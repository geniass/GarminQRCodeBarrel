# Makefile for the QRCode Connect IQ barrel library.
# Build/release produce QRCode.barrel; the example watch app is for local testing.

SDK_HOME ?= "$(HOME)/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-8.4.0-2025-12-03-5122605dc"
MONKEYC     ?= $(SDK_HOME)/bin/monkeyc
MONKEYDO    ?= $(SDK_HOME)/bin/monkeydo
BARRELBUILD ?= $(SDK_HOME)/bin/barrelbuild
BARRELTEST  ?= $(SDK_HOME)/bin/barreltest

PRODUCT     ?= fr255
PRIVATE_KEY ?= ./developer_key

BARREL_NAME = QRCode
JUNGLE      = barrel.jungle

EXAMPLE_NAME   = qr-watch-app
EXAMPLE_JUNGLE = examples/qr-app/monkey.jungle

# ============================================
# Barrel
# ============================================

build:
	$(BARRELBUILD) -f $(JUNGLE) -o $(BARREL_NAME).barrel -w

release:
	mkdir -p bin/
	$(BARRELBUILD) -r -f $(JUNGLE) -o ./bin/$(BARREL_NAME).barrel -w -O=3z

test:
	$(BARRELTEST) -d $(PRODUCT) -f $(JUNGLE) -o /tmp/$(BARREL_NAME).prg -y $(PRIVATE_KEY) -w --debug-log-level=3
	@$(MONKEYDO) /tmp/$(BARREL_NAME).prg $(PRODUCT) -t | tee /tmp/$(BARREL_NAME).test.out; \
		grep -qE "^PASSED" /tmp/$(BARREL_NAME).test.out

# ============================================
# Example app (consumes the barrel)
# ============================================

build-example:
	$(MONKEYC) -d $(PRODUCT) -f $(EXAMPLE_JUNGLE) -o $(EXAMPLE_NAME).prg -y $(PRIVATE_KEY) -w --debug-log-level=3

run-example: build-example
	$(MONKEYDO) $(EXAMPLE_NAME).prg $(PRODUCT)

# ============================================

clean:
	rm -rf gen/ bin/
	rm -f $(BARREL_NAME).barrel $(BARREL_NAME).barrel.debug.xml
	rm -f $(EXAMPLE_NAME).prg $(EXAMPLE_NAME).prg.debug.xml

.PHONY: build release test build-example run-example clean
