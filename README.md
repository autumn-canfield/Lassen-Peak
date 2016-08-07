# Lassen-Peak
A hobby OS project.

## Status
So far I have only implemented the bootloader.

Here's what the bootloader does so far:

1. Configures vga 80x25 text mode.
2. Sets the vga colors.
3. Enables the A20 line.
4. Reads the second stage and kernel from the drive.
5. Checks that Long Mode is supported.
6. Obtains a memory map from the BIOS.
7. Disables the legacy interrupt controller.
8. Sets up default page tables.
9. Switches to Long Mode.

I am currently working on reading the ACPI tables, enabling the APICs, and
starting up the other cores in `bootloader-64.asm`.

## Running
```
make && bochs -q
```

Additionally you can use `dd` to put it on a USB drive. Like so: (Where sdX is the
USB drive.)

```
make && sudo dd if=lassen-peak.img of=/dev/sdX
```
