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

-- Reset the part. Use after power on, before starting a conversion.
function ms5607reset(addr)
   i2c.txn(i2c.tx(addr, MS5607.CMD_RESET))
end

-- Read the ith coefficient.
-- Returns a 16-bit unsigned integer on success, nil on failure.
function read_coefficient(addr, i)
   local command = MS5607.CMD_PROM_READ |
      (MS5607.PROM_ADDR_MASK & (i * 2))
   local status, buffer = i2c.txn(i2c.tx(addr, command),
                                  i2c.rx(addr, 2))
   if status then
      return string.unpack(">I2", buffer)
   end
end

-- Read all coefficients.
-- Returns a Table with entry keys 0-7.
function read_coefficients(addr)
   local coefficients = {}
   
   for i=0,7,1 do
      coefficients[i] = read_coefficient(addr, i)
   end

   -- TODO: check CRC
   
   return coefficients
end

-- Tell the part to read its ADC and get its value ready to be read later.
-- Parameter 'sample' should be CONVERT_D1 (pressure) or CONVER_D2 (temp).
-- Parameter 'resolution' should be one of OSR_x
-- Wait for CONV_TIME_x after this function before calling read_adc.
function start_conversion(addr, sample, resolution)
   local cmd = MS5607.CMD_CONVERT | sample, resolution
   i2c.txn(i2c.tx(addr, cmd))
end

-- Read the last converted ADC value from the part.
-- Parameter 'resolution' should be one of OSR_x
-- Return value is an unsigned 24-bit integer.
function read_adc(addr, resolution)
   local status, buffer = i2c.txn(i2c.tx(addr, MS5607.CMD_ADC_READ),
                                  i2c.rx(addr, 3))
   if status then
      -- > big endian
      return string.unpack(">I3", buffer)
   end
end

-- Read both temperature and pressure (currently at resolution 4096)
-- Parameter 'coefficients' should be the table returned from read_coefficients
-- Returns 'temp, pressure' in /100s degrees C and /100s millibars
function get_reading(addr, coefficients)
   start_conversion(addr, MS5607.CONVERT_D1, MS5607.OSR_4096)
   he.wait{time=MS5607.CONV_TIME_4096 + he.now()}
   local uncompPres = read_adc(addr, MS5607.OSR_4096)

   start_conversion(addr, MS5607.CONVERT_D2, MS5607.OSR_4096)
   he.wait{time=MS5607.CONV_TIME_4096 + he.now()}
   local uncompTemp = read_adc(addr, MS5607.OSR_4096)

   -- first-order compensation
   local dT = uncompTemp - coefficients[5] * 256
   local temp =  2000 + dT * coefficients[6] / 8388608

   local off = coefficients[2] * 131072 +
      (coefficients[4] * dT) / 64
   local sens = coefficients[1] * 65536 +
      (coefficients[3] * dT) / 128
   local pres = (uncompPres * sens / 2097152 - off) / 32768

   return temp, pres
end

addr = MS5607.ADDR_HIGH
print(string.format("Using addr 0x%X", addr))

he.power_set(true)

-- coefficients are PROM, so we only need to read them once
ms5607reset(addr)
coefficients = read_coefficients(addr)

for i=1,6,1 do
   print("Coefficient["..i.."] = "..coefficients[i])
end

-- prepare for reporting & sleeping
now = he.now()

-- number of samples to average to reduce noise
samples = 10

while true do
   local temp = 0
   local press = 0
   local failures = 0

   for i=1,10,1 do
      lt, lp = get_reading(addr, coefficients)
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
   he.send("ti", now, "f", temp/100)
   he.send("pi", now, "f", press/100)

   print("Temperature: "..(temp/100).."C Pressure: "..(press/100).."mbar")

   -- power down while we wait until next reading
   he.power_set(false)
   now = he.wait({time=60*1000 + now})

   -- doing this here just makes the top of the loop cleaner
   he.power_set(true)
   ms5607reset(addr)
end
