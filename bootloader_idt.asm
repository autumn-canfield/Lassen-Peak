times 0x0e dd \
   0x00080000 | (0x7c00 + interrupt_routine - $$) & 0xffff, \
   0x0e00 | (0x7c00 + interrupt_routine - $$) & 0xffff0000, \
   (0x7c00 + interrupt_routine - $$)>>0x20, \
   0x00000000

dd \
   0x00080000 | (0x7c00 + page_fault_isr - $$) & 0xffff, \
   0x8e00 | (0x7c00 + page_fault_isr - $$) & 0xffff0000, \
   (0x7c00 + page_fault_isr - $$)>>0x20, \
   0x00000000

times 0xf1 dd \
   0x00080000 | (0x7c00 + interrupt_routine - $$) & 0xffff, \
   0x0e00 | (0x7c00 + interrupt_routine - $$) & 0xffff0000, \
   (0x7c00 + interrupt_routine - $$)>>0x20, \
   0x00000000

