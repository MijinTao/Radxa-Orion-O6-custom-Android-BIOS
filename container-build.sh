#!/bin/bash
# Builds the Android BIOS (UEFI firmware) for the Radxa Orion O6 from Radxa's edk2-cix sources, applies the
# patches in /opt/bios-patches, verifies the result and writes it to /out. Runs inside the Docker image
# defined by ./Dockerfile; start it with ./build.sh or .\build.ps1 (see README.md).
#
# Environment variables:
#   EDK2_CIX_REF  git tag of radxa-pkg/edk2-cix to build                       (default: 1.3.2)
#   BOARD         O6 or O6N (the patches are tested on the O6 only)            (default: O6)
#   UEFI_TARGET   RELEASE or DEBUG                                             (default: RELEASE)
#   PATCHES       1 = apply the patches ("dmod" BIOS), 0 = stock Android build (default: 1)
#   JOBS          parallel jobs for the git submodule fetch                    (default: 8)
#   HOST_UID/HOST_GID  if set, the output is chown'ed to this user (Linux hosts)
#
# Volumes:
#   /work  persistent source checkout (about 2.7 GB, re-used between builds)
#   /out   output folder:
#            <BOARD>-BIOS-<ref>-android[-dmod][-debug]/             the BIOS (build output only)
#            <BOARD>-BIOS-<ref>-android[-dmod][-debug]-build-info/  how it was built

set -euo pipefail

EDK2_CIX_REF="${EDK2_CIX_REF:-1.3.2}"
BOARD="${BOARD:-O6}"
UEFI_TARGET="${UEFI_TARGET:-RELEASE}"
PATCHES="${PATCHES:-1}"
JOBS="${JOBS:-8}"
PATCH_DIR="${PATCH_DIR:-/opt/bios-patches}"

case "$BOARD" in
  O6|O6N) ;;
  *) echo "ERROR: BOARD must be O6 or O6N (got '$BOARD')" >&2; exit 1 ;;
esac
case "$UEFI_TARGET" in
  RELEASE|DEBUG) ;;
  *) echo "ERROR: UEFI_TARGET must be RELEASE or DEBUG (got '$UEFI_TARGET')" >&2; exit 1 ;;
esac
case "$PATCHES" in
  0) ;;
  1) if ! compgen -G "${PATCH_DIR}/*/*.patch" >/dev/null; then
       echo "ERROR: PATCHES=1 but no patches found in ${PATCH_DIR}/<submodule>/*.patch" >&2; exit 1
     fi ;;
  *) echo "ERROR: PATCHES must be 1 or 0 (got '$PATCHES')" >&2; exit 1 ;;
esac

SRC="/work/edk2-cix-${EDK2_CIX_REF}"
PKG_NAME="${BOARD}-BIOS-${EDK2_CIX_REF}-android"
if [[ "$PATCHES" == "1" ]]; then PKG_NAME="${PKG_NAME}-dmod"; fi
if [[ "$UEFI_TARGET" == "DEBUG" ]]; then PKG_NAME="${PKG_NAME}-debug"; fi
PKG="/out/${PKG_NAME}"
INFO="/out/${PKG_NAME}-build-info"
# Name patch 0001 gives the BIOS (setup page, boot console, SMBIOS)
DMOD_LABEL="Android-${EDK2_CIX_REF}-dmod"
# Which features the patches folder carries (the checks below follow them)
HAS_DDR=0; HAS_WIPE=0; HAS_FBCMD=0; HAS_ASPM=0
if [[ "$PATCHES" == "1" ]]; then
  if compgen -G "${PATCH_DIR}/*/*ddr-low-power*.patch" >/dev/null; then HAS_DDR=1; fi
  if compgen -G "${PATCH_DIR}/*/*wipe-android*.patch" >/dev/null; then HAS_WIPE=1; fi
  if compgen -G "${PATCH_DIR}/*/*fastboot-command*.patch" >/dev/null; then HAS_FBCMD=1; fi
  if compgen -G "${PATCH_DIR}/*/*pcie-aspm*.patch" >/dev/null; then HAS_ASPM=1; fi
fi

log() { echo -e "\n\033[1;36m==> $*\033[0m"; }

git config --global --add safe.directory '*'
git config --global advice.detachedHead false

# ---------------------------------------------------------------------------
log "1/6 Fetching radxa-pkg/edk2-cix @ ${EDK2_CIX_REF} (with all submodules)"
# ---------------------------------------------------------------------------
if [[ ! -d "$SRC/.git" ]]; then
  git clone --branch "$EDK2_CIX_REF" --recurse-submodules --jobs "$JOBS" \
    https://github.com/radxa-pkg/edk2-cix.git "$SRC"
else
  echo "Re-using existing checkout in $SRC"
fi
cd "$SRC"
# Undo any change from a previous run (Makefile, patched submodules incl. files a patch added)
# and make sure the submodules match the tag.
git checkout -- src/Makefile
git submodule update --init --recursive --jobs "$JOBS"
for sub in edk2-platforms $( [[ -d "$PATCH_DIR" ]] && find "$PATCH_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' ); do
  if [[ -d "src/$sub" ]]; then git -C "src/$sub" checkout -q -- . && git -C "src/$sub" clean -fdq; fi
done
echo "edk2-cix:       $(git describe --tags --always)  ($(git rev-parse --short HEAD))"
git submodule status | sed 's/^/  /'

# ---------------------------------------------------------------------------
log "2/6 Configuring: Android BIOS$( [[ "$PATCHES" == "1" ]] && echo ' + patches' )"
# ---------------------------------------------------------------------------
# Android variant = Radxa's official build with two extra defines, the same ones CIX's own Android build
# (build_and_package.sh androidO6) passes:
#   FASTBOOT_LOAD=nvme     fastboot over USB + NVMe boot (PCIe host, CDNSP USB device, firmware update)
#   SYSTEM_LOADER=android  LinuxLoader (Android boot loader), ABSelect (A/B slots), AndroidConfigDxe,
#                          Android memory map, capsule (OTA) support
sed -i 's/-D FASTBOOT_LOAD= /-D FASTBOOT_LOAD=nvme -D SYSTEM_LOADER=android /' src/Makefile
if ! grep -q -- '-D FASTBOOT_LOAD=nvme -D SYSTEM_LOADER=android ' src/Makefile; then
  echo "ERROR: could not apply the Android build flags to src/Makefile." >&2
  echo "       The upstream Makefile changed; edit the 'build -a AARCH64 ...' line by hand." >&2
  exit 1
fi
git --no-pager diff -- src/Makefile
if [[ "$PATCHES" == "1" ]]; then
  for d in "$PATCH_DIR"/*/; do
    sub="$(basename "$d")"
    [[ -d "src/$sub" ]] || { echo "ERROR: patches/$sub targets a submodule that does not exist (src/$sub)" >&2; exit 1; }
    for p in "$d"*.patch; do
      [[ -f "$p" ]] || continue
      echo "applying $sub/$(basename "$p")  (sha256 $(sha256sum "$p" | cut -c1-16))"
      if ! git -C "src/$sub" apply --whitespace=nowarn "$p"; then
        echo "ERROR: patch $sub/$(basename "$p") does not apply to edk2-cix ${EDK2_CIX_REF}." >&2; exit 1
      fi
    done
    git -C "src/$sub" status --short --untracked-files=all | sed 's/^/  /'
  done
fi

# ---------------------------------------------------------------------------
log "3/6 Building ${BOARD} (${UEFI_TARGET}) - this takes a while"
# ---------------------------------------------------------------------------
BUILD_DIR="src/Build/${BOARD}/${UEFI_TARGET}_GCC5"
# Always start from a clean board build dir, so nothing from an earlier build is reused.
rm -rf "src/Build/${BOARD}"
make -C src UEFI_TARGET="$UEFI_TARGET" \
  "Build/${BOARD}/${UEFI_TARGET}_GCC5/cix_flash_all.bin" \
  "Build/${BOARD}/${UEFI_TARGET}_GCC5/cix_flash_ota.bin"

# ---------------------------------------------------------------------------
log "4/6 Verifying the firmware image"
# ---------------------------------------------------------------------------
grep -o "gCommandLineDefines: {[^}]*}" "$BUILD_DIR/BuildOptions" || true
python3 -I /opt/bios-tools/fvlist.py "$BUILD_DIR/cix_flash_all.bin" > /tmp/modules.txt
echo "UEFI modules in image: $(grep -c ' ui=' /tmp/modules.txt)"
for m in LinuxLoader ABSelect AndroidConfigDxe Fastboot LaunchFastbootDxe; do
  if grep -q " ui=${m} " /tmp/modules.txt; then present=yes; else present=no; fi
  printf '  %-24s %s\n' "$m" "$present"
  if [[ "$present" == "no" ]]; then echo "ERROR: Android build is missing module $m" >&2; exit 1; fi
done
if [[ "$PATCHES" == "1" ]]; then
  # The patch features must be in the built modules: setup option texts (HII strings, UTF-16) in
  # PlatformConfigDxe, variable names in RadxaSetupVariableInitDxe, the fastboot command driver, and the
  # BIOS name (PcdFirmwareVersionString, UTF-16) somewhere.
  python3 -I - "$BUILD_DIR/AARCH64" "$DMOD_LABEL" "$HAS_DDR" "$HAS_WIPE" "$HAS_FBCMD" "$HAS_ASPM" <<'PY' || { echo "ERROR: the patch features are not in the built firmware" >&2; exit 1; }
import pathlib, sys
d, label, want_ddr, want_wipe, want_fbcmd = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3] == "1", sys.argv[4] == "1", sys.argv[5] == "1"
want_aspm = len(sys.argv) > 6 and sys.argv[6] == "1"
def has(path, text): return path.is_file() and text.encode("utf-16-le") in path.read_bytes()
ok = True
pc, rs = d / "PlatformConfigDxe.efi", d / "RadxaSetupVariableInitDxe.efi"
checks = []
if want_ddr:
    checks += [("DDR Low Power option", pc, "DDR Low Power"), ("DmodSetupVar in DXE", rs, "DmodSetupVar")]
if want_wipe:
    checks += [("Wipe Android option", pc, "Wipe Android data at next boot"), ("DmodWipeAndroid in DXE", rs, "DmodWipeAndroid")]
if want_fbcmd:
    checks += [("Shell command fastboot", d / "DmodFastbootCommandDxe.efi", "fastboot: starting fastboot")]
if want_aspm:
    checks += [("ASPM default migration", d / "PlatformSetupVariableInitDxe.efi", "DmodAspmDefault")]
for name, f, text in checks:
    r = has(f, text)
    print(f"  {name:24s} {'yes' if r else 'no'}"); ok &= r
hits = sorted(p.name for p in d.glob("*.efi") if has(p, label))
print(f"  {'name ' + label:24s} {', '.join(hits) if hits else 'not found as UTF-16 (warning only)'}")
sys.exit(0 if ok else 1)
PY
  echo "patch checks passed"
fi

# ---------------------------------------------------------------------------
log "5/6 Writing ${PKG_NAME}"
# ---------------------------------------------------------------------------
rm -rf "$PKG" "$INFO"
mkdir -p "$PKG" "$INFO"
# The BIOS folder: exactly the file set of Radxa's own edk2-cix release package (debian/edk2-cix.install),
# all from this build and its source checkout. cix_flash_all.bin is the 8 MB SPI image to flash;
# startup.nsh + FlashUpdate.efi flash it from a USB stick.
cp "$BUILD_DIR/cix_flash_all.bin" "$BUILD_DIR/cix_flash_ota.bin" "$BUILD_DIR/BuildOptions" "$PKG/"
for efi in Shell VariableInfo EnrollFromDefaultKeysApp; do
  if [[ -f "$BUILD_DIR/AARCH64/${efi}.efi" ]]; then cp "$BUILD_DIR/AARCH64/${efi}.efi" "$PKG/"; fi
done
cp src/edk2-non-osi/Platform/CIX/Sky1/FlashTool/* "$PKG/"   # FlashUpdate.efi, BurnImage.efi
cp src/scripts/startup.nsh "$PKG/"                           # runs FlashUpdate.efi from the EFI Shell

# The build-info folder: how this BIOS was built (not needed to flash it)
{
  echo "edk2-cix ${EDK2_CIX_REF} ($(git rev-parse HEAD))"
  git submodule status
  echo "BOARD=${BOARD} UEFI_TARGET=${UEFI_TARGET} PATCHES=${PATCHES}"
  if [[ "$PATCHES" == "1" ]]; then
    echo "BIOS name: ${DMOD_LABEL}"
    (cd "$PATCH_DIR" && sha256sum */*.patch | sed 's/^/patch: /')
  fi
  echo "Built $(date -u +%Y-%m-%dT%H:%M:%SZ) in $(. /etc/os-release && echo "$PRETTY_NAME"), $(aarch64-linux-gnu-gcc --version 2>/dev/null | head -1 || gcc --version | head -1)"
} > "$INFO/BUILD-INFO.txt"
# Full source change: src/Makefile, plus changed and added files inside patched submodules
{
  git --no-pager diff -- src/Makefile
  if [[ "$PATCHES" == "1" ]]; then
    for d in "$PATCH_DIR"/*/; do
      sub="$(basename "$d")"
      git -C "src/$sub" --no-pager diff --src-prefix="a/src/$sub/" --dst-prefix="b/src/$sub/"
      git -C "src/$sub" ls-files --others --exclude-standard | while read -r f; do
        git -C "src/$sub" --no-pager diff --no-index --src-prefix="a/src/$sub/" --dst-prefix="b/src/$sub/" /dev/null "$f" || true
      done
    done
  fi
} > "$INFO/source-changes.diff"
cp /tmp/modules.txt "$INFO/uefi-modules.txt"
(cd "$PKG" && sha256sum ./* > "$INFO/SHA256SUMS")

if [[ -n "${HOST_UID:-}" ]]; then chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" "$PKG" "$INFO"; fi

# ---------------------------------------------------------------------------
log "6/6 Done: ${PKG_NAME}"
# ---------------------------------------------------------------------------
ls -l "$PKG"
cat "$INFO/SHA256SUMS"
