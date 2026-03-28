# DSPico Build Stages

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
