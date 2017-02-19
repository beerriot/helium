TILT_SRCS=adxl345.lua queue.lua tilt.lua
SINK_SRCS=ms5607.lua queue.lua lps22hb.lua sink.lua

all: tilt_upload.lua sink_upload.lua

tilt_upload.lua: $(TILT_SRCS)
	cat $(TILT_SRCS) > tilt_upload.lua

sink_upload.lua: $(SINK_SRCS)
	cat $(SINK_SRCS) > sink_upload.lua
