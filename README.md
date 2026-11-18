# Radxa Orion O6 custom Android BIOS

An Android BIOS (UEFI firmware) for the **Radxa Orion O6** and **Orion O6N**, built in Docker from Radxa's
official sources, [radxa-pkg/edk2-cix](https://github.com/radxa-pkg/edk2-cix) **1.3.2**, plus five small
patches. The BIOS calls itself **`Android-1.3.2-dmod`** on the setup page, on the boot console and in SMBIOS.

**Tested on a Radxa Orion O6 with Android 16. The O6N build uses the same patches but hasn't been tested on
hardware**. The O6 and O6N need different images: never flash one board's BIOS on the other.

## Build

You need Docker (Docker Desktop on Windows or macOS), internet access and about 4 GB of free disk space.
The first build takes about 10 minutes, most of it downloading the sources. Later builds reuse them and take
2–3 minutes.

Windows (PowerShell), from the repository folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 -O6
```

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 -O6N
```

Linux or macOS:

```bash
./build.sh --o6
```

```bash
./build.sh --o6n
```

The BIOS ends up in **`output/O6-BIOS-1.3.2-android-dmod/`** (O6) or
**`output/O6N-BIOS-1.3.2-android-dmod/`** (O6N). Give both board switches to build both, one after the other.
Without a board switch the O6 is built.

| Option (`build.ps1` / `build.sh`) | Effect |
|---|---|
| `-O6` / `--o6` | Build for the Orion O6 |
| `-O6N` / `--o6n` | Build for the Orion O6N |
| `-Stock` / `--stock` | Same Android build **without** the patches → `output/<board>-BIOS-1.3.2-android/` |
| `-DebugBuild` / `--debug` | DEBUG firmware with a verbose serial log (folder name ends in `-debug`) |
| `-Ref <tag>` / `--ref <tag>` | Another edk2-cix release tag (default `1.3.2`; the patches are made for 1.3.2) |
| `-OutputDir <dir>` / `--output <dir>` | Another output folder (default `output` in the repository) |

## Output

`output/<board>-BIOS-1.3.2-android-dmod/` contains only build output, the same file set as Radxa's own
edk2-cix release package:

| File | What it is |
|---|---|
| `cix_flash_all.bin` | The complete 8 MB SPI flash image: **this is what you flash** |
| `cix_flash_ota.bin` | Partial image for OTA/capsule updates |
| `startup.nsh`, `FlashUpdate.efi`, `BurnImage.efi` | Flash the image from a USB stick through the UEFI Shell |
| `Shell.efi`, `VariableInfo.efi`, `EnrollFromDefaultKeysApp.efi` | UEFI tools from the same build |
| `BuildOptions` | The EDK2 build defines of this image |

Next to it, `output/<board>-BIOS-1.3.2-android-dmod-build-info/` records how it was built: edk2-cix and
submodule commits, patch checksums, toolchain, full source diff, module list and `SHA256SUMS`. You don't need it
to flash.

## The patches

All five patches change `edk2-platforms` and are applied in order. Besides them, the build makes the one change
that turns Radxa's build into an Android BIOS: `-D FASTBOOT_LOAD=nvme -D SYSTEM_LOADER=android` in
`src/Makefile`, the same flags CIX's own Android build uses.

1. **`0001-dmod-name-Android-version-dmod`**: names the BIOS `Android-<version>-dmod`, so you can see which
   BIOS is installed.
2. **`0002-dmod-ddr-low-power-off-by-default`**: adds the setup option **DDR Low Power** (Device Manager →
   Platform Configuration), default **Disabled**: the BIOS turns the firmware's DDR low-power mode off at every
   boot. With it on, sustained CPU/GPU load could make the power-management firmware stop responding, which
   froze, reset or powered off the board. **Enabled** keeps the firmware default.
3. **`0003-dmod-wipe-android-data-at-next-boot`**: adds the one-shot setup option **Wipe Android data at
   next boot**. On the next boot the BIOS erases Android's `metadata` partition and the start of `userdata` on
   the NVMe drive, like `fastboot erase`. Android then sets up `/data` again as on first boot. All Android apps
   and data are lost. The option switches itself back off. Needs 0002.
4. **`0004-fix-setup-variable-from-other-bios`**: the BIOS keeps its settings (PCIe, USB, memory, power,
   CPU) in a UEFI variable that survives BIOS flashes. 1.3.2 changed that variable's layout, but stock 1.3.2
   accepts an old one, for example from Radxa's Android 1.0.0 BIOS, and then reads every later setting one
   byte off. In testing, Android then didn't boot. With this patch, a settings variable of the wrong size is
   replaced by this BIOS's defaults.
5. **`0005-uefi-shell-fastboot-command`**: adds the UEFI Shell command **`fastboot`**, which starts the
   BIOS's fastboot mode so you can flash Android from a PC (no USB stick needed). On the **O6** it also makes
   the USB-C data port a USB **device** by default, as in Radxa's Android 1.0.0 BIOS; in 1.3.2's default host
   role the PC never sees the board in fastboot. In UEFI that USB-C port therefore no longer works as a host:
   use a USB-A port for USB sticks. On the **O6N** the port role is left as Radxa set it (host), because there
   is no reference for which O6N port fastboot uses: switch the data role in setup if the PC doesn't see the
   board.

Patches 0001–0004 and the `fastboot` command change files shared by both boards, so the O6N build gets them
too.

## Flashing

> Flashing a BIOS can brick the board if it goes wrong. Keep the power stable during the flash, and have a
> way to recover: the O6's BIOS chip is socketed and can be rewritten with a 1.8 V SPI programmer, see
> [Radxa's BIOS documentation](https://docs.radxa.com/en/orion/o6/low-level-dev/bios).

1. Copy the **contents** of your board's folder (`output/O6-BIOS-1.3.2-android-dmod/` or
   `output/O6N-BIOS-1.3.2-android-dmod/`) to the root of a FAT32 USB stick.
2. Plug the stick into a USB-A port, power on, press **Escape**, then **Boot Manager → UEFI Shell**. The
   Shell runs `startup.nsh` from the stick (or run `fs0:\startup.nsh`). Follow the prompts; the board powers
   off at the end.
3. Remove **all** power for a few seconds, then power on.

If you are coming from a different BIOS version (for example Radxa's Android 1.0.0), wipe Android's data
afterwards: `fastboot erase userdata` and `fastboot erase metadata`, or the **Wipe Android data at next boot**
option.

**Fastboot:** in the UEFI Shell type `fastboot`, connect the board's USB-C data port to the PC, and on the PC
run `fastboot devices`.

## Optional UEFI Shell scripts

`uefi-shell/` has two helper scripts; copy them to the USB stick if you want them:

- `wipe-android-data.nsh`: asks for confirmation, sets **Wipe Android data at next boot** (patch 0003) and
  resets.
- `reboot-to-fastboot.nsh`: reboots into fastboot through the reboot-reason register, the same way
  `adb reboot bootloader` does. It's a fallback for when the `fastboot` command isn't available.

## How it works

- `build.ps1` / `build.sh` build the Docker image from `Dockerfile` and run it. The container clones
  edk2-cix at the requested tag (with all submodules) into the Docker volume `radxa-o6-bios-src`, which is
  reused by later builds. It then sets the Android flags, applies `patches/`, builds, checks that the Android
  modules and the patch features are in the image, and writes the result to `output/`.
- `container-build.sh` is the script that runs inside the container.
- `tools/fvlist.py` lists the UEFI modules in an image; the build uses it for its checks.
- To start completely fresh: `docker volume rm radxa-o6-bios-src`.

Builds aren't bit-for-bit reproducible because the build date is embedded, so checksums differ between runs.

## Credits

Based on Radxa's [edk2-cix](https://github.com/radxa-pkg/edk2-cix) and CIX's UEFI code for the Sky1 SoC. The
patches modify that code, which is licensed under BSD-2-Clause-Patent. No warranty: use at your own risk.
