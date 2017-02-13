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

   REG_DATA_X0 = 0x32,      -- X-axis data 0
   REG_DATA_X1 = 0x33,      -- X-axis data 0
   REG_DATA_Y0 = 0x34,      -- X-axis data 0
   REG_DATA_Y1 = 0x35,      -- X-axis data 0
   REG_DATA_Z0 = 0x36,      -- X-axis data 0
   REG_DATA_Z1 = 0x37,      -- X-axis data 0
}

function check_for_sensor(addr)
   local status, buffer =
      i2c.txn(i2c.tx(addr, ADXL345.REG_DEVID),
              i2c.rx(addr, 1))
   local result = string.unpack("B", buffer)
   return (status and #buffer >= 1 and
              ADXL345.DEVID_RESULT == string.unpack("B", buffer))
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
   -- todo: verify that these come out in the order we expect them
   if status and #buffer == 6 then
      return string.unpack("i2i2i2", buffer) -- x,y,z
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

   if enable_measurement(activeAddress) then
      local x, y, z = get_reading(activeAddress)
      disable_measurement(activeAddress)

      if x and y and z then
         print("Read ("..x..", "..y..", "..z..")")
      else
         print("Failed to read")
      end
   else
      print("Failed to enable measurement")
   end
else
   print("NOT FOUND")
end

he.power_set(false)
