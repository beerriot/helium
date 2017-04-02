# NOTE: main script must be first in the list
TILT_SRCS=tilt.lua adxl345.lua queue.lua
SINK_SRCS=sink.lua ms5607.lua queue.lua lps22hb.lua

all: tilt.lpk sink.lpk

# Upload packages
tilt.lpk: $(TILT_SRCS)
	helium-script -p -m $(TILT_SRCS) -o tilt.lpk

sink.lpk: $(SINK_SRCS)
	helium-script -p -m $(SINK_SRCS) -o sink.lpk

# Directly run the script
tilt-test:
	helium-script -m $(TILT_SRCS)

sink-test:
	helium-script -m $(SINK_SRCS)
