-- Use the ADXL3445 to detect and report the angle of a float.
-- This file is concatenated with adxl345.lua and queue.lua

-- number of samples to average for a reading
samples = 10

-- time to wait for sample interrupt
-- 10: default sample rate is 100Hz = 10ms/sample
-- 2: timeout at twice as long as expected
wait_time = (samples * 10) * 2

-- queue up our reports, so we don't turn on the antenna every time
-- send reports every 10 samples
Q = queue:new(10, {{name="x", type="f"},
                   {name="y", type="f"},
                   {name="z", type="f"}})

he.power_set(true)

sensor = assert(ADXL345:new(ADXL345.ADDR_LOW))

while true do
   cycle_now = he.now()

   -- values we'll fill
   local x,y,z = 0,0,0

   local fifofill = sensor:get_fifo_entry_count()
   for i=0,fifofill+1,1 do
      -- throw away old data; what's in the fifo, plus what's in
      -- the DATA registers
      sensor:get_reading()
   end

   -- setup fifo and interrupt hanlding
   if sensor:enable_fifo(samples, true) then
      he.interrupt_cfg("int1", "r", samples)

      if sensor:enable_measurement() then
         -- this is likely to be a short wait, so use a fresh now
         time, new_events, events = he.wait{time=wait_time+he.now()}

         -- save power as soon as possible
         sensor:disable_measurement()

         -- find out how many samples are available
         if new_events and events.int1 then
            read_samples = samples
         else
            read_samples = math.min(sensor:get_fifo_entry_count() or 0,
                                    samples)
         end

         -- read all samples
         failures = 0
         for i=1,read_samples,1 do
            local nx,ny,nz = sensor:get_reading()
            if nx and ny and nz then
               x = x+nx
               y = y+ny
               z = z+nz
            else
               failures = failures+1
            end
         end

         -- save power
         he.power_set(false)

         -- average readings
         x = x / (read_samples-failures)
         y = y / (read_samples-failures)
         z = z / (read_samples-failures)
         quality = (read_samples-failures)/samples

         -- report readings
         Q:addEntry(cycle_now, {x, y, z})

         print("Reading: ("..x..", "..y..", "..z..") @ "..quality)
      else
         he.power_set(false)
         print("Failed to enable measurement")
      end
   else
      he.power_set(false)
      print("Failed to enable interrupt")
   end

   -- wait for a minute (from start of this cycle)
   he.wait{time=60*1000 + cycle_now}
   he.power_set(true)
end
