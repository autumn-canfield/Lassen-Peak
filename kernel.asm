bits 64
default rel
org 0xffffff7fbf800000

%include "kernel_data.asm"

kernel_entry:

mov eax, 0x00000001
cpuid
and edx, 0x00000100
jnz cpu_has_apic
   mov rsi, no_apic_message
   call panic
cpu_has_apic:

;; Get CPU Vendor ID String
mov eax, 0x00000000
cpuid
mov rdi, cpu_vendor_string
mov [rdi], ebx
mov [rdi+0x04], edx
mov [rdi+0x08], ecx

mov rsi, cpu_vendor_string
mov rbx, 0x07
call print
cli
hlt

interrupt_routine:
   mov rsi, interrupt_message
   mov rbx, 0x07
   call print
   iretq

page_fault_isr:
   mov rsi, page_fault_message
   mov rbx, 0x4f
   call print
   mov r15, cr2
   call print_r15
   cli
   hlt

print_newline:
   push rdx
   push rbx
   push rax
   xor edx, edx
   mov eax, [cursor_location]
   mov ebx, 0x000000a0
   div bx
   add [cursor_location], dword 0xa0
   sub [cursor_location], edx
   pop rax
   pop rbx
   pop rdx
   ret

print_space:
   mov [cursor_location + 0xb8000], word 0x2002
   add [cursor_location], dword 0x02
   ret

panic:
   mov eax, 0x4f
   call clear_screen
   mov [cursor_location], dword 0x780
   mov ebx, 0x4f
   call print
   cli
   hlt

;;; Prints string in rsi using rbx for color.
print:
   mov rdi, 0xb8000
   add edi, [cursor_location]
   mov ah, bl
   cld
   .loop:
      lodsb
      or al, al
      jz .end
      stosw
      add [cursor_location], dword 0x02
      jmp .loop
   .end:
   ret

; Clear screen with color in eax
clear_screen:
   mov ecx, 0x7d0; 80*25 columns*rows
   mov rdi, 0xb8000
   shl eax, 8
   .loop:
      stosw
   loop .loop
   mov [cursor_location], dword 0
   ret

;;; Prints r15 in hex using rbx for color.
print_r15:
   push rcx
   mov rdi, 0xb8000
   add edi, [cursor_location]
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
      add [cursor_location], dword 0x02
      sub rcx, 0x01
      jnz .loop
   pop rcx
   ret

cursor_location: dd 0x00000000
ebda_location: dq 0
cpu_vendor_string: times 3 dd 0
db 0x00 ;cpu_vendor_string trailing null.
interrupt_message: db "Encountered interrupt!", 0x00
page_fault_message: db "Page fault! CR2:", 0x00
message: db "Miles rocks!", 0x00
no_apic_message: db \
"                      Sorry, your CPU doesn't have an APIC!                     ", 0x00
rsdp_not_found_message: db \
"                        Sorry, we couldn't find the RSDP!                       ", 0x00
bad_acpi_checksum_message: db \
"                 Sorry, an ACPI table had an invalid checksum!                  ", 0x00
xsdt_not_supported_message: db \
"                       Sorry, your computer uses an XSDT!                       ", 0x00
madt_not_found_message: db \
"                        Sorry, we couldn't find the MADT!                       ", 0x00

times 0x3000-($-kernel_entry) db 0

