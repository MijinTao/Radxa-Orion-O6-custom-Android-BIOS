#!/bin/bash
# Builds the Radxa Orion O6 / O6N Android BIOS (Radxa edk2-cix + the patches in ./patches) in Docker
# and puts the result in ./output.
#
#   ./build.sh --o6            Orion O6  -> ./output/O6-BIOS-1.3.2-android-dmod/
#   ./build.sh --o6n           Orion O6N -> ./output/O6N-BIOS-1.3.2-android-dmod/
#   ./build.sh --o6 --o6n      both boards, one after the other
#   ./build.sh --o6 --stock    the same Android build without the patches -> ...-android/
#   ./build.sh --o6 --debug    DEBUG firmware (verbose serial log)
#
# Without --o6 / --o6n it builds the O6. Other options: --ref <edk2-cix tag> (default 1.3.2), --output <dir>
set -euo pipefail

REF="1.3.2"
BOARDS=()
UEFI_TARGET="RELEASE"
PATCHES="1"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$HERE/output"
IMAGE="${IMAGE:-radxa-o6-bios-builder}"
SOURCE_VOLUME="${SOURCE_VOLUME:-radxa-o6-bios-src}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --o6|--O6)   BOARDS+=("O6"); shift ;;
    --o6n|--O6N) BOARDS+=("O6N"); shift ;;
    --stock)     PATCHES="0"; shift ;;
    --debug)     UEFI_TARGET="DEBUG"; shift ;;
    --ref)       REF="$2"; shift 2 ;;
    --output)    OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)   sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done
if [[ ${#BOARDS[@]} -eq 0 ]]; then
  BOARDS=("O6")
  echo "No board given: building the Orion O6 (--o6n for the Orion O6N, --o6 --o6n for both)."
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

docker build -t "$IMAGE" "$HERE"
docker volume create "$SOURCE_VOLUME" >/dev/null
for BOARD in "${BOARDS[@]}"; do
  echo; echo "=== Building the $BOARD BIOS ==="
  docker run --rm \
    -v "$SOURCE_VOLUME:/work" \
    -v "$OUTPUT_DIR:/out" \
    -e EDK2_CIX_REF="$REF" -e BOARD="$BOARD" -e UEFI_TARGET="$UEFI_TARGET" -e PATCHES="$PATCHES" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    "$IMAGE"
done

echo "Done (${BOARDS[*]}). Output in $OUTPUT_DIR"
ls -l "$OUTPUT_DIR"
