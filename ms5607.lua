-- Library for the helium Atom to control a Farnell MS5607 Altimeter
-- Values are from datasheet at: http://www.farnell.com/datasheets/1756127.pdf

i2c = he.i2c

MS5607 = {
   -- address when CS pin is held high
   ADDR_HIGH = 0x76,
   -- address when CS pin is tied to GND
   ADDR_LOW = 0x77,

   --- COMMANDS

   CMD_RESET = 0x1E,       -- send after power on

   CMD_PROM_READ = 0xA0,   -- OR this with PROM address
   PROM_ADDR_MASK = 0x0E,  -- address is coef. no. shifted one left

   CMD_CONVERT = 0x40,  -- OR this with CONVERT_ and OSR_
   CONVERT_D1 = 0x00,
   CONVERT_D2 = 0x10,

   OSR_256 = 0x00,         -- low resolution
   OSR_512 = 0x02,
   OSR_1024 = 0x04,
   OSR_2048 = 0x06,
   OSR_4096 = 0x08,        -- high resolution

   CONV_TIME_256 = 1,      -- 0.6ms max
   CONV_TIME_512 = 2,      -- 1.17ms max
   CONV_TIME_1024 = 3,     -- 2.08ms max
   CONV_TIME_2048 = 5,     -- 4.54ms max
   CONV_TIME_4096 = 10,    -- 9.04ms max

   CMD_ADC_READ = 0x00,    -- read the value
}

-- Setup a sensor. Expects to load the coefficients from it, so turn
-- the power on first.
function MS5607:new(address)
   address = address or MS5607.ADDR_HIGH
   local o = {addr = address}
   setmetatable(o, self)
   self.__index = self

   -- load the coefficients to be ready for compensation
   o:reset()
   o.coefficients = o:_read_coefficients()

   if o.coefficients then
      return o
   end
end

-- Reset the part. Use after power on, before starting a conversion.
function MS5607:reset()
   i2c.txn(i2c.tx(self.addr, self.CMD_RESET))
end

-- Read the ith coefficient.
-- Returns a 16-bit unsigned integer on success, nil on failure.
function MS5607:_read_coefficient(i)
   local command = self.CMD_PROM_READ |
      (self.PROM_ADDR_MASK & (i * 2))
   local status, buffer = i2c.txn(i2c.tx(self.addr, command),
                                  i2c.rx(self.addr, 2))
   if status then
      return string.unpack(">I2", buffer)
   end
end

-- Read all coefficients.
-- Returns a Table with entry keys 0-7.
function MS5607:_read_coefficients()
   local coefficients = {}
   
   for i=0,7,1 do
      coefficients[i] = self:_read_coefficient(i)
      if not coefficients[i] then
         return -- the part is not working, don't let a program continue
      end
   end

   -- TODO: check CRC
   
   return coefficients
end

-- Tell the part to read its ADC and get its value ready to be read later.
-- Parameter 'sample' should be CONVERT_D1 (pressure) or CONVER_D2 (temp).
-- Parameter 'resolution' should be one of OSR_x
-- Wait for CONV_TIME_x after this function before calling read_adc.
function MS5607:_start_conversion(sample, resolution)
   local cmd = self.CMD_CONVERT | sample | resolution
   i2c.txn(i2c.tx(self.addr, cmd))
end

-- Read the last converted ADC value from the part.
-- Parameter 'resolution' should be one of OSR_x
-- Return value is an unsigned 24-bit integer.
function MS5607:_read_adc(resolution)
   local status, buffer = i2c.txn(i2c.tx(self.addr, self.CMD_ADC_READ),
                                  i2c.rx(self.addr, 3))
   if status then
      -- > big endian
      return string.unpack(">I3", buffer)
   end
end

-- Read both temperature and pressure (currently at resolution 4096)
-- Parameter 'coefficients' should be the table returned from read_coefficients
-- Returns 'temp, pressure' in /100s degrees C and /100s millibars
function MS5607:get_reading()
   self:_start_conversion(self.CONVERT_D1, MS5607.OSR_4096)
   he.wait{time=self.CONV_TIME_4096 + he.now()}
   local uncompPres = self:_read_adc(self.OSR_4096)

   self:_start_conversion(self.CONVERT_D2, self.OSR_4096)
   he.wait{time=self.CONV_TIME_4096 + he.now()}
   local uncompTemp = self:_read_adc(self.OSR_4096)

   -- first-order compensation
   local dT = uncompTemp - self.coefficients[5] * 256
   local temp =  2000 + dT * self.coefficients[6] / 8388608

   local off = self.coefficients[2] * 131072 +
      (self.coefficients[4] * dT) / 64
   local sens = self.coefficients[1] * 65536 +
      (self.coefficients[3] * dT) / 128
   local pres = (uncompPres * sens / 2097152 - off) / 32768

   return temp, pres
end
