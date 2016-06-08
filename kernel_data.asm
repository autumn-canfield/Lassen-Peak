;;; Note: Don't move the gdt or idt, their addresses are hard coded in their
;;; respective pointers in loader.asm.
;;; The gdt and idt from 0xffffff7fbf7fe000 to 0xffffff7fbf800000 are not really
;;; mapped to the virtual address space. We only care about their physical
;;; addresses, so why waste the kernel's address space.
kernel_data: ;0x0000000000009000
%define kernel_org 0xffffff7fbf7fe000

idt_data: ;0x000000000000a000
times 0x0e dd \
   0x00080000 | (kernel_org + interrupt_routine - $$) & 0xffff, \
   0x0e00 | (kernel_org + interrupt_routine - $$) & 0xffff0000, \
   (kernel_org + interrupt_routine - $$)>>0x20, \
   0x00000000

dd \
   0x00080000 | (kernel_org + page_fault_isr - $$) & 0xffff, \
   0x8e00 | (kernel_org + page_fault_isr - $$) & 0xffff0000, \
   (kernel_org + page_fault_isr - $$)>>0x20, \
   0x00000000

times 0xf1 dd \
   0x00080000 | (kernel_org + interrupt_routine - $$) & 0xffff, \
   0x0e00 | (kernel_org + interrupt_routine - $$) & 0xffff0000, \
   (kernel_org + interrupt_routine - $$)>>0x20, \
   0x00000000

gdt_data:
dq 0x0000000000000000 ;Null entry
dq 0x0020980000000000 ;code
dq 0x0000900000000000 ;data
dq 0x0020f80000000000 ;user code

times 0x2000-($-kernel_data) db 0 ; Pad to two pages.

