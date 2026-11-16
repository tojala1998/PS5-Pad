BUILD ?= build
CFLAGS = -std=c11 -Wall -Wextra -Werror -O2
PS5_CC = $(PS5_PAYLOAD_SDK)/bin/prospero-clang

.PHONY: all check
all: $(BUILD)/ps5-keyboard-probe.elf
$(BUILD):
	mkdir -p "$@"
$(BUILD)/ps5-keyboard-probe.elf: probe.c ascii.h backend.h backend_ps5.c third_party/kbm.c third_party/kbm.h | $(BUILD)
	"$(PS5_CC)" $(CFLAGS) -ffunction-sections -fdata-sections -Wl,--gc-sections -o "$@" probe.c backend_ps5.c third_party/kbm.c -lSceUserService
$(BUILD)/probe-host: probe.c ascii.h backend.h backend_host.c | $(BUILD)
	$(CC) $(CFLAGS) -D_DEFAULT_SOURCE -DPROBE_HOST_TEST -DPROBE_PORT=19306 -DPROBE_IDLE_MS=500 -DPROBE_LIFETIME_MS=60000 -o "$@" probe.c backend_host.c
check: $(BUILD)/probe-host
	python3 test_probe.py "$(BUILD)/probe-host"
