ASM=nasm
ASM_FLAGS= -fbin

all:
	$(ASM) $(ASM_FLAGS) bootloader.asm -o bootloader.o
	$(ASM) $(ASM_FLAGS) kernel.asm -o kernel.o
	cat bootloader.o > lassen-peak.img
	cat kernel.o >> lassen-peak.img

clean:
	rm *.o

