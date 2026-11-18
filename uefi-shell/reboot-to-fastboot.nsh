#!/usr/bin/env -S echo "This script is for UEFI Shell only:"
#
# Reboot into fastboot mode (Radxa Orion O6, Android 1.3.2 BIOS).
# Sets the reboot-reason register to 0x01 (the value "adb reboot bootloader" sets) and does a warm reset;
# the BIOS's LaunchFastbootDxe then starts fastboot early in the next boot. Fallback for when the
# built-in "fastboot" command can't be used. (A cold "reset" did not keep the register on 18 Nov 2026.)
#
@echo -off
echo "Setting reboot reason 0x01 (fastboot) and doing a warm reset..."
echo "The board restarts into fastboot. On the PC: fastboot devices"
mm 16000500 1 -w 4 -MMIO -n
reset -w
