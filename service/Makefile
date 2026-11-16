BUILD ?= build
PS5_CC = $(PS5_PAYLOAD_SDK)/bin/prospero-clang
CFLAGS = -std=c11 -Wall -Wextra -Werror -O1
HEADERS = payload/protocol.h payload/system.h

.PHONY: all check
all: $(BUILD)/padd-controller.elf

$(BUILD):
	mkdir -p "$@"

$(BUILD)/padd-controller.elf: payload/padd.c payload/system_ps5.c $(HEADERS) | $(BUILD)
	"$(PS5_CC)" $(CFLAGS) -o "$@" payload/padd.c payload/system_ps5.c -lSceUserService -lScePad -lSceSystemService

$(BUILD)/padd-host: payload/padd.c payload/system_host.c $(HEADERS) | $(BUILD)
	$(CC) $(CFLAGS) -D_DEFAULT_SOURCE -DPADD_HOST_TEST -o "$@" payload/padd.c payload/system_host.c

check: $(BUILD)/padd-host
	python3 smoke_test.py "$(BUILD)/padd-host"
