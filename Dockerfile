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
