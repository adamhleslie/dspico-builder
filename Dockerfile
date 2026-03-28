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
