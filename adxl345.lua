-- Library for the Helium Atom to control an Analog Devices ADXL345
-- Digital Accelerometer via I2C. Values are from datasheet at:
-- http://www.analog.com/static/imported-files/data_sheets/ADXL345.pdf

i2c = he.i2c

ADXL345 = {
   -- address when SDO/ALT ADDRESS pin is held high
   ADDR_HIGH = 0x1D,
   -- address when SDO/ALT ADDRESS pin is tied to GND
   ADDR_LOW = 0x53,

   --- REGISTERS

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
   print("fifoval: "..fifoval)
   local status = i2c.txn(i2c.tx(addr, ADXL345.REG_FIFO_CTL, fifoval))

   if status and interrupt then
      print("enabling watermark interrupt")
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

function get_interrupt_source(addr)
   local status, buffer = i2c.txn(i2c.tx(addr, ADXL345.REG_INT_SOURCE),
                                  i2c.rx(addr, 1))
   if status then
      return string.unpack("B", buffer)
   end
end

he.power_set(true)

if check_for_sensor(ADXL345.ADDR_LOW) then
   activeAddress = ADXL345.ADDR_LOW
elseif check_for_sensor(ADXL345.ADDR_HIGH) then
   activeAddress = ADXL345.ADDR_HIGH
end

if activeAddress then
   print("FOUND at address "..activeAddress)

   local x,y,z = 0,0,0
   local samples = 10

   get_reading(activeAddress) -- clear old data

   if enable_fifo(activeAddress, samples, true) then
      he.interrupt_cfg("int1", "e", 10)
      if enable_measurement(activeAddress) then
         -- waiting 0.5s, even though interrupt should come in 0.1s
         time, new_events, events = he.wait{time=500+he.now()}
         disable_measurement(activeAddress)

         local fifostat = get_fifo_status(activeAddress)

         if new_events then --or fifostat > samples then
            for i=1,samples,1 do
               local nx,ny,nz = get_reading(activeAddress)
               if nx and ny and nz then
                  x = x+nx
                  y = y+ny
                  z = z+nz
                  print("   "..i..": "..x.." "..y.." "..z)
               else
                  print("failed to read "..i)
               end
            end

            x = x / samples
            y = y / samples
            z = z / samples

            print("Read ("..x..", "..y..", "..z..")")
         else
            print("Timed out waiting for interrupt "..fifostat)
         end
      else
         print("Failed to enable measurement")
      end
   else
      print("Failed to enable interrupt")
   end

else
   print("NOT FOUND")
end

he.power_set(false)
