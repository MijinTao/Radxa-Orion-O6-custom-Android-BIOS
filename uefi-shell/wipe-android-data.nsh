#!/usr/bin/env -S echo "This script is for UEFI Shell only:"
#
# Wipe Android data at the next boot, then reset (dmod BIOS, patch 0003).
# Sets the one-shot option "Wipe Android data at next boot" (UEFI variable DmodWipeAndroid = 01).
# On the next boot, before anything starts, the BIOS erases the Android metadata partition and the
# start of userdata on the NVMe drive (like fastboot erase); Android then reformats /data with new
# encryption keys from this BIOS's OP-TEE. Use it after switching BIOS versions. All Android apps
# and data are lost. The BIOS switches the option back off by itself.
#
@echo -off
echo "Wipe Android data at next boot: ALL Android apps and data will be erased."
echo "Press q to cancel, any other key to continue."
pause
setvar DmodWipeAndroid -guid eedf122d-a912-43d5-aa11-142762dd96fa -bs -nv =01
echo "Option set (DmodWipeAndroid):"
setvar DmodWipeAndroid -guid eedf122d-a912-43d5-aa11-142762dd96fa
echo "Resetting..."
reset
