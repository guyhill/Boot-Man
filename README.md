# Boot-Man
A bootable Pac-Man clone that fits inside the Master Boot Record

This tiny version of Pac-Man (only 510 bytes of code) fits inside the Master Boot Record of a USB stick.
To run it you need a version of [NASM](https://www.nasm.us/) (I used 2.11, newer versions should also work) and either a system emulator
(the make file contains a rule to run Boot-Man with the [Qemu](https://www.qemu.org/download/) emulator) or a low level tool such as [HDD Raw copy tool](https://hddguru.com/software/HDD-Raw-Copy-Tool/) to store the binary
in the first sector of a USB stick. Be warned however: since Boot-Man uses every available byte on the boot
sector, no space is available for a partition table. Therefore the USB stick cannot be used for anything else,
and all data on the USB stick is lost when storing Boot-Man on it. I did not yet test thoroughly if Boot-Man
actually boots on all PCs. If it does not on your machine, please let me know and I can see what can be done 
about it.

Happy booting!

Edit: I have since tried Boot-Man on a number of other machines, and results have been mixed:
1. My brand-new laptop can only boot in UEFI mode, not in Legacy BIOS mode. So this laptop cannot boot Boot-Man from USB stick.
2. My primary desktop PC can boot in both UEFI and Legacy modes, and will boot Boot-Man when I specify the boot device as "Legacy / USB Key". If I specify the boot device as some other USB device (USB hard disk, USB FDD, USB CDROM) it does not work.
3. My old multi-media laptop can do legacy BIOS boot, but does not have an option to boot from USB Key. I tried booting from USB Disk, USB FDD and USB CDROM but neither of them works.

Legacy BIOS is on its way out (finally, after almost 40 years!) and UEFI is the future. So it seems that the days of Boot-Man are, sadly, numbered.
