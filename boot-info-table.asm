boot_info_table_addr equ 0x00000000
struc boot_info_table_struc
	pit_irq: resb 1
	keyboard_irq: resb 1
	ioapic_count: resb 1
	processor_count: resb 1
	tsc_frequency: resd 1 ;khz
	lapic_address: resq 1
	ioapic_address: resq 1
	ioapic_id: resd 1
	processor_list: resw 256 ;msb=processor-id lsb=apic-id
endstruc

