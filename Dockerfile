# syntax=docker/dockerfile:1

# ==============================================================================
# Stage: blocksds
# Base image for all NDS ARM builds. Installs Wonderful toolchain + BlocksDS.
# ==============================================================================
FROM debian:bookworm-slim AS blocksds

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Wonderful toolchain
RUN mkdir -p /opt/wonderful && \
    wget -qO /tmp/wf-bootstrap.tar.gz https://wonderful.asie.pl/bootstrap/wf-bootstrap-x86_64.tar.gz && \
    tar xzf /tmp/wf-bootstrap.tar.gz -C /opt/wonderful && \
    rm /tmp/wf-bootstrap.tar.gz

ENV PATH="/opt/wonderful/bin:${PATH}"

# Install BlocksDS
RUN wf-pacman --noconfirm -Syu wf-tools && \
    wf-config repo enable blocksds && \
    wf-pacman --noconfirm -Syu && \
    wf-pacman --noconfirm -S blocksds-toolchain

ENV BLOCKSDS=/opt/wonderful/thirdparty/blocksds/core
ENV BLOCKSDSEXT=/opt/wonderful/thirdparty/blocksds/external
ENV DLDITOOL=/opt/wonderful/thirdparty/blocksds/core/tools/dlditool/dlditool

# ==============================================================================
# Stage: dldi
# Compiles the DSpico DLDI driver.
# Source: https://github.com/LNH-team/dspico-dldi
# ==============================================================================
FROM blocksds AS dldi

WORKDIR /build
RUN git clone https://github.com/LNH-team/dspico-dldi.git . && \
    make

# Artifact: /build/DSpico.dldi

# ==============================================================================
# Stage: bootloader
# Compiles and DLDI-patches the DSpico bootloader.
# Source: https://github.com/LNH-team/dspico-bootloader
# ==============================================================================
FROM blocksds AS bootloader

WORKDIR /build
RUN git clone https://github.com/LNH-team/dspico-bootloader.git . && \
    git submodule update --init && \
    make

COPY --from=dldi /build/DSpico.dldi /build/DSpico.dldi
RUN $DLDITOOL DSpico.dldi BOOTLOADER.nds

# Artifact: /build/BOOTLOADER.nds (DLDI-patched)

# ==============================================================================
# Stage: encryptor
# Builds DSRomEncryptor (.NET 9.0).
# Source: https://github.com/Gericom/DSRomEncryptor
# ==============================================================================
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS encryptor

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone https://github.com/Gericom/DSRomEncryptor.git . && \
    dotnet build

# Artifact: /build/DSRomEncryptor/bin/Debug/net9.0/DSRomEncryptor

# ==============================================================================
# Stage: encrypt
# Encrypts the bootloader using DSRomEncryptor + user-supplied blowfish keys.
# Source: https://github.com/Gericom/DSRomEncryptor#blowfish-tables
# ==============================================================================
FROM encryptor AS encrypt

ARG BLOWFISH_DIR=.

# Copy blowfish key files into the DSRomEncryptor executable directory.
# Supports: ntrBlowfish.bin, biosnds7.rom, twlBlowfish.bin, biosdsi7.rom, twlDevBlowfish.bin
# DSRomEncryptor auto-detects whichever files are present.
COPY ${BLOWFISH_DIR}/ntrBlowfish.bi[n] ${BLOWFISH_DIR}/biosnds7.ro[m] \
     ${BLOWFISH_DIR}/twlBlowfish.bi[n] ${BLOWFISH_DIR}/biosdsi7.ro[m] \
     ${BLOWFISH_DIR}/twlDevBlowfish.bi[n] \
     /build/DSRomEncryptor/bin/Debug/net9.0/

COPY --from=bootloader /build/BOOTLOADER.nds /build/BOOTLOADER.nds

RUN cd /build/DSRomEncryptor/bin/Debug/net9.0 && \
    dotnet DSRomEncryptor.dll /build/BOOTLOADER.nds /build/default.nds

# Artifact: /build/default.nds

# ==============================================================================
# Stage: wrfuxxed (optional)
# Compiles and DLDI-patches the Wrfuxxed exploit for DSi/3DS.
# Source: https://github.com/LNH-team/dspico-wrfuxxed
# ==============================================================================
FROM blocksds AS wrfuxxed

WORKDIR /build
RUN git clone https://github.com/LNH-team/dspico-wrfuxxed.git . && \
    make

COPY --from=dldi /build/DSpico.dldi /build/DSpico.dldi
RUN $DLDITOOL DSpico.dldi uartBufv060.bin

# Artifact: /build/uartBufv060.bin (DLDI-patched)

# ==============================================================================
# Stage: firmware
# Compiles the DSpico RP2040 firmware. Produces DSpico.uf2.
# Source: https://github.com/LNH-team/dspico-firmware
# ==============================================================================
FROM debian:bookworm-slim AS firmware

ARG ENABLE_WRFUXXED=false

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    gcc-arm-none-eabi \
    git \
    libnewlib-arm-none-eabi \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone https://github.com/LNH-team/dspico-firmware.git . && \
    git submodule update --init && \
    cd pico-sdk && git submodule update --init && cd ..

# Copy encrypted bootloader
COPY --from=encrypt /build/default.nds /build/roms/default.nds

# Wrfuxxed exploit support: binary is always copied from the wrfuxxed stage.
# The WRFU Tester ROM (dsimode.nds) must be placed in roms/ by the user when
# ENABLE_WRFUXXED=true. The Makefile handles copying it into the build context.
COPY --from=wrfuxxed /build/uartBufv060.bin /build/data/uartBufv060.bin

RUN if [ "$ENABLE_WRFUXXED" = "true" ]; then \
      sed -i 's/#DSPICO_ENABLE_WRFUXXED/DSPICO_ENABLE_WRFUXXED/' CMakeLists.txt; \
    fi

RUN chmod +x compile.sh && ./compile.sh

# Artifact: /build/build/DSpico.uf2

# ==============================================================================
# Stage: loader
# Compiles Pico Loader.
# Source: https://github.com/LNH-team/pico-loader
# ==============================================================================
FROM blocksds AS loader

WORKDIR /build
RUN git clone https://github.com/LNH-team/pico-loader.git . && \
    git submodule update --init && \
    make

# Artifacts: /build/picoLoader7.bin, /build/picoLoader9_DSPICO.bin,
#            /build/data/aplist.bin, /build/data/savelist.bin

# ==============================================================================
# Stage: launcher
# Compiles Pico Launcher.
# Source: https://github.com/LNH-team/pico-launcher
# ==============================================================================
FROM blocksds AS launcher

WORKDIR /build
RUN git clone https://github.com/LNH-team/pico-launcher.git . && \
    git submodule update --init && \
    make

# Artifacts: /build/LAUNCHER.nds, /build/_pico/ (themes)

# ==============================================================================
# Stage: output
# Collects all build artifacts into /out for extraction.
# ==============================================================================
FROM debian:bookworm-slim AS output

RUN mkdir -p /out

COPY --from=firmware /build/build/DSpico.uf2 /out/DSpico.uf2
COPY --from=loader /build/picoLoader7.bin /out/picoLoader7.bin
COPY --from=loader /build/picoLoader9_DSPICO.bin /out/picoLoader9_DSPICO.bin
COPY --from=loader /build/data/aplist.bin /out/aplist.bin
COPY --from=loader /build/data/savelist.bin /out/savelist.bin
COPY --from=launcher /build/LAUNCHER.nds /out/LAUNCHER.nds
COPY --from=launcher /build/_pico/ /out/_pico/
