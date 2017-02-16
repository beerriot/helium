-- Library for the Helium Atom to control an Analog Devices ADXL345
-- Digital Accelerometer via I2C. Values are from datasheet at:
-- http://www.analog.com/static/imported-files/data_sheets/ADXL345.pdf

i2c = he.i2c

ADXL345 = {
   -- address when SDO/ALT ADDRESS pin is held high
   ADDR_HIGH = 0x1D,
   -- address when SDO/ALT ADDRESS pin is tied to GND
   ADDR_LOW = 0x53,

   --- REGISTERS (and their associated values)

   REG_DEVID = 0x00,
   DEVID_RESULT = 0xE5, -- expected result of reading REG_DEVID

   REG_OFSX = 0x1E,         -- X-axis offset
   REG_OFSY = 0x1F,         -- Y-axis offset
   REG_OFSZ = 0x20,         -- Z-axis offset

   REG_BW_RATE = 0x2C,      -- data rate and power mode
   REG_POWER_CTL = 0x2D,    -- power savings features control
   POWER_CTL_MEASURE = 0x08,-- enable measurement

   REG_DATA_FORMAT = 0x31,  -- data format control
   DATA_FORMAT_FULL_RES = 0x08, -- note: not applicable to 2g

   REG_DATA_X0 = 0x32,      -- X-axis data 0
   REG_DATA_X1 = 0x33,      -- X-axis data 0
   REG_DATA_Y0 = 0x34,      -- X-axis data 0
   REG_DATA_Y1 = 0x35,      -- X-axis data 0
   REG_DATA_Z0 = 0x36,      -- X-axis data 0
   REG_DATA_Z1 = 0x37,      -- X-axis data 0

   REG_FIFO_CTL = 0x38,     -- FIFO setup
   FIFO_CTL_BYPASS = 0x00,  -- no FIFO used
   FIFO_CTL_FIFO = 0x40,    -- FIFO up to 32 samples
   FIFO_CTL_STREAM = 0x80,  -- FIFO latest 32 samples
   FIFO_CTL_TRIGGER = 0xc0, -- FIFO trigger 32 samples
   FIFO_CTL_SAMPLE_MASK = 0x1F, -- number of sample for watermark

   REG_FIFO_STATUS = 0x39,  -- FIFO status
   FIFO_STATUS_ENTRIES_MASK = 0x3F, -- entry count

   REG_INT_ENABLE = 0x2E,   -- interrupt enable
   INT_ENABLE_WATERMARK = 0x02, -- watermark interrupt

   REG_INT_SOURCE = 0x30,   -- source of interrupt
}

function check_for_sensor(addr)
   local status, buffer =
      i2c.txn(i2c.tx(addr, ADXL345.REG_DEVID),
              i2c.rx(addr, 1))
   local result = string.unpack("B", buffer)
   return (status and #buffer >= 1 and
              ADXL345.DEVID_RESULT == string.unpack("B", buffer))
end

function set_full_resolution(addr)
   local status =
      i2c.txn(i2c.tx(addr, ADXL345.REG_DATA_FORMAT,
                     ADXL345.DATA_FORMAT_FULL_RES))
   -- todo: read first, to avoid unsetting other bits

   return status
end

function enable_measurement(addr)
   local status =
      i2c.txn(i2c.tx(addr, ADXL345.REG_POWER_CTL, ADXL345.POWER_CTL_MEASURE))
   -- todo: read first, to avoid unsetting other bits

   return status
end

function disable_measurement(addr)
   local status =
      i2c.txn(i2c.tx(addr, ADXL345.REG_POWER_CTL, 0x0))
   -- todo: read first, to avoid unsetting other bits

   return status
end

function get_reading(addr)
   local status, buffer =
      i2c.txn(i2c.tx(addr, ADXL345.REG_DATA_X0),
              i2c.rx(addr, 6))
   if status and #buffer == 6 then
      return string.unpack("i2i2i2", buffer) -- x,y,z
   end
end

function enable_fifo(addr, watermark, interrupt)
   local fifoval = ADXL345.FIFO_CTL_FIFO |
      (watermark & ADXL345.FIFO_CTL_SAMPLE_MASK)
   local status = i2c.txn(i2c.tx(addr, ADXL345.REG_FIFO_CTL, fifoval))

   if status and interrupt then
      status = i2c.txn(i2c.tx(addr, ADXL345.REG_INT_ENABLE,
                              ADXL345.INT_ENABLE_WATERMARK))
   end
   return status
end

function get_fifo_status(addr)
   local status, buffer = i2c.txn(i2c.tx(addr, ADXL345.REG_FIFO_STATUS),
                                  i2c.rx(addr, 1))
   if status then
      return string.unpack("B", buffer)
   end
end

function get_fifo_entry_count(addr)
   return (get_fifo_status(addr) or 0) & ADXL345.FIFO_STATUS_ENTRIES_MASK
end

function get_interrupt_source(addr)
   local status, buffer = i2c.txn(i2c.tx(addr, ADXL345.REG_INT_SOURCE),
                                  i2c.rx(addr, 1))
   if status then
      return string.unpack("B", buffer)
   end
end

-- address we expect ADXL345 to be using
addr = ADXL345.ADDR_LOW

-- number of samples to average for a reading
samples = 10

-- time to wait for sample interrupt
-- 10: default sample rate is 100Hz = 10ms/sample
-- 2: timeout at twice as long as expected
wait_time = (samples * 10) * 2

while true do
   he.power_set(true)
   cycle_now = he.now()
   if check_for_sensor(addr) then
      -- values we'll fill
      local x,y,z = 0,0,0

      local fifofill = get_fifo_entry_count(addr)
      for i=0,fifofill+1,1 do
         -- throw away old data; what's in the fifo, plus what's in
         -- the DATA registers
         get_reading(addr)
      end

      -- setup fifo and interrupt hanlding
      if enable_fifo(addr, samples, true) then
         he.interrupt_cfg("int1", "r", samples)

         if enable_measurement(addr) then
            -- this is likely to be a short wait, so use a fresh now
            time, new_events, events = he.wait{time=wait_time+he.now()}

            -- save power as soon as possible
            disable_measurement(addr)

            -- find out how many samples are available
            if new_events and events.int1 then
               read_samples = samples
            else
               read_samples = math.min(get_fifo_entry_count(addr) or 0,
                                       samples)
            end

            -- read all samples
            failures = 0
            for i=1,read_samples,1 do
               local nx,ny,nz = get_reading(addr)
               if nx and ny and nz then
                  x = x+nx
                  y = y+ny
                  z = z+nz
               else
                  failures = failures+1
               end
            end

            -- average readings
            x = x / (read_samples-failures)
            y = y / (read_samples-failures)
            z = z / (read_samples-failures)
            quality = (read_samples-failures)/samples

            -- report readings
            he.send("x", cycle_now, "f", x)
            he.send("y", cycle_now, "f", y)
            he.send("z", cycle_now, "f", z)
            he.send("q", cycle_now, "f", quality)

            print("Reading: ("..x..", "..y..", "..z..") @ "..quality)
         else
            print("Failed to enable measurement")
         end
      else
         print("Failed to enable interrupt")
      end
   else
      print(string.format("ADXL345 did not respond at address 0x%X", addr))
   end

   -- wait for a minute (from start of this cycle)
   he.power_set(false)
   he.wait{time=60*1000 + cycle_now}
end
