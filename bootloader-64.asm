;;; This file is included by loader.asm right after entering long mode.
;;; This code sets things up then jumps to the kernel.

pop rcx ; Number of entries in memory map.

;; Jump to kernel
mov rax, 0xffffff7fbf800000
jmp rax

search_for_rsdp:
   xor edi, edi
   mov di, [abs 0x040e] ;EBDA address
   add rdi, 0xf ;;Round up to a 16 byte boundary
   and rdi, ~0xf
   mov rax, 0x2052545020445352
   mov rcx, 0x40 ;The magic number will be in the first kib so we only need to test 0x40 places.
   cld
   .loop:
   scasq
   je .found
   add rdi, 0x8 ;Magic number is always on a 16 byte boundary
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
   sub rsi, 0x08
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
   .loop:
      mov eax, [rsi+rbx*4+rsdt_header_size]
      mov ebp, [rax]
      cmp ebp, 0x43495041 ;APIC
      je read_madt
      add ebx, 1
      sub ecx, 1
      jnz .loop
   mov rsi, madt_not_found_message
   jmp panic

read_xsdt:
   mov rsi, rax
   mov ecx, [rsi+0x04]
   call test_checksum

   sub ecx, rsdt_header_size
   shr ecx, 3
   xor ebx, ebx
   .loop:
      mov rax, [rsi+rbx*8+rsdt_header_size]
      mov ebp, [rax]
      cmp ebp, 0x43495041 ;APIC
      je read_madt
      add ebx, 1
      sub ecx, 1
      jnz .loop
   mov rsi, madt_not_found_message
   jmp panic

%define madt_header_size 44
read_madt:
   mov esi, eax
   mov ecx, [rsi+0x04]
   call test_checksum

   ;mov r15d, [rsi+36] ;local apic address

   sub ecx, madt_header_size
   add rsi, madt_header_size
   xor r15, r15
   mov bl, 0x07
   .loop:
      mov r15, [rsi]
      call print_r15_64
      and r15, 0xff
      jz .continue
      add [cursor_location_64], dword 2
      cmp r15, 0x02
      je .two
         mov r15d, [rsi+8]
         call print_r15_64
      jmp .continue
      .two:
         movzx r15, word [rsi+8]
         call print_r15_64
      .continue:
      call print_newline
      movzx rax, byte [rsi+1]
      add rsi, rax
      sub ecx, eax
      jg .loop

   mov r14, 0xfee00020
   mov r15d, [r14]
   mov bl, 0x07
   call print_r15_64

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

panic:
   mov eax, 0x4f00
   xor ecx, ecx
   mov edi, 0xb8000
   .clear_loop:
      mov [rdi+rcx*2], eax
      add ecx, 1
      cmp ecx, 0x7d0
      jl .clear_loop
   mov edi, 0xb8780
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
   pop r15
   pop rcx
   ret

cursor_location_64: dd 0x00000000
acpi_table_name: dd 0
db 0 ;acpi_table_name trailing null.
next_free_page: dq 0x18000

no_acpi_region_in_memory_map: db \
"                Sorry, the memory map didn't have an ACPI region!               ", 0x00
acpi_region_too_large: db \
"                      Sorry, the ACPI region is too large!                      ", 0x00
rsdp_not_found_message: db \
"                        Sorry, we couldn't find the RSDP!                       ", 0x00
bad_acpi_checksum_message: db \
"                 Sorry, an ACPI table had an invalid checksum!                  ", 0x00
madt_not_found_message: db \
"                        Sorry, we couldn't find the MADT!                       ", 0x00

