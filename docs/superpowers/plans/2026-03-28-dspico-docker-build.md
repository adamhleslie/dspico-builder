# DSPico Docker Build System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Docker-based compilation system that produces all DSPico artifacts from source with a single `make all` command.

**Architecture:** Single multi-stage Dockerfile with stages for each component (BlocksDS base, DLDI, bootloader, encryptor, firmware, loader, launcher). A Makefile orchestrates `docker buildx` calls to build individual or all stages, extracting artifacts to `output/`. Docker Compose provides the default full-build configuration.

**Tech Stack:** Docker (multi-stage builds, buildx), Docker Compose, GNU Make, BlocksDS/Wonderful toolchain, Pico SDK, .NET 9.0, gcc-arm-none-eabi

---

## File Structure

| File | Responsibility |
|------|---------------|
| `Dockerfile` | Multi-stage build defining all compilation stages |
| `docker-compose.yml` | Default full-build service with build args |
| `Makefile` | User-facing build targets, orchestrates docker buildx |
| `.gitignore` | Ignores output/, blowfish keys, BIOS dumps |
| `docs/build-stages.md` | Already exists — stage reference table |

---

### Task 1: Create .gitignore

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Write .gitignore**

```gitignore
# Build output
output/

# Blowfish key files (user-supplied, not redistributable)
ntrBlowfish.bin
biosnds7.rom
twlBlowfish.bin
biosdsi7.rom
twlDevBlowfish.bin

# WRFU Tester ROM (user-supplied)
wrfu_tester_v060.nds

# OS
.DS_Store
Thumbs.db
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "feat: add .gitignore for build artifacts and key files"
```

---

### Task 2: Write the `blocksds` base stage in Dockerfile

This is the foundation stage that all NDS ARM builds depend on. It installs the Wonderful toolchain and BlocksDS.

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Create Dockerfile with blocksds stage**

```dockerfile
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
```

- [ ] **Step 2: Verify the stage builds**

```bash
docker buildx build --target blocksds -t dspico-blocksds .
```

Expected: image builds successfully, final layer has `/opt/wonderful/bin/wf-pacman` and `$DLDITOOL` path exists.

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "feat: add blocksds base stage to Dockerfile"
```

---

### Task 3: Add `dldi` and `bootloader` stages

These two stages build sequentially: dldi produces `DSpico.dldi`, bootloader uses it to DLDI-patch `BOOTLOADER.nds`.

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append dldi stage to Dockerfile**

Add after the `blocksds` stage:

```dockerfile
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
```

- [ ] **Step 2: Append bootloader stage to Dockerfile**

Add after the `dldi` stage:

```dockerfile
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
```

- [ ] **Step 3: Verify both stages build**

```bash
docker buildx build --target bootloader -t dspico-bootloader .
```

Expected: builds successfully, produces `BOOTLOADER.nds`.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add dldi and bootloader stages to Dockerfile"
```

---

### Task 4: Add `encryptor` and `encrypt` stages

These use .NET to build DSRomEncryptor, then encrypt the bootloader with user-supplied blowfish keys.

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append encryptor stage to Dockerfile**

Add after the `bootloader` stage:

```dockerfile
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
```

- [ ] **Step 2: Append encrypt stage to Dockerfile**

Add after the `encryptor` stage. This uses the `BLOWFISH_DIR` build arg:

```dockerfile
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
```

Note: The `[n]`, `[m]` glob trick in COPY makes each file optional — if the file doesn't exist, Docker won't fail. At least one NTR blowfish file (either `ntrBlowfish.bin` or `biosnds7.rom`) must be present or DSRomEncryptor will error at runtime.

- [ ] **Step 3: Test the encrypt stage builds (requires blowfish keys)**

Place at least `ntrBlowfish.bin` or `biosnds7.rom` in the project root, then:

```bash
docker buildx build --target encrypt -t dspico-encrypt .
```

Expected: builds successfully, produces `default.nds`.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add encryptor and encrypt stages to Dockerfile"
```

---

### Task 5: Add `firmware` stage

This is the main RP2040 firmware build. It uses pico-sdk (not BlocksDS) and takes `default.nds` from the encrypt stage.

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append firmware stage to Dockerfile**

Add after the `encrypt` stage:

```dockerfile
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

# Conditional: Wrfuxxed exploit support
COPY --from=wrfuxxe[d] /build/uartBufv060.bin /build/data/uartBufv060.bin*
ARG WRFU_TESTER_ROM=wrfu_tester_v060.nds
# The glob trick: wrfu_tester_v060.nd[s] won't fail if file is absent
COPY ${WRFU_TESTER_ROM%.nds}.nd[s] /build/roms/dsimode.nds*

RUN if [ "$ENABLE_WRFUXXED" = "true" ]; then \
      sed -i 's/#DSPICO_ENABLE_WRFUXXED/DSPICO_ENABLE_WRFUXXED/' CMakeLists.txt; \
    fi

RUN chmod +x compile.sh && ./compile.sh

# Artifact: /build/build/DSpico.uf2
```

**Important implementation note:** The conditional COPY from the `wrfuxxed` stage is tricky in Docker. The glob-bracket trick (`wrfuxxe[d]`) makes the `COPY --from` not fail when the stage doesn't exist. However, this approach has limitations — if it doesn't work cleanly during testing, the fallback is to always build the `wrfuxxed` stage but only use its output conditionally in the `RUN` step. Test this carefully in Step 2.

- [ ] **Step 2: Test firmware stage builds (default path, no Wrfuxxed)**

```bash
docker buildx build --target firmware -t dspico-firmware .
```

Expected: builds successfully, produces `DSpico.uf2` in `/build/build/`.

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "feat: add firmware stage with conditional Wrfuxxed support"
```

---

### Task 6: Add `wrfuxxed`, `loader`, `launcher`, and `output` stages

The remaining stages. `wrfuxxed` is conditionally used by firmware. `loader` and `launcher` produce SD card files. `output` collects everything.

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Insert wrfuxxed stage before the firmware stage**

This stage must appear before `firmware` in the Dockerfile since firmware references it. Insert it between the `encrypt` and `firmware` stages:

```dockerfile
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
```

- [ ] **Step 2: Append loader stage to Dockerfile**

Add after the `firmware` stage:

```dockerfile
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
```

- [ ] **Step 3: Append launcher stage to Dockerfile**

Add after the `loader` stage:

```dockerfile
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
```

- [ ] **Step 4: Append output stage to Dockerfile**

Add as the final stage:

```dockerfile
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
```

- [ ] **Step 5: Test the full output stage builds**

```bash
docker buildx build --target output -t dspico-output .
```

Expected: builds all stages, collects artifacts in `/out/`.

- [ ] **Step 6: Commit**

```bash
git add Dockerfile
git commit -m "feat: add wrfuxxed, loader, launcher, and output stages"
```

---

### Task 7: Create docker-compose.yml

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Write docker-compose.yml**

```yaml
services:
  build:
    build:
      context: .
      dockerfile: Dockerfile
      target: output
      args:
        BLOWFISH_DIR: ${BLOWFISH_DIR:-.}
        ENABLE_WRFUXXED: ${ENABLE_WRFUXXED:-false}
        WRFU_TESTER_ROM: ${WRFU_TESTER_ROM:-wrfu_tester_v060.nds}
    image: dspico-build
```

- [ ] **Step 2: Verify docker compose config parses**

```bash
docker compose config
```

Expected: prints resolved config without errors.

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add docker-compose.yml for full build"
```

---

### Task 8: Create Makefile

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Write Makefile**

```makefile
.PHONY: all firmware dldi bootloader loader launcher sdcard clean

# Build args (override via environment or command line)
BLOWFISH_DIR ?= .
ENABLE_WRFUXXED ?= false
WRFU_TESTER_ROM ?= wrfu_tester_v060.nds

BUILD_ARGS = \
	--build-arg BLOWFISH_DIR=$(BLOWFISH_DIR) \
	--build-arg ENABLE_WRFUXXED=$(ENABLE_WRFUXXED) \
	--build-arg WRFU_TESTER_ROM=$(WRFU_TESTER_ROM)

BUILDX = docker buildx build $(BUILD_ARGS)

# --- Top-level targets ---

all: output/DSpico.uf2 output/LAUNCHER.nds output/picoLoader7.bin

sdcard: all
	@mkdir -p output/sdcard/_pico
	cp output/LAUNCHER.nds output/sdcard/_picoboot.nds
	cp output/picoLoader7.bin output/sdcard/_pico/picoLoader7.bin
	cp output/picoLoader9_DSPICO.bin output/sdcard/_pico/picoLoader9.bin
	cp output/aplist.bin output/sdcard/_pico/aplist.bin
	cp output/savelist.bin output/sdcard/_pico/savelist.bin
	cp -r output/_pico/themes output/sdcard/_pico/themes
	@echo "SD card layout ready at output/sdcard/"

clean:
	rm -rf output/

# --- Individual stage targets ---

output/DSpico.uf2: output/.firmware
output/.firmware:
	$(BUILDX) --target firmware --output type=local,dest=output/firmware .
	mv output/firmware/build/DSpico.uf2 output/DSpico.uf2
	rm -rf output/firmware
	@touch $@

output/LAUNCHER.nds output/_pico: output/.launcher
output/.launcher:
	$(BUILDX) --target launcher --output type=local,dest=output/launcher .
	mv output/launcher/LAUNCHER.nds output/LAUNCHER.nds
	cp -r output/launcher/_pico output/_pico
	rm -rf output/launcher
	@touch $@

output/picoLoader7.bin output/picoLoader9_DSPICO.bin output/aplist.bin output/savelist.bin: output/.loader
output/.loader:
	$(BUILDX) --target loader --output type=local,dest=output/loader .
	mv output/loader/picoLoader7.bin output/picoLoader7.bin
	mv output/loader/picoLoader9_DSPICO.bin output/picoLoader9_DSPICO.bin
	mv output/loader/data/aplist.bin output/aplist.bin
	mv output/loader/data/savelist.bin output/savelist.bin
	rm -rf output/loader
	@touch $@

# Convenience aliases
firmware: output/DSpico.uf2
launcher: output/LAUNCHER.nds
loader: output/picoLoader7.bin

dldi:
	$(BUILDX) --target dldi --output type=local,dest=output/dldi .
	mv output/dldi/DSpico.dldi output/DSpico.dldi
	rm -rf output/dldi

bootloader:
	$(BUILDX) --target encrypt --output type=local,dest=output/encrypt .
	mv output/encrypt/default.nds output/default.nds
	rm -rf output/encrypt
```

- [ ] **Step 2: Verify Makefile syntax**

```bash
make -n all
```

Expected: prints the commands that would be run without executing them (dry run). Should show `docker buildx build` commands.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add Makefile with per-stage and sdcard targets"
```

---

### Task 9: End-to-end test (default build, no Wrfuxxed)

This task validates the full pipeline works. Requires blowfish keys in the project root.

**Files:**
- No file changes — this is a validation task.

- [ ] **Step 1: Verify blowfish keys are present**

```bash
ls -la ntrBlowfish.bin biosnds7.rom twlBlowfish.bin biosdsi7.rom 2>/dev/null
```

Expected: at least one NTR file exists (`ntrBlowfish.bin` or `biosnds7.rom`).

- [ ] **Step 2: Run full build**

```bash
make all
```

Expected: Docker builds all stages, `output/` contains:
- `DSpico.uf2`
- `LAUNCHER.nds`
- `picoLoader7.bin`
- `picoLoader9_DSPICO.bin`
- `aplist.bin`
- `savelist.bin`
- `_pico/themes/` directory

- [ ] **Step 3: Run sdcard assembly**

```bash
make sdcard
```

Expected: `output/sdcard/` contains the correct directory structure:
```
output/sdcard/
├── _pico/
│   ├── themes/
│   ├── aplist.bin
│   ├── savelist.bin
│   ├── picoLoader7.bin
│   └── picoLoader9.bin
└── _picoboot.nds
```

- [ ] **Step 4: Test individual target rebuild**

```bash
make clean
make firmware
```

Expected: only the firmware stage chain builds (blocksds → dldi → bootloader → encryptor → encrypt → firmware). `output/DSpico.uf2` exists. Other artifacts do not.

- [ ] **Step 5: Test clean**

```bash
make clean
ls output/ 2>/dev/null
```

Expected: `output/` directory does not exist.

---

### Task 10: Test Wrfuxxed toggle

**Files:**
- No file changes — this is a validation task.

- [ ] **Step 1: Run build with Wrfuxxed enabled**

Place the WRFU Tester v0.60 ROM as `wrfu_tester_v060.nds` in the project root, then:

```bash
make firmware ENABLE_WRFUXXED=true
```

Expected: the wrfuxxed stage builds, firmware CMakeLists.txt gets `DSPICO_ENABLE_WRFUXXED` uncommented, `DSpico.uf2` is produced.

- [ ] **Step 2: Verify without the ROM present, build still works with default (no Wrfuxxed)**

```bash
make clean
make firmware
```

Expected: builds successfully without Wrfuxxed stage.
