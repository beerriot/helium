-- Use the MS5607 to detect and report pressure on a sink.
-- This file is concatenated with ms5607.lua, queue.lua, lps22hb.lua.

he.power_set(true)

-- coefficients are PROM, so we only need to read them once
internal_sensor = assert(MS5607:new(MS5607.ADDR_HIGH))

-- use the sensors on board the atom as well
external_sensor = assert(lps22hb:new())

-- queue up our reports, so we don't turn on the antenna every time
-- send reports every 10 samples
Q = queue:new(10, {{name="ti", type="f"},
                   {name="pi", type="f"},
                   {name="t", type="f"},
                   {name="p", type="f"}})

-- prepare for reporting & sleeping
now = he.now()

-- number of samples to average to reduce noise
samples = 10

while true do
   local internal_temp = 0
   local internal_press = 0
   local external_temp = 0
   local external_press = 0
   local failures = 0

   for i=1,10,1 do
      ilt, ilp = internal_sensor:get_reading()
      elt = external_sensor:read_temperature()
      elp = external_sensor:read_pressure()
      if ilt and ilp and elt and elp then
         internal_temp = internal_temp + ilt
         internal_press = internal_press + ilp
         external_temp = external_temp + elt
         external_press = external_press + elp
      else
         failures = failures+1
      end
   end

   -- power down sensors as soon as possible
   he.power_set(false)

   internal_temp = internal_temp / (samples-failures)
   internal_press = internal_press / (samples-failures)
   external_temp = external_temp / (samples-failures)
   external_press = external_press / (samples-failures)
   quality = (samples-failures) / samples

   -- report in degrees C and millibars
   Q:addEntry(now, {internal_temp/100, internal_press/100,
                    external_temp,     external_press/100})

   print("Internal Temperature: "..(internal_temp/100)..
            "C Internal Pressure: "..(internal_press/100).."mbar")
   print("External Temperature: "..(external_temp)..
            "C External Pressure: "..(external_press/100).."mbar")

   -- wait a minute before reading again
   now = he.wait({time=60*1000 + now})

   -- doing this here just makes the top of the loop cleaner
   he.power_set(true)
   internal_sensor:reset()
end
