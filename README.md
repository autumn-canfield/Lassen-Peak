# Lassen-Peak
A hobby OS project.

## Status
Currently only a bootloader is implemented. The bootloader performs the
following tasks:

1. Configures vga 80x50 text mode.
2. Sets the vga colors.
3. Enables the A20 line. (Disables memory wrap-around past 1 Mib)
4. Reads the second stage and kernel from the drive.
5. Checks that Long Mode is supported.
6. Obtains a memory map from the BIOS.
7. Disables the legacy interrupt controller.
8. Sets up default page tables.
9. Switches to Long Mode.
10. Maps ACPI regions and extracts processor information. 
11. Enables Programmable Interrupt Timer.
12. Starts up additional processors/cores.

## Running
NASM (or a compatible) assembler is required to build Lassen-Peak.

```
make && bochs -q
```

Additionally you can use `dd` to put it on a USB drive. Like so: (Where sdX is the
USB drive.)

```
make && sudo dd if=lassen-peak.img of=/dev/sdX
```
