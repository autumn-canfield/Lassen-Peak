;;; Map of image
;;; 0x0000 len=0x0200 phys=0x07c00 Bootsector
;;; 0x0200 len=0x1200 phys=0x07e00 Second Stage
;;; 0x1400 len=0x1000 phys=0x09000 AP Init
;;; 0x2400 len=0x1000 phys=0x0a000 Kernel Data (GDT)
;;; 0x3400 len=0x3000 phys=0x0b000 Kernel
;;;
;;; Map of physical memory below 1 mib:
;;; 0x00000000		 - 0x03ff Default interrupt vector table
;;; 0x00000400		 - 0x04ff Bios data area
;;; 0x00000500		 - (0x500 + 0x18*num_entries) Memory map
;;; 0x0000????		 - 0x7bff Stack
;;; 0x00007c00		 - 0x9fff Bootloader
;;; 0x0000a000		 - 0xafff GDT & kernel data
;;; 0x0000b000		 - 0xefff Kernel (3 pages)
;;; 0x0000f000		 - 0x0000ffff Free (3 pages)
;;; 0x00010000		 - 0x00010fff Default PML4
;;; 0x00011000		 - 0x00011fff Default PDP
;;; 0x00012000		 - 0x00012fff Default PD (first 2mib identity mapped)
;;; 0x00013000		 - 0x00013fff Free
;;; 0x00014000		 - 0x00014fff Kernel PDP
;;; 0x00015000		 - 0x00015fff Kernel PD
;;; 0x00016000		 - 0x00016fff Kernel PT
;;; 0x00017000		 - 0x00017fff IDT
;;; 0x00018000		 - 0x0007ffff Guaranteed free (104 pages)
;;; 0x00080000		 - 0x0009fbff Possibly free depending on EBDA
;;; 0x0009fc00 (typ) - 0x0009ffff Extended bios data area
;;; 0x000a0000		 - 0x000bffff Video memory
;;; 0x000c0000		 - 0x000fffff Rom area
;;;
;;; 0x00000000 contains info as specified in "boot-info-table.asm"
;;;
;;; The default page tables map the kernel to 0xffffff7fbf800000.
;;; 
;;; Once the kernel has setup an idt, created a new stack, and is done with the
;;; memory map, the memory from 0x0000 to 0x9000 can be used for other purposes.
;;;
;;; If the kernel grows bigger than 16 kib we can expand it by moving the
;;; initial page tables to higher addresses and reading more sectors for the
;;; kernel. However, if it grows larger than 1 mib we have to either load the
;;; rest in first part of the kernel, or switch to unreal mode.
;;; 
;;; Initial page tables identity-map memory from 0x00000000 to 0x40000000.
;;;
;;; The last entry of the PML4 is mapped to itself. Meaning that addresses from
;;; ffffff8000000000 to ffffffffffffffff can be used to modify any entry in the
;;; page tables.

bits 16
org 0x7c00

start:
jmp 0x0000:_start
_start:
xor ax, ax ;Zero segment registers
mov ss, ax
mov ds, ax
mov es, ax

mov sp, 0x7c00 ;nb The stack doesn't overwrite the bootsector because it grows down.

and dl, 0xff ;Push drive number to the stack.
push dx

mov ax, 0x0003 ;Change vga settings
int 0x10

mov ax, 0x1112 ;Set 8x8 font => 80x50
xor bl, bl
int 0x10

mov ax, 0x1003 ;Disable blinking so background can be all 16 colors.
xor bl, bl
int 0x10

mov ah, 0x01 ;Hide the cursor
mov cx, 0x2d0e
int 0x10

;;Set vga dac palette registers
;;The register numbers don't map nicely to the actual indices used when actually
;;writing to the terminal. 0x00 through 0x05 have the same register number as
;;index, as does 0x07, but the index 0x06 is in register 0x14, and 0x09 through
;;0x0f are in registers 0x39 through 0x3f.
mov ax, 0x1012
mov bx, 0x01
mov cx, 0x05
mov dx, vga_color_palette_data
int 0x10
mov bx, 0x14
mov cx, 0x01
mov dx, vga_color_palette_data + 0xf
int 0x10
mov bx, 0x07
mov cx, 0x01
mov dx, vga_color_palette_data + 0x12
int 0x10
mov bx, 0x38
mov cx, 0x08
mov dx, vga_color_palette_data + 0x15
int 0x10

;;Uncomment to print all combinations of background and foreground colors.
;mov ax, 0xb800
;mov fs, ax
;xor ax, ax
;xor bx, bx
;color_loop:
;	mov [fs:bx], ax
;	add bx, 0x0002
;	add ax, 0x0101
;	cmp al, 0xff
;	jne .end
;	mov al, 0x00
;	.end:
;	cmp bx, 0x1000
;	jne color_loop
;cli
;hlt

;;Enable A20
xor ax, ax
not ax
mov es, ax
call test_a20
jne a20_enabled
enable_a20:
	mov ax, 0x2401
	int 0x15
	call test_a20
	jne a20_enabled
	mov si, a20_error_message
	jmp panic16
test_a20:
	mov word [0x7dfe], 0xabcd
	mov cx, [es:0x7e0e]
	cmp cx, 0xabcd
	ret
a20_enabled:
xor ax, ax
mov es, ax

;;Read second stage and kernel from drive
;;If we supported real floppy disks we would retry in case of failure.
mov si, drive_read_error_message
pop dx
mov ax, 0x0231 ;0x6400 bytes (0x31 sectors)
mov cx, 0x0002 ;Cylinder, Sector (one indexed)
mov dh, 0x00	;Head
mov bx, 0x7e00 ;Destination address
int 0x13
jc panic16

;;Check if long mode and invariant tsc are supported
mov si, cpu_not_supported_message
pushfd
pushfd
mov ecx, [esp]
xor dword [esp],0x00200000
popfd
pushfd
pop eax
xor eax, ecx
jz panic16
popfd
mov eax, 0x80000000
cpuid
cmp eax, 0x80000007
jb panic16
mov eax, 0x80000001
cpuid
test edx, 1<<29
jz panic16
mov eax, 0x80000007
cpuid
test edx, 1<<8
jz panic16

jmp second_stage

;;;Print string in si to the top left corner using attributes in bl
print:
	mov ax, 0xb800
	mov es, ax
	xor di, di
	.loop:
	lodsb
	or al, al
	jz .done
	mov ah, bl
	stosw
	jmp .loop
	.done:
	xor ax, ax
	mov es, ax
	ret

;;;Print error message in si and halt
panic16:
	mov bl, 0x4f
	call print
	cli
	.hlt:
	hlt
	jmp .hlt

vga_color_palette_data: ;RGB, from 0x00 to 3f
db 0x04, 0x14, 0x2e ;Sapphire
db 0x1f, 0x2c, 0x1a ;Bud Green
db 0x3c, 0x21, 0x00 ;Tangerine
db 0x24, 0x00, 0x04 ;Sangria
db 0x2e, 0x1f, 0x37 ;Lavender
db 0x06, 0x04, 0x03 ;Licorice
db 0x31, 0x2f, 0x27 ;Khaki
db 0x0d, 0x09, 0x07 ;Bistre
db 0x24, 0x2d, 0x2f ;Pewter Blue
db 0x14, 0x1e, 0x10 ;Fern Green
db 0x35, 0x2c, 0x1f ;Light French Beige
db 0x37, 0x17, 0x20 ;Blush
db 0x18, 0x14, 0x36 ;Majorelle Blue
db 0x3c, 0x30, 0x0c ;Saffron
db 0x3f, 0x3f, 0x3f ;White

a20_error_message: db "Error enabling A20!", 0x00
cpu_not_supported_message: db "CPU not supported!", 0x00
drive_read_error_message: db "Error reading from disk!", 0x00
mem_detect_error_message: db "Error detecting memory!", 0x00

times 510-($-start) db 0 ;Pad first boot sector to 512 bytes.
dw 0xaa55 ;Boot signature.

second_stage:

;;Place e820 memory map at 0x500
;;
;;Format:
;;0x0000000000000000 Base address
;;0x0000000000000000 Length of region
;;0x00000000			Type of region
;;0x00000000			Padding
;;
;;Values for Type field:
;;0x01 Available
;;0x02 Reserved
;;0x03 ACPI (reclaimable)
;;0x04 ACPI NVS
;;Treat all others as reserved.

mov di, 0x500
xor ebx, ebx
xor bp, bp ;number of entries
mov edx, 0x534d4150
mov ecx, 0x00000018
mov eax, 0x0000e820
int 0x15
mov si, mem_detect_error_message
jc panic16
inc bp

mem_map_loop:
	add di, 0x18
	mov edx, 0x534d4150
	mov eax, 0x0000e820
	mov ecx, 0x00000018
	int 0x15
	pushfd
	inc bp
	or ebx, ebx
	jz mem_map_done
	popfd
	jnc mem_map_loop
	jc mem_map_done
	mov si, mem_detect_error_message
	jmp panic16
mem_map_done:
	xor di, di ;Save number of entries padded to 64 bits.
	push di
	push di
	push di
	push bp

;print_mem_map:
;	mov si, 0x500
;	xor cx, cx
;
;	.loop:
;		;mov bx, [si + 0x10]
;		;cmp bx, 0x01 ;Filter out a particular type
;		;jne .continue
;
;		mov bx, [si + 0x06]
;		call print_bx
;		mov bx, [si + 0x04]
;		call print_bx
;		mov bx, [si + 0x02]
;		call print_bx
;		mov bx, [si]
;		call print_bx
;
;		add di, 0x02
;		mov bx, [si + 0x0e]
;		call print_bx
;		mov bx, [si + 0x0c]
;		call print_bx
;		mov bx, [si + 0x0a]
;		call print_bx
;		mov bx, [si + 0x08]
;		call print_bx
;
;		add di, 0x02
;		mov bx, [si + 0x10]
;		call print_bx
;
;		add di, 0x54
;	.continue
;		add si, 0x18
;		add cx, 1
;		cmp cx, bp
;		jl .loop
;	cli
;	hlt

mov ax, 0xec00 ;Detect Target Operating Mode (Lets BIOS optimize for long mode)
mov bx, 0x0002 ;Long Mode target only
int 0x15

;;;Remap PIC to avoid spurrious irqs.
;;;Master PIC spurious irq: 0xed
;;;Slave PIC spurious irq: 0xee
cli
mov al, 0x11 ;;Start PIC initialization
out 0x20, al
out 0xa0, al
mov al, 0xe6 ;;Remap the PICs' IRQs
out 0x21, al
mov al, 0xe7
out 0xa1, al
mov al, 0x04 ;;Setup master/slave arrangement
out 0x21, al
mov al, 0x02
out 0xa1, al
mov al, 0x01 ;;Set PICs to 8086 mode
out 0x21, al
out 0xa1, al
mov al, 0xff ;;Disable PICs
out 0xa1, al
out 0x21, al
nop
nop

;;;Set up page tables
mov ax, 0x1000		;;Zero 0x10000 to 0x18000
mov es, ax
mov ecx, 0x00002000
xor edi, edi
xor eax, eax
cld
rep stosd
xor di, di			 ;;Add first entry in PML4
mov eax, 0x00011003
mov [es:di], eax
mov eax, 0x00012003 ;;Add first entry in PDP
mov [es:di + 0x1000], eax
mov eax, 0x00000083 ;;Add all PD entries
mov cx, 0x200
fill_page_table:
mov [es:di + 0x2000], eax
add eax, 0x200000
add di, 0x0008
loop fill_page_table
mov di, 0x0ff0		;;Add second to last entry in PML4 for the kernel
mov eax, 0x00014003
mov [es:di], eax
mov di, 0x4ff0		;;Add second to last entry in PDP for the kernel
mov eax, 0x00015003
mov [es:di], eax
mov di, 0x5fe0		;;Add fourth to last entry in PD
mov eax, 0x00016003
mov [es:di], eax
mov eax, 0x0000a003 ;;Add first four entries to PT
mov cx, 0x0004
mov di, 0x6000
fill_2nd_page_table:
mov [es:di], eax
add eax, 0x1000
add di, 0x0008
loop fill_2nd_page_table
mov di, 0x0ff8		;;Add last entry in PML4 for recursive paging
mov eax, 0x00010003
mov [es:di], eax

xor ax, ax
mov es, ax

lidt [dummy_idt]

mov eax, 0xa0		 ;;Set PAE and PGE bits
mov cr4, eax
mov ebx, 0x00010000 ;;Load CR3 with address of PML4
mov cr3, ebx
mov ecx, 0xc0000080 ;;Enable long mode by setting LME and LMA in the EFER MSR
rdmsr
or eax, 0x00000100
wrmsr
mov ebx, cr0		  ;;Set protected mode and paging bits
or ebx, 0x80000001
mov cr0, ebx

lgdt [gdt_pointer]
jmp 8:bootloader_64
bits 64
bootloader_64:
	mov ax, 0x10 ;;Initialize segment registers.
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	xor ax, ax
	mov ss, ax

	mov edi, 0x17000 ;;Setup IDT
	mov rax, 0x00000e0000080000
	xor ebx, ebx
	mov ecx, 0x100
	.idt_loop:
		mov [rdi], rax
		mov [rdi+0x08], rbx
		add edi, 0x10
		sub ecx, 0x01
		jnz .idt_loop
	mov rsi, page_fault_isr
	mov rdi, 0x0e
	call install_isr
	mov rsi, mpic_spurious_isr
	mov rdi, 0xed
	call install_isr
	mov rsi, spic_spurious_isr
	mov rdi, 0xee
	call install_isr
	mov rsi, spurious_isr
	mov rdi, 0xef
	call install_isr
	lidt [idt_pointer]

	;;Enable SSE
	;mov rax, cr0
	;or al, 0x6
	;xor al, 0x4
	;mov cr0, rax
	;mov rax, cr4
	;or ax, 0x600
	;mov cr4, rax

	%include "bootloader-64.asm"

bits 16

;;;Print bx in hex at position in di. (Commented to save space when not debugging.)
print_bx:
	push si
	push bp
	push cx
	mov ax, 0xb800
	mov es, ax

	mov cx, 0x4
	mov si, 0x30
	mov bp, 0x57

	.loop:
	mov dl, bh
	shr dl, 4
	cmp dl, 0x09
	cmovle ax, si
	cmovg ax, bp
	add al, dl
	mov ah, 0x07
	stosw
	shl bx, 4
	loop .loop

	xor ax, ax
	mov es, ax
	pop cx
	pop bp
	pop si
	ret

align 16
dummy_idt:
dw 0x0000
dd 0x00000000
align 16
idt_pointer:
dw 0x1000
dq 0x0000000000017000
align 16
gdt_pointer:
dw 0x0020
dq 0x000000000000a000

times 0x1200-($-second_stage) db 0
ap_initialization: ;0x9000
xor ax, ax ;;Zero segment registers
mov ss, ax
mov ds, ax
mov es, ax

lidt [dummy_idt]

mov eax, 0xa0		 ;;Set PAE and PGE bits
mov cr4, eax
mov ebx, 0x00010000 ;;Load CR3 with address of PML4
mov cr3, ebx
mov ecx, 0xc0000080 ;;Enable long mode by setting LME and LMA in the EFER MSR
rdmsr
or eax, 0x00000100
wrmsr
mov ebx, cr0		  ;;Set protected mode and paging bits
or ebx, 0x80000001
mov cr0, ebx
lgdt [gdt_pointer]

jmp 8:ap_initialization_64
bits 64
ap_initialization_64:
bits 64

mov rsi, [lapic_address]
mov ecx, [rsi+0x20]
shr ecx, 0x18
mov eax, ecx
and cl, 0x3f
shr eax, 6
mov esi, 1
shl rsi, cl
not rsi
and [processor_started_flags+eax*8], rsi

;;;Enable SSE
;mov rax, cr0
;or al, 0x6
;xor al, 0x4
;mov cr0, rax
;mov rax, cr4
;or ax, 0x600
;mov cr4, rax

cli
hlt

times 0x1000-($-ap_initialization) db 0

