# Assembled with nasm 2.11.02. Newer versions should work as well
boot-man.bin: boot-man.asm
	nasm -fbin $< -o $@

run: boot-man.bin
	qemu-system-i386 -full-screen $<

show: boot-man.bin
	ndisasm $<