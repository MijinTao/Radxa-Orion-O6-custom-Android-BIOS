# Build environment for the Radxa Orion O6 Android BIOS: Radxa's edk2-cix sources + the patches in ./patches.
# Same toolchain as Radxa's own builds: Debian bookworm + the distro AArch64 cross compiler (GCC 12)
# (see Build-Depends in radxa-pkg/edk2-cix debian/control).
FROM debian:bookworm

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates git curl zip \
      build-essential python3 python-is-python3 \
      uuid-dev nasm acpica-tools bison flex dpkg-dev \
 && if [ "$(dpkg --print-architecture)" != "arm64" ]; then \
      apt-get install -y --no-install-recommends crossbuild-essential-arm64; \
    fi \
 && rm -rf /var/lib/apt/lists/*

COPY container-build.sh /usr/local/bin/build-bios
COPY tools/fvlist.py /opt/bios-tools/fvlist.py
# Patches keep their exact bytes (several patched edk2 files use CRLF line endings)
COPY patches/ /opt/bios-patches/
# Strip Windows line endings from the scripts, in case they were edited on Windows.
RUN sed -i 's/\r$//' /usr/local/bin/build-bios /opt/bios-tools/fvlist.py \
 && chmod +x /usr/local/bin/build-bios

VOLUME ["/work", "/out"]
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/build-bios"]
