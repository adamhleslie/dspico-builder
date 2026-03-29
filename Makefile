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
# Each target: build stage with --load, create temp container, docker cp artifacts out.

output/DSpico.uf2: output/.firmware
output/.firmware:
	$(BUILDX) --target firmware --load -t dspico-firmware .
	@mkdir -p output
	@cid=$$(docker create dspico-firmware) && \
		docker cp $$cid:/build/build/DSpico.uf2 output/DSpico.uf2 && \
		docker rm $$cid > /dev/null
	@touch $@

output/LAUNCHER.nds output/_pico: output/.launcher
output/.launcher:
	$(BUILDX) --target launcher --load -t dspico-launcher .
	@mkdir -p output
	@cid=$$(docker create dspico-launcher) && \
		docker cp $$cid:/build/LAUNCHER.nds output/LAUNCHER.nds && \
		docker cp $$cid:/build/_pico output/_pico && \
		docker rm $$cid > /dev/null
	@touch $@

output/picoLoader7.bin output/picoLoader9_DSPICO.bin output/aplist.bin output/savelist.bin: output/.loader
output/.loader:
	$(BUILDX) --target loader --load -t dspico-loader .
	@mkdir -p output
	@cid=$$(docker create dspico-loader) && \
		docker cp $$cid:/build/picoLoader7.bin output/picoLoader7.bin && \
		docker cp $$cid:/build/picoLoader9_DSPICO.bin output/picoLoader9_DSPICO.bin && \
		docker cp $$cid:/build/data/aplist.bin output/aplist.bin && \
		docker cp $$cid:/build/data/savelist.bin output/savelist.bin && \
		docker rm $$cid > /dev/null
	@touch $@

# Convenience aliases
firmware: output/DSpico.uf2
launcher: output/LAUNCHER.nds
loader: output/picoLoader7.bin

dldi:
	$(BUILDX) --target dldi --load -t dspico-dldi .
	@mkdir -p output
	@cid=$$(docker create dspico-dldi) && \
		docker cp $$cid:/build/DSpico.dldi output/DSpico.dldi && \
		docker rm $$cid > /dev/null

# Builds through the encrypt stage; output is default.nds (encrypted bootloader)
bootloader:
	$(BUILDX) --target encrypt --load -t dspico-encrypt .
	@mkdir -p output
	@cid=$$(docker create dspico-encrypt) && \
		docker cp $$cid:/build/default.nds output/default.nds && \
		docker rm $$cid > /dev/null
