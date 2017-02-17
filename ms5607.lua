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

function ms5607reset(addr)
   i2c.txn(i2c.tx(addr, MS5607.CMD_RESET))
end

function read_coefficient(addr, i)
   local command = MS5607.CMD_PROM_READ |
      (MS5607.PROM_ADDR_MASK & (i * 2))
   local status, buffer = i2c.txn(i2c.tx(addr, command),
                                  i2c.rx(addr, 2))
   if status then
      return string.unpack(">I2", buffer)
   end
end

function read_coefficients(addr)
   local coefficients = {}
   
   for i=0,7,1 do
      coefficients[i] = read_coefficient(addr, i)
   end

   -- TODO: check CRC
   
   return coefficients
end

function start_conversion(addr, sample, resolution)
   local cmd = MS5607.CMD_CONVERT | sample, resolution
   i2c.txn(i2c.tx(addr, cmd))
end

function read_adc(addr, resolution)
   local status, buffer = i2c.txn(i2c.tx(addr, MS5607.CMD_ADC_READ),
                                  i2c.rx(addr, 3))

   if status then
      -- > big endian
      return string.unpack(">I3", buffer)
   end
end

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

ms5607reset(addr)
coefficients = read_coefficients(addr)

for i=1,6,1 do
   print("Coefficient["..i.."] = "..coefficients[i])
end

temp, pres = get_reading(addr, coefficients)

print("Temperature: "..temp.." Pressure: "..pres)

he.power_set(false)
