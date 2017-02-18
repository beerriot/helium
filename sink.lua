-- Use the MS5607 to detect and report pressure on a sink.
-- This file is concatenated with ms5607.lua, queue.lua.

he.power_set(true)

-- coefficients are PROM, so we only need to read them once
sensor = assert(MS5607:new(MS5607.ADDR_HIGH))

-- queue up our reports, so we don't turn on the antenna every time
-- send reports every 10 samples
Q = queue:new(10, {{name="ti", type="f"},
                   {name="pi", type="f"}})

-- prepare for reporting & sleeping
now = he.now()

-- number of samples to average to reduce noise
samples = 10

while true do
   local temp = 0
   local press = 0
   local failures = 0

   for i=1,10,1 do
      lt, lp = sensor:get_reading()
      if lt and lp then
         temp = temp + lt
         press = press + lp
      else
         failures = failures+1
      end
   end

   temp = temp / (samples-failures)
   press = press / (samples-failures)
   quality = (samples-failures) / samples

   -- report in degrees C and millibars
   Q:addEntry(now, {temp/100, press/100})

   print("Temperature: "..(temp/100).."C Pressure: "..(press/100).."mbar")

   -- power down while we wait until next reading
   he.power_set(false)
   now = he.wait({time=60*1000 + now})

   -- doing this here just makes the top of the loop cleaner
   he.power_set(true)
   sensor:reset()
end
