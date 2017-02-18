TILT_SRCS=adxl345.lua queue.lua tilt.lua

tilt_upload.lua: $(TILT_SRCS)
	cat $(TILT_SRCS) > tilt_upload.lua
