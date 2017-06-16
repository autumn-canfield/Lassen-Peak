;;;This file is included by loader.asm right after entering long mode.
;;;This code sets things up then jumps to the kernel.
%include "boot-info-table.asm" ;

;;;Zero 0x000 to 0x500 (boot-info-table)
xor eax, eax
mov ecx, 0xa0
xor edi, edi
rep stosq

pop rdx ;Number of entries in memory map.
map_acpi_regions:
	mov esi, 0x0500
	.loop:
		mov eax, [esi + 0x10]
		cmp eax, 0x03
		je .map
		cmp eax, 0x04
		je .map
		add esi, 0x18
		sub rdx, 0x01
		jz .end
		jmp .loop
	.map:
		mov rdi, [esi]
		mov rcx, [esi + 0x08]
		call map_memory
		add esi, 0x18
		sub rdx, 0x01
		jmp .loop
	.end:

search_for_rsdp:
	xor edi, edi
	mov di, [abs 0x040e] ;EBDA address
	add rdi, 0xf ;Round up to a 16 byte boundary
	and rdi, ~0xf
	mov rax, 0x2052545020445352
	mov rcx, 0x40 ;The magic number will be in the first kib -> 0x40 places.

	.loop:
	cmp [rdi], rax
	je .found
	add rdi, 0x10 ;Magic number is always on a 16 byte boundary
	sub rcx, 0x01
	jnz .loop
	cmp rdi, 0xffff0 ;Print error and halt if we can't find it the second time.
	je .notfound

	;; Wasn't in the ebda, trying 0xe0000 to 0xfffff
	mov rdi, 0x00000000000e0000
	mov rcx, 0x0000000000010000
	jmp .loop

	.notfound:
		mov rsi, rsdp_not_found_message
		jmp panic
	.found:

read_rsdp:
	mov rsi, rdi
	mov rcx, 0x14
	call test_checksum

	test byte [rsi+0x0f], 0xff ;Test revision field
	jz .noxsdt

	.xsdt:
		mov ecx, [rsi+0x14]
		call test_checksum
		mov rax, [rsi+0x18]
		jmp read_xsdt
	.noxsdt:
		mov eax, dword [rsi+0x10]

%define rsdt_header_size 36
read_rsdt:
	mov rsi, rax
	mov ecx, [rsi+0x04]
	call test_checksum

	sub ecx, rsdt_header_size
	shr ecx, 2
	xor ebx, ebx
	xor edi, edi ;Table flags
	.loop:
		mov eax, [rsi+rbx*4+rsdt_header_size]
		mov ebp, [rax]
			;push rbx
			;push rsi
			;mov [acpi_table_name], rbp
			;mov ebx, 0x07
			;mov rsi, acpi_table_name
			;call print_64
			;call print_newline
			;pop rsi
			;pop rbx
		cmp ebp, 0x43495041 ;APIC
		jne .continue
			or edi, 0x01
			mov [madt_address], rax
		.continue:
		add ebx, 1
		sub ecx, 1
		jnz .loop
	jmp test_table_flags

read_xsdt:
	mov rsi, rax
	mov ecx, [rsi+0x04]
	call test_checksum

	sub ecx, rsdt_header_size
	shr ecx, 3
	xor ebx, ebx
	xor edi, edi ;Table flags
	.loop:
		mov rax, [rsi+rbx*8+rsdt_header_size]
		mov ebp, [rax]
			;push rbx
			;push rsi
			;mov [acpi_table_name], rbp
			;mov ebx, 0x07
			;mov rsi, acpi_table_name
			;call print_64
			;call print_newline
			;pop rsi
			;pop rbx
		cmp ebp, 0x43495041 ;APIC
		jne .continue
			or edi, 0x01
			mov [madt_address], rax
		.continue:
		add ebx, 1
		sub ecx, 1
		jnz .loop

test_table_flags:
	mov rsi, madt_not_found_message
	test rdi, 0x01
	jz panic

%define madt_header_size 44
read_madt:
	mov rsi, [madt_address]
	mov ecx, [rsi+0x04]
	call test_checksum

	mov r15d, [rsi+36] ;local apic address
	mov [boot_info_table_addr+lapic_address], r15

	sub ecx, madt_header_size
	add rsi, madt_header_size
	xor r15, r15
	mov bl, 0x07
	mov ebp, 1 ;Don't mark bsp for startup
	.loop:
		mov r15, [rsi]
		;call print_r15_64
		and r15, 0xff
		;jz .continue
		test r15b, r15b
		jnz .not_lapic
			cmp [rsi+4], dword 0x00000001
			jne .continue
			mov r13d, [boot_info_table_addr+processor_count]
			add [boot_info_table_addr+processor_count], dword 1
			shl r13, 1
			xor r14, r14
			mov r14b, [rsi+3]
			mov [boot_info_table_addr+processor_list+r13+1], r14b
			mov r14b, [rsi+2]
			mov [boot_info_table_addr+processor_list+r13], r14b
			test ebp, ebp
			jz .add_ap_entry
				xor ebp, ebp
				jmp .continue
			.add_ap_entry:
				push rcx
				mov rcx, r14
				and rcx, 0x3f
				shr r14, 6
				mov r12, 1
				shl r12, cl
				or [processor_started_flags+r14*8], r12
				pop rcx
				jmp .continue
		.not_lapic:
		cmp r15b, 0x01
		jne .not_ioapic
			;push rbx
			;push r15
			;	mov rbx, 0x07
			;	mov r15b, [rsi+2]
			;	call print_r15_64
			;	call print_newline
			;pop r15
			;pop rbx
			mov r14d, [rsi+4]
			mov [boot_info_table_addr+ioapic_address], r14
			mov r14b, [rsi+2]
			mov [boot_info_table_addr+ioapic_id], r14b
	 jmp .continue
		.not_ioapic:
		cmp r15b, 0x02
		jne .not_override
			mov r13d, [rsi+4]
			mov r14b, [rsi+3]
			cmp r14b, 0x00
			jne .keyboard_irq
				mov [boot_info_table_addr+pit_irq], r13b
			.keyboard_irq:
			cmp r14b, 0x01
			jne .continue
				mov [boot_info_table_addr+keyboard_irq], r13b
		.not_override:
		.continue:
		movzx rax, byte [rsi+1]
		add rsi, rax
		sub ecx, eax
		jg .loop

		mov rdi, [boot_info_table_addr+ioapic_address]
		mov rcx, 0x1000
		call map_memory
		mov rdi, [boot_info_table_addr+lapic_address]
		mov rcx, 0x1000
		call map_memory
		mov eax, 0x01ef ;;Enable lapic and set spurious irq to 0xef.
		mov [rdi+0xf0], eax

setup_pit:
	mov rsi, pit_isr
	mov edi, 0x30
	call install_isr
	mov al, [boot_info_table_addr+pit_irq]
	shl al, 1
	add al, 0x10
	mov rdi, [boot_info_table_addr+ioapic_address]
	mov [rdi], al
	mov ebx, 0x00000030
	mov [rdi+0x10], ebx
	add al, 1
	mov [rdi], al
	xor ebx, ebx
	mov [rdi+0x10], ebx

;;Send INIT IPIs
mov rdi, [boot_info_table_addr+lapic_address]
xor edx, edx
init_loop:
	add edx, 1
	cmp edx, [boot_info_table_addr+processor_count]
	jl .continue
		jmp .done
	.continue:

	xor eax, eax
	mov al, [boot_info_table_addr+processor_list+edx*2+1]
	shl eax, 0x18
	mov [rdi+0x310], eax
	mov ebx, 0x00004500
	mov [rdi+0x300], ebx
	jmp init_loop
	.done:

	;rdtsc
	;mov [tsc_value], eax
	;mov [tsc_value+4], edx
	mov eax, 0x002e9c30 ;10ms
	call pit_wait

	;mov ecx, 0x2710
	;.wait_loop:
	;	in al, 0x80
	;	loop .wait_loop
	
	;rdtsc
	;shl rdx, 0x20
	;or rdx, rax
	;sub rdx, [tsc_value]
	;mov r15, rdx
	;mov ebx, 0x07
	;call print_r15_64
	;cli
	;hlt

;;Send SIPIs
mov rdi, [boot_info_table_addr+lapic_address]
xor edx, edx
sipi_loop:
	add edx, 1
	cmp edx, [boot_info_table_addr+processor_count]
	jge .done
	
	mov al, [boot_info_table_addr+processor_list+edx*2+1]
	shl eax, 0x18
	mov [rdi+0x310], eax
	mov ebx, 0x00004609
	mov [rdi+0x300], ebx
	jmp sipi_loop
	.done:

	mov eax, 0x0000ef30 ;200us
	call pit_wait

;;Send second SIPIs if needed.
xor edx, edx
second_sipi_loop:
	add edx, 1
	cmp edx, [boot_info_table_addr+processor_count]
	jge .done

	xor r11, r11
	mov r11b, [boot_info_table_addr+processor_list+edx*2+1]
	mov ebx, r11d
	mov ecx, r11d
	and cl, 0x3f
	shr ebx, 6
	mov eax, 1
	shl rax, cl
	test [processor_started_flags+ebx*8], rax
	jz .continue
		shl r11, 0x18
		mov [rdi+0x310], r11d
		mov ebx, 0x00004609
		mov [rdi+0x300], ebx
	.continue:
		jmp second_sipi_loop
	.done:

	mov eax, 0x0000ef30 ;200us
	call pit_wait

xor edx, edx
mov edx, [boot_info_table_addr+processor_count]
mov rsi, boot_info_table_addr+processor_list
mov rdi, rsi
check_ap_loop:
	sub edx, 1
	js .done

	or r11, r11
	mov r11b, [rsi+1]
	mov ebx, r11d
	mov ecx, r11d
	and cl, 0x3f
	shr ebx, 6
	mov eax, 1
	shl rax, cl
	test [processor_started_flags+ebx*8], rax
	jnz .remove_entry
		mov ax, [rsi]
		mov [rdi], ax
		add rdi, 2
		add rsi, 2
		jmp check_ap_loop
	.remove_entry:
		sub [boot_info_table_addr+processor_count], dword 1
		add rsi, 2
		jmp check_ap_loop
	.done:

;mov rsi, clock_speed_too_slow
;sub r12, [tsc_value]
;jz panic
;mov rsi, clock_speed_too_fast
;xor edx, edx
;mov rax, 0x2481dc8b6
;cmp r12, rax
;jge panic
;div r12

;mov ebx, 0x07
;mov r15, [processor_started_flags]
;call print_r15_64
;cli
;hlt

;; Jump to kernel
mov rax, 0xffffff7fbf801000
jmp rax


;;Test ACPI checksum at rsi with a length of rcx bytes.
test_checksum:
	push rsi
	push rcx
	xor rax, rax
	xor rbx, rbx
	.loop:
		lodsb
		add rbx, rax
		sub rcx, 0x01
		jnz .loop
	or bl, bl
	jz .end
		mov rsi, bad_acpi_checksum_message
		jmp panic
	.end:
	pop rcx
	pop rsi
	ret

;;;eax: 0x00aaaa30, where a = number of ticks.
pit_wait:
	out 0x43, al
	shr eax, 8
	out 0x40, al
	shr eax, 8
	out 0x40, al
	sti
	hlt
	cli
	ret

panic:
	mov eax, 0x4f00
	xor ecx, ecx
	mov edi, 0xb8000
	.clear_loop:
		mov [rdi+rcx*2], eax
		add ecx, 1
		cmp ecx, 0xfa0
		jl .clear_loop
	mov edi, 0xb8f00
	xor ecx, ecx
	mov eax, 0x4f00
	.print_loop:
		mov al, [rsi+rcx]
		or al, al
		jz .end
		mov [rdi+rcx*2], word ax
		add rcx, 1
		jmp .print_loop
	.end:
	cli
	hlt

;; Prints string in rsi using color in bl. rcx = string length
print_64:
	push rcx
	push rax
	push rdx
	mov edx, [cursor_location_64]
	xor ecx, ecx
	mov eax, 0x0700
	.loop:
		mov al, [rsi+rcx]
		or al, al
		jz .end
		mov [0xb8000+rdx+rcx*2], word ax
		add [cursor_location_64], dword 0x02
		add rcx, 0x01
		jmp .loop
	.end:
	pop rdx
	pop rax
	pop rcx
	ret

print_newline:
	push rdx
	push rbx
	push rax
	xor edx, edx
	mov eax, [cursor_location_64]
	mov ebx, 0x000000a0
	div bx
	add [cursor_location_64], dword 0xa0
	sub [cursor_location_64], edx
	pop rax
	pop rbx
	pop rdx
	ret

;; Print r15 using color in bl.
print_r15_64:
	push rcx
	push r15
	push rdi
	push rdx
	push r9
	push r8
	mov rdi, 0xb8000
	add edi, [cursor_location_64]
	mov ecx, 0x10
	mov r8d, 0x30
	mov r9d, 0x57 
	cld
	.loop:
		mov rdx, r15
		shr rdx, 0x3c
		cmp dl, 0x09
		cmovle eax, r8d
		cmovg eax, r9d
		add rax, rdx
		mov ah, bl
		stosw
		shl r15, 4
		add [cursor_location_64], dword 0x02
		sub rcx, 0x01
		jnz .loop
	pop r8
	pop r9
	pop rdx
	pop rdi
	pop r15
	pop rcx
	ret

;0xffff000000000000 ;sign extend
;0x0000ff8000000000 ;pml4
;0x0000007fc0000000 ;pdp
;0x000000003fe00000 ;pd
;0x00000000001ff000 ;pt
;0x0000000000000fff ;offset
;0x000ffffffffff000
%define min_free_page_address 0x17000
%define pml4_address 0x10000

;;;rdi: address  rcx: length
map_memory:
	push rdi
	push rax
	push rcx
	push rbx
	add rcx, rdi
	mov rbx, 0xffffffffffe00000
	and rdi, rbx
	.pml4:
		mov rbx, pml4_address
		mov rax, 0x0000ff8000000000
		and rax, rdi
		shr rax, 36
		add rax, rbx
		call map_page_entry
	.pdp:
		mov rax, 0x000ffffffffff000
		and rbx, rax
		mov rax, 0x0000007fc0000000
		and rax, rdi
		shr rax, 27
		add rax, rbx
		call map_page_entry
	.pd:
		mov rax, 0x000ffffffffff000
		and rbx, rax
		mov rax, 0x000000003fe00000
		and rax, rdi
		shr rax, 18
		add rax, rbx
		mov [rax], rdi
		or qword [rax], 0x83
		add rdi, 0x200000
		cmp rdi, rcx
		jl .pml4
	pop rbx
	pop rcx
	pop rax
	pop rdi
	ret

;;Ensures that the entry has a table allocated.
;;rax: entry_address  (return)rbx: entry_value
map_page_entry:
	mov rbx, [rax]
	test rbx, 0x01
	jnz .exit
		mov rbx, [next_free_page]
		sub qword [next_free_page], 0x1000
		or rbx, 0x3
		mov [rax], rbx
		xor rbx, 0x3
	.exit:
	ret

;;rsi: isr_address  rdi:irq
install_isr:
	push rcx
	shl rdi, 4
	add rdi, 0x17000
	mov rcx, 0xffff
	and rcx, rsi
	or ecx, 0x00080000
	mov [rdi], ecx
	mov rcx, 0xffff0000
	and rcx, rsi
	or rcx, 0x8e00
	mov [rdi+4], ecx
	mov rcx, rsi
	shr rcx, 0x20
	mov [rdi+8], ecx
	pop rcx
	ret

;;11932(0x2e9c) clocks = 10.0001508571 ms (0x00000002540e3149 ps)
;;  239(0x00ef) clocks = 200.304787351 us (0x000000000bf06893 ps)
;; diff = 0x2481dc8b6 ps

;===== in 0x80 =====
;4e25 --bochs
;1f6dc49 --qemu kvm host
;103683c --qemu

;===== pit irq =====
;f976d4 -- bochs

;1dd4049c
;1f8dc0ea
;220e63c0

;3d641091
;3d1af543
;3c04dfbc
;387dd153
;3033132c
;302d4421

pit_isr:
	push rax
	push rdx
	rdtsc
	shl rdx, 32
	or rdx, rax
	mov rax, [tsc_value]
	sub rdx, rax
	mov [tsc_value], rdx
	mov eax, [boot_info_table_addr+lapic_address] ;EOI
	mov [rax+0xb0], eax
	pop rdx
	pop rax
	iretq

interrupt_routine:
	mov rsi, interrupt_message
	mov rbx, 0x07
	call print_64
	cli
	hlt

spic_spurious_isr:
	mov al, 0x20
	out 0x20, al ;Send EOI to Master PIC
mpic_spurious_isr:
spurious_isr:
	iretq

page_fault_isr:
	mov rsi, page_fault_message
	mov rbx, 0x4f
	call print_64
	mov r15, cr2
	call print_r15_64
	cli
	hlt

madt_address: dq 0

;lapic_address: dq 0
;ioapic_address: dq 0
;ioapic_id: dd 0

;processor_count: dd 0
;processor_list:
;times 256 db 0, 0 ;processor id, apic id
processor_started_flags: dq 0, 0, 0, 0 ;1 = needs to be started

tsc_value: dq 0

;pit_irq: db 0
;keyboard_irq: db 1

cursor_location_64: dd 0x00000000
acpi_table_name: dd 0
db 0 ;acpi_table_name trailing null.
next_free_page: dq 0x79000 ;Grows down

interrupt_message: db "Encountered interrupt!", 0x00
page_fault_message: db "Boot: Page fault! CR2:", 0x00
rsdp_not_found_message: db \
"								Sorry, we couldn't find the RSDP!							  ", 0x00
bad_acpi_checksum_message: db \
"					  Sorry, an ACPI table had an invalid checksum!						", 0x00
madt_not_found_message: db \
"								Sorry, we couldn't find the MADT!							  ", 0x00
clock_speed_too_slow: db \
"								Sorry, your CPU isn't fast enough!							 ", 0x00
clock_speed_too_fast: db \
"									Sorry, your CPU is too fast!								 ", 0x00

