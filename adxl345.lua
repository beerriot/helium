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

-- Setup a sensor. Expects to ping the sensor, so turn the power on first.
function ADXL345:new(address)
   address = address or ADXL345.ADDR_LOW
   local o = {addr = address}
   setmetatable(o, self)
   self.__index = self

   if o:check_for_sensor() then
      return o
   else
      print(string.format("ADXL345 did not respond at address 0x%X",
                          self.addr))
   end
end

-- Read DEVID register to make sure the sensor is present.
function ADXL345:check_for_sensor()
   local status, buffer =
      i2c.txn(i2c.tx(self.addr, self.REG_DEVID),
              i2c.rx(self.addr, 1))
   local result = string.unpack("B", buffer)
   return (status and #buffer >= 1 and
              self.DEVID_RESULT == string.unpack("B", buffer))
end

-- Flip into "full resolution" mode, instead of fixed 10-bit mode.
function ADXL345:set_full_resolution()
   local status =
      i2c.txn(i2c.tx(self.addr, self.REG_DATA_FORMAT,
                     self.DATA_FORMAT_FULL_RES))
   -- todo: read first, to avoid unsetting other bits

   return status
end

-- Start measuring. Set all configuration before calling this.
function ADXL345:enable_measurement()
   local status =
      i2c.txn(i2c.tx(self.addr, self.REG_POWER_CTL, self.POWER_CTL_MEASURE))
   -- todo: read first, to avoid unsetting other bits

   return status
end

-- Disable measuring. Save power, and change configuration after.
function ADXL345:disable_measurement()
   local status =
      i2c.txn(i2c.tx(self.addr, self.REG_POWER_CTL, 0x0))
   -- todo: read first, to avoid unsetting other bits

   return status
end

-- Read all REG_DATA_* registers in one go. Reading all of them at
-- once is required for correct FIFO use.
function ADXL345:get_reading()
   local status, buffer =
      i2c.txn(i2c.tx(self.addr, self.REG_DATA_X0),
              i2c.rx(self.addr, 6))
   if status and #buffer == 6 then
      return string.unpack("i2i2i2", buffer) -- x,y,z
   end
end

-- Put the FIFO into FIFO mode, with the given watermark. If interrupt
-- is true, also enable the watermark interrupt.
function ADXL345:enable_fifo(watermark, interrupt)
   local fifoval = self.FIFO_CTL_FIFO |
      (watermark & self.FIFO_CTL_SAMPLE_MASK)
   local status = i2c.txn(i2c.tx(self.addr, self.REG_FIFO_CTL, fifoval))

   if status and interrupt then
      status = i2c.txn(i2c.tx(self.addr, self.REG_INT_ENABLE,
                              self.INT_ENABLE_WATERMARK))
   end
   return status
end

-- Read the FIFO_STATUS register.
function ADXL345:get_fifo_status()
   local status, buffer = i2c.txn(i2c.tx(self.addr, self.REG_FIFO_STATUS),
                                  i2c.rx(self.addr, 1))
   if status then
      return string.unpack("B", buffer)
   end
end

-- Find out how many entries the FIFO is storing.
function ADXL345:get_fifo_entry_count()
   return (self:get_fifo_status() or 0) & self.FIFO_STATUS_ENTRIES_MASK
end

-- Read the INT_SOURCE register to find out what triggered the interrupt.
function ADXL345:get_interrupt_source()
   local status, buffer = i2c.txn(i2c.tx(self.addr, self.REG_INT_SOURCE),
                                  i2c.rx(self.addr, 1))
   if status then
      return string.unpack("B", buffer)
   end
end
