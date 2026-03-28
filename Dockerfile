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
