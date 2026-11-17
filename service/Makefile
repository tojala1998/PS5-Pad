BUILD ?= build
PS5_CC = $(PS5_PAYLOAD_SDK)/bin/prospero-clang
CFLAGS = -std=c11 -Wall -Wextra -Werror -O1
KEYBOARD = ../experiments/keyboard-probe/third_party/kbm.c
COMMON = payload/padd.c payload/owner_monitor.c payload/text_input.c payload/live_keyboard.c
HEADERS = payload/protocol.h payload/system.h payload/ownership.h payload/owner_monitor.h payload/text_input.h payload/live_keyboard.h ../experiments/keyboard-probe/ascii.h ../experiments/keyboard-probe/third_party/kbm.h

.PHONY: all check
all: $(BUILD)/padd-controller.elf

$(BUILD):
	mkdir -p "$@"

$(BUILD)/padd-controller.elf: $(COMMON) payload/system_ps5.c payload/text_backend_ps5.c $(KEYBOARD) $(HEADERS) | $(BUILD)
	"$(PS5_CC)" $(CFLAGS) -ffunction-sections -fdata-sections -Wl,--gc-sections -o "$@" $(COMMON) payload/system_ps5.c payload/text_backend_ps5.c $(KEYBOARD) -lSceUserService -lScePad -lSceSystemService

$(BUILD)/padd-host: $(COMMON) payload/system_host.c payload/text_backend_host.c $(HEADERS) | $(BUILD)
	$(CC) $(CFLAGS) -D_DEFAULT_SOURCE -DPADD_HOST_TEST -o "$@" $(COMMON) payload/system_host.c payload/text_backend_host.c

check: $(BUILD)/padd-host
	python3 smoke_test.py "$(BUILD)/padd-host"
	python3 initialization_test.py "$(BUILD)/padd-host"
	python3 ownership_test.py "$(BUILD)/padd-host"
	python3 text_input_test.py "$(BUILD)/padd-host"
	python3 live_keyboard_test.py "$(BUILD)/padd-host"
	python3 app_state_test.py "$(BUILD)/padd-host"
	python3 power_off_test.py "$(BUILD)/padd-host"
	python3 power_api_test.py
