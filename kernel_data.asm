gdt_data:
dq 0x0000000000000000 ;Null entry
dq 0x0020980000000000 ;code
dq 0x0000900000000000 ;data
dq 0x0020f80000000000 ;user code

times 0x1000-($-gdt_data) db 0

