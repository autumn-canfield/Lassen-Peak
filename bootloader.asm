;;; Map of physical memory below 1 mib:
;;; 0x00000000       - 0x03ff Default interrupt vector table
;;; 0x00000400       - 0x04ff Bios data area
;;; 0x00000500       - (0x500 + 0x18*num_entries) Memory map
;;; 0x0000????       - 0x7bff Stack
;;; 0x00007c00       - 0x9fff Bootloader
;;; 0x0000a000       - 0xafff GDT & kernel data
;;; 0x0000b000       - 0xefff Kernel (3 pages)
;;; 0x0000e000       - 0x0000ffff Free (3 pages)
;;; 0x00010000       - 0x00010fff Default PML4
;;; 0x00011000       - 0x00011fff Default PDP
;;; 0x00012000       - 0x00012fff Default PD (2 mib identity mapped)
;;; 0x00013000       - 0x00013fff Free
;;; 0x00014000       - 0x00014fff Kernel PDP
;;; 0x00015000       - 0x00015fff Kernel PD
;;; 0x00016000       - 0x00016fff Kernel PT
;;; 0x00017000       - 0x00017fff IDT
;;; 0x00018000       - 0x0007ffff Guaranteed free (104 pages)
;;; 0x00080000       - 0x0009fbff Possibly free depending on EBDA
;;; 0x0009fc00 (typ) - 0x0009ffff Extended bios data area
;;; 0x000a0000       - 0x000bffff Video memory
;;; 0x000c0000       - 0x000fffff Rom area
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
;;; Output of print_mem_map in bochs (using "memory: guest=32"):
;;; address          length           type
;;; 0000000000000000 000000000009f000 0001
;;; 000000000009f000 0000000000001000 0002
;;; 00000000000e8000 0000000000018000 0002
;;; 0000000000100000 0000000001ef0000 0001
;;; 0000000001ff0000 0000000000010000 0003
;;; 00000000fffc0000 0000000000040000 0002
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

xor ax, ax ;;Zero segment registers
mov ss, ax
mov ds, ax
mov es, ax

mov sp, 0x7c00 ;Note: The stack doesn't overwrite the bootsector because it grows down.

and dl, 0xff ;;Push drive number to the stack.
push dx

;; Change vga settings
xor ah, ah
mov al, 0x03 ;0x30 = 80x25 text mode.
int 0x10

mov ax, 0x1003 ;Disable blinking so we can use all 16 colors as a background.
xor bl, bl
int 0x10

mov ah, 0x01 ;;Hide the cursor
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
;   mov [fs:bx], ax
;   add bx, 0x0002
;   add ax, 0x0101
;   cmp al, 0xff
;   jne .end
;   mov al, 0x00
;   .end:
;   cmp bx, 0x1000
;   jne color_loop
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
   call panic16

test_a20:
   mov word [0x7dfe], 0xabcd
   mov cx, [es:0x7e0e]
   cmp cx, 0xabcd
   ret

a20_enabled:
xor ax, ax
mov es, ax

;; Read from drive
;;
;;If we were using an actual floppy disk we would reset then try again in case
;;of failure. Because we have no plans to use a real floppy this is sufficient.
mov si, drive_read_error_message

;;Read the second stage of the bootloader.
pop dx ;Pop drive number from the stack
mov ax, 0x0211 ;0x2200 bytes (0x11 sectors)
mov cx, 0x0002 ;Cylinder, Sector (one indexed)
mov dh, 0x00   ;Head
mov bx, 0x7e00 ;Buffer address
int 0x13
jc panic16

;;Read the kernel to 0xa000
mov ax, 0x0220 ;16 kib (0x20 sectors)
mov cx, 0x000b ;Cylinder, Sector
mov dh, 0x00   ;Head
mov bx, 0xa000 ;Buffer address
int 0x13
jc panic16


;;Check if long mode is supported
mov si, no_long_mode_message

pushfd
mov ecx, [esp]
xor dword [esp],0x00200000
popfd
pushfd
pop eax
xor eax, ecx
jz panic16

mov eax, 0x80000000
cpuid
cmp eax, 0x80000001
jb panic16

mov eax, 0x80000001
cpuid
test edx, 1<<29
jz panic16


;;Get memory map and place it at 0x500
;;
;;Format:
;;0x0000000000000000 Base address
;;0x0000000000000000 Length of region
;;0x00000000         Type of region
;;0x00000000         Padding
;;
;;Values for Type field:
;;0x01 Available
;;0x02 Reserved
;;0x03 ACPI (reclaimable)
;;0x04 ACPI NVS
;;Treat all others as reserved.

mov di, 0x500
xor ebx, ebx
xor bp, bp ;bp holds the number of entries.
mov edx, 0x534d4150
mov ecx, 0x00000018
mov eax, 0x0000e820
int 0x15
mov si, mem_detect_error_message
jc panic16
inc bp

mem_detect_loop:
   add di, 0x18
   mov edx, 0x534d4150
   mov eax, 0x0000e820
   mov ecx, 0x00000018
   int 0x15
   pushfd
   inc bp
   or ebx, ebx
   jz mem_detect_done
   popfd
   jnc mem_detect_loop
   jc mem_detect_done

   mov si, mem_detect_error_message
   jmp panic16

mem_detect_done:
   xor di, di ;;Save number of entries padded to 64 bits.
   push di
   push di
   push di
   push bp

;; Uncomment this to print the memory map for debugging.
;print_mem_map:
;   mov si, 0x500
;   xor cx, cx
;
;   .loop:
;      mov bx, [si + 0x10]
;      cmp bx, 0x01 ;Filter out a particular type
;      jne .continue
;
;      mov bx, [si + 0x06]
;      call print_bx
;      mov bx, [si + 0x04]
;      call print_bx
;      mov bx, [si + 0x02]
;      call print_bx
;      mov bx, [si]
;      call print_bx
;
;      add di, 0x02
;      mov bx, [si + 0x0e]
;      call print_bx
;      mov bx, [si + 0x0c]
;      call print_bx
;      mov bx, [si + 0x0a]
;      call print_bx
;      mov bx, [si + 0x08]
;      call print_bx
;
;      add di, 0x02
;      mov bx, [si + 0x10]
;      call print_bx
;
;      add di, 0x54
;   .continue
;      add si, 0x18
;      add cx, 1
;      cmp cx, bp
;      jl .loop
;   cli
;   hlt

   
   jmp second_stage

; Print string in si to the top left corner using attributes in bl
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

panic16:
   mov bl, 0x4f
   call print
   cli
   .hlt:
   hlt
   jmp .hlt

vga_color_palette_data:
;;First color is already black so we don't need to set it.
;;One byte for red, green, then blue. Each are on a scale from 0x00 to 0x3f.
db 0x04, 0x14, 0x2e ; Sapphire
db 0x14, 0x1e, 0x10 ; Fern Green
db 0x3c, 0x21, 0x00 ; Tangerine
db 0x24, 0x00, 0x0a ; Burgandy
db 0x18, 0x14, 0x36 ; Majorelle Blue
db 0x30, 0x26, 0x1a ; Camel
db 0x2b, 0x2b, 0x2b ; Light Grey
db 0x0e, 0x0d, 0x0b ; Umber (modified)
db 0x11, 0x20, 0x2c ; Steel Blue
db 0x27, 0x2a, 0x08 ; Citron
db 0x30, 0x3d, 0x28 ; Pistachio
db 0x37, 0x17, 0x20 ; Blush
db 0x2d, 0x1f, 0x36 ; Lavender
db 0x3c, 0x30, 0x0c ; Saffron
db 0x3f, 0x3f, 0x3f ; White
;db 0x38, 0x1c, 0x1e ; Tango Pink
;db 0x37, 0x1b, 0x28 ; China Pink
;db 0x37, 0x0c, 0x18 ; Cerise
;db 0x39, 0x0b, 0x14 ; Amaranth
;db 0x20, 0x00, 0x00 ; Maroon
;db 0x16, 0x26, 0x23 ; Viridian
;db 0x0e, 0x0e, 0x0e ; Dark Grey
;db 0x16, 0x14, 0x12 ; Umber (original)

a20_error_message: db "Error enabling A20!", 0x00
no_long_mode_message: db "Computer isn't 64 bit!", 0x00
drive_read_error_message: db "Error reading instalation media!", 0x00
mem_detect_error_message: db "Error detecting memory!", 0x00

times 510-($-start) db 0 ;Pad first boot sector to 512 bytes.
dw 0xaa55 ;Boot signature.

second_stage:

;; Notify bios that we will be operating in long mode. (Ostensibly used for
;; bios optimizations.)
mov ax, 0xec00
mov bx, 0x0002
int 0x15

cli

;; Because the PICs can still generate spurious IRQs even when they are
;; disabled we stil have to remap the IRQs.
;; Master PIC spurious irq: 0xed
;; Slave PIC spurious irq: 0xee
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
mov ax, 0x1000      ;;Zero 0x10000 to 0x18000
mov es, ax
mov ecx, 0x00002000
xor edi, edi
xor eax, eax
cld
rep stosd
xor di, di          ;;Add first entry in PML4
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
mov di, 0x0ff0      ;;Add second to last entry in PML4 for the kernel
mov eax, 0x00014003
mov [es:di], eax
mov di, 0x4ff0      ;;Add second to last entry in PDP for the kernel
mov eax, 0x00015003
mov [es:di], eax
mov di, 0x5fe0      ;;Add fourth to last entry in PD
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
mov di, 0x0ff8      ;;Add last entry in PML4 for recursive paging
mov eax, 0x00010003
mov [es:di], eax

xor ax, ax
mov es, ax


lidt [dummy_idt]

mov eax, 0xa0       ;;Set PAE and PGE bits
mov cr4, eax
mov ebx, 0x00010000 ;;Load CR3 with address of PML4
mov cr3, ebx
mov ecx, 0xc0000080 ;;Enable long mode by setting LME and LMA in the EFER MSR
rdmsr
or eax, 0x00000100
wrmsr
mov ebx, cr0        ;;Set protected mode and paging bits
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

   mov edi, 0x17000
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

   %include "bootloader-64.asm" ;Does some setup then jumps to the kernel.

bits 16

ap_initalization:
lidt [dummy_idt]

mov eax, 0xa0       ;;Set PAE and PGE bits
mov cr4, eax
mov ebx, 0x00010000 ;;Load CR3 with address of PML4
mov cr3, ebx
mov ecx, 0xc0000080 ;;Enable long mode by setting LME and LMA in the EFER MSR
rdmsr
or eax, 0x00000100
wrmsr
mov ebx, cr0        ;;Set protected mode and paging bits
or ebx, 0x80000001
mov cr0, ebx
lgdt [gdt_pointer]


;; Print bx in hex at position in di. (Commented to save space when not debugging.)
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
dq 0x000000000000b000

times 0x2200-($-second_stage) db 0

