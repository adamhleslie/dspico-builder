# DSPico Docker Build System Design

## Overview

A Docker Compose-based build system that compiles all DSPico components from source, orchestrated by a Makefile. Produces a ready-to-flash UF2 firmware file and a complete SD card directory structure.

## Goals

- Single `make all` command builds everything from scratch
- Individual `make <target>` commands for rebuilding specific components
- `make sdcard` assembles the final SD card layout
- Wrfuxxed exploit support toggleable via build arg (off by default — primary target is DS Lite)
- Blowfish keys supplied by the user, never committed to the repo

## Architecture

### Dockerfile (multi-stage)

A single `Dockerfile` with the following stages. Each stage is independently cacheable by Docker.

| Stage | Base | Toolchain | Produces | Source |
|-------|------|-----------|----------|--------|
| `blocksds` | debian:bookworm-slim | BlocksDS/wonderful + build-essential | Base for NDS ARM builds | [BlocksDS setup](https://blocksds.skylyrac.net/docs/setup/linux/) |
| `dldi` | blocksds | make | `DSpico.dldi` | [dspico-dldi](https://github.com/LNH-team/dspico-dldi) |
| `bootloader` | blocksds | make + dlditool | `BOOTLOADER.nds` (DLDI-patched) | [dspico-bootloader](https://github.com/LNH-team/dspico-bootloader) |
| `encryptor` | mcr.microsoft.com/dotnet/sdk:9.0 | dotnet build | DSRomEncryptor binary | [DSRomEncryptor](https://github.com/Gericom/DSRomEncryptor) |
| `encrypt` | encryptor | DSRomEncryptor + blowfish keys | `default.nds` | [DSRomEncryptor README](https://github.com/Gericom/DSRomEncryptor#blowfish-tables) |
| `firmware` | debian:bookworm-slim | pico-sdk + cmake + gcc-arm-none-eabi | `DSpico.uf2` | [dspico-firmware](https://github.com/LNH-team/dspico-firmware) |
| `loader` | blocksds | make + submodules | picoLoader bins + data files | [pico-loader](https://github.com/LNH-team/pico-loader) |
| `launcher` | blocksds | make + submodules | `LAUNCHER.nds` + `_pico/` assets | [pico-launcher](https://github.com/LNH-team/pico-launcher) |
| `wrfuxxed` | blocksds | make + dlditool | `uartBufv060.bin` (DLDI-patched) | [dspico-wrfuxxed](https://github.com/LNH-team/dspico-wrfuxxed) |
| `output` | debian:bookworm-slim | Copies all artifacts to `/out` | Everything | -- |

### Build Args

| Arg | Default | Description |
|-----|---------|-------------|
| `BLOWFISH_DIR` | `.` | Directory containing blowfish key files. Supports any combination of: `ntrBlowfish.bin` or `biosnds7.rom` (NTR/DS), `twlBlowfish.bin` or `biosdsi7.rom` (TWL/DSi retail), `twlDevBlowfish.bin` (TWL/DSi dev). All files in this directory are copied into the DSRomEncryptor executable directory; DSRomEncryptor handles detection automatically. |
| `ENABLE_WRFUXXED` | `false` | When `true`, compiles the Wrfuxxed exploit, patches it with DLDI, and enables `DSPICO_ENABLE_WRFUXXED` in the firmware CMakeLists.txt. |
| `WRFU_TESTER_ROM` | `wrfu_tester_v060.nds` | Path to the WRFU Tester v0.60 ROM file (SHA-1: `2d65fb7a0c62a4f08954b98c95f42b804fccfd26`). Only required when `ENABLE_WRFUXXED=true`. |

### docker-compose.yml

Defines a single `build` service:
- Builds from the `Dockerfile` targeting the `output` stage
- Passes build args (`BLOWFISH_DIR`, `ENABLE_WRFUXXED`)
- Bind-mounts `./output/` to receive artifacts

### Makefile Targets

| Target | Description |
|--------|-------------|
| `make all` | Full pipeline — builds everything, extracts all artifacts to `output/` |
| `make firmware` | Builds only the UF2 firmware |
| `make dldi` | Builds only the DLDI driver |
| `make bootloader` | Builds the bootloader through encryption |
| `make loader` | Builds Pico Loader |
| `make launcher` | Builds Pico Launcher |
| `make sdcard` | Assembles the complete SD card directory structure in `output/sdcard/` |
| `make clean` | Removes `output/` directory |

Individual targets use `docker buildx build --target <stage> --output type=local,dest=output/` to extract artifacts from specific stages without running the full pipeline.

### SD Card Assembly (`make sdcard`)

The `sdcard` target depends on `all` and assembles the final layout:

```
output/sdcard/
├── _pico/
│   ├── themes/          # copied from launcher build
│   │   ├── material/
│   │   │   └── theme.json
│   │   └── raspberry/
│   │       └── ...
│   ├── aplist.bin
│   ├── savelist.bin
│   ├── picoLoader7.bin
│   └── picoLoader9.bin  # renamed from picoLoader9_DSPICO.bin
└── _picoboot.nds        # renamed from LAUNCHER.nds
```

## Stage Details

### `blocksds` (base image)

Installs the Wonderful toolchain and BlocksDS packages:
1. Install system deps (`build-essential`, `wget`)
2. Install `wf-pacman` from the Wonderful toolchain
3. `wf-pacman -Syu wf-tools && wf-config repo enable blocksds && wf-pacman -Syu`
4. `wf-pacman -S blocksds-toolchain`
5. Set env vars: `BLOCKSDS`, `BLOCKSDSEXT`, `DLDITOOL`

### `dldi`

1. `git clone https://github.com/LNH-team/dspico-dldi`
2. `make`
3. Artifact: `DSpico.dldi`

### `bootloader`

1. `git clone https://github.com/LNH-team/dspico-bootloader`
2. `git submodule update --init`
3. `make`
4. `COPY --from=dldi` the `DSpico.dldi` file
5. `$DLDITOOL DSpico.dldi BOOTLOADER.nds`
6. Artifact: `BOOTLOADER.nds` (patched)

### `encryptor`

1. Uses `mcr.microsoft.com/dotnet/sdk:9.0` base
2. `git clone https://github.com/Gericom/DSRomEncryptor`
3. `dotnet build`
4. Artifact: compiled DSRomEncryptor at `DSRomEncryptor/bin/Debug/net9.0/`

### `encrypt`

1. Extends `encryptor` stage
2. `COPY --from=bootloader` the patched `BOOTLOADER.nds`
3. `COPY` blowfish key files from `BLOWFISH_DIR` into the DSRomEncryptor executable directory
4. Run `DSRomEncryptor BOOTLOADER.nds default.nds`
5. Artifact: `default.nds`

### `firmware`

1. Fresh `debian:bookworm-slim` base (does not use BlocksDS)
2. Install `cmake`, `gcc-arm-none-eabi`, `build-essential`, `git`, `python3`
3. `git clone https://github.com/LNH-team/dspico-firmware`
4. `git submodule update --init` then `cd pico-sdk && git submodule update --init && cd ..`
5. `COPY --from=encrypt` `default.nds` into `roms/`
6. If `ENABLE_WRFUXXED=true`:
   - `COPY --from=wrfuxxed` the patched `uartBufv060.bin` into `data/`
   - `COPY` the WRFU Tester ROM (from `WRFU_TESTER_ROM` build arg) to `roms/dsimode.nds`
   - Uncomment `DSPICO_ENABLE_WRFUXXED` in `CMakeLists.txt`
7. Run `./compile.sh`
8. Artifact: `build/DSpico.uf2`

### `loader`

1. `git clone https://github.com/LNH-team/pico-loader`
2. `git submodule update --init`
3. `make`
4. Artifacts: `picoLoader7.bin`, `picoLoader9_DSPICO.bin`, `data/aplist.bin`, `data/savelist.bin`

### `launcher`

1. `git clone https://github.com/LNH-team/pico-launcher`
2. `git submodule update --init`
3. `make`
4. Artifacts: `LAUNCHER.nds`, `_pico/` directory (themes)

### `wrfuxxed` (conditional — only when `ENABLE_WRFUXXED=true`)

1. `git clone https://github.com/LNH-team/dspico-wrfuxxed`
2. `make`
3. `COPY --from=dldi` the `DSpico.dldi` file
4. `$DLDITOOL DSpico.dldi uartBufv060.bin`
5. Artifact: `uartBufv060.bin` (patched)

### `output`

1. `COPY --from=firmware` `DSpico.uf2`
2. `COPY --from=loader` all loader artifacts
3. `COPY --from=launcher` `LAUNCHER.nds` and `_pico/` assets
4. Everything placed in `/out/`

## Project File Structure

```
ds-pico-setup/
├── Dockerfile
├── docker-compose.yml
├── Makefile
├── .gitignore              # ignores output/, blowfish keys
├── docs/
│   └── build-stages.md     # stage table with source links
└── output/                 # git-ignored, created by build
    ├── DSpico.uf2
    ├── LAUNCHER.nds
    ├── picoLoader7.bin
    ├── picoLoader9_DSPICO.bin
    ├── aplist.bin
    ├── savelist.bin
    └── sdcard/             # ready-to-copy SD layout
        ├── _pico/
        │   ├── themes/
        │   ├── aplist.bin
        │   ├── savelist.bin
        │   ├── picoLoader7.bin
        │   └── picoLoader9.bin
        └── _picoboot.nds
```

## Blowfish Key Setup

Users place their blowfish key files in the build context root (default) or a custom directory. Supported files per the DSRomEncryptor README:

| File | Purpose | Alternative |
|------|---------|-------------|
| `ntrBlowfish.bin` (SHA1: `84E467F2...`) | NTR blowfish table | `biosnds7.rom` (DS ARM7 BIOS dump) |
| `twlBlowfish.bin` (SHA1: `2DEA1119...`) | TWL retail blowfish table | `biosdsi7.rom` (DSi ARM7i BIOS dump) |
| `twlDevBlowfish.bin` (SHA1: `CFF62F24...`) | TWL dev blowfish table | -- |

At minimum, the NTR blowfish (via either file) is required. TWL blowfish is only needed for DSi/TWL hybrid ROMs.

## Conditional Wrfuxxed Build

When `ENABLE_WRFUXXED=true`:
1. The `wrfuxxed` stage is built
2. The firmware stage copies the exploit binary and WRFU Tester ROM
3. The `DSPICO_ENABLE_WRFUXXED` flag is uncommented in CMakeLists.txt
4. The firmware detects both `default.nds` and `dsimode.nds` and enables `DETECT_CONSOLE_TYPE`

When `ENABLE_WRFUXXED=false` (default):
- The `wrfuxxed` stage is skipped entirely
- Only `default.nds` is placed in the firmware `roms/` directory
- Standard DS Lite boot path only
