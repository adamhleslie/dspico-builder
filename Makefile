.PHONY: all firmware dldi bootloader loader launcher sdcard clean

# Build args (override via environment or command line)
BLOWFISH_DIR ?= .
ENABLE_WRFUXXED ?= false

BUILD_ARGS = \
	--build-arg BLOWFISH_DIR=$(BLOWFISH_DIR) \
	--build-arg ENABLE_WRFUXXED=$(ENABLE_WRFUXXED)

BUILDX = docker buildx build $(BUILD_ARGS)

# --- Top-level targets ---

all: output/DSpico.uf2 output/LAUNCHER.nds output/picoLoader7.bin

sdcard: all
	@rm -rf output/sdcard
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

# Builds through the encrypt stage; output is default.nds (encrypted bootloader)
bootloader:
	$(BUILDX) --target encrypt --output type=local,dest=output/encrypt .
	mv output/encrypt/default.nds output/default.nds
	rm -rf output/encrypt
