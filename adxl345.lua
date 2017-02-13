-- Library for the Helium Atom to control an Analog Devices ADXL345
-- Digital Accelerometer via I2C

i2c = he.i2c

ADXL345 = {
   ADDR = 0x53,

   REG_DEVID = 0x00,
   REG_DEVID_LEN = 1,
   REG_DEVID_RESULT = 0xE5,
}

function check_for_sensor()
   local status, buffer =
      i2c.txn(i2c.tx(ADXL345.ADDR, ADXL345.REG_DEVID),
              i2c.rx(ADXL345.ADDR, ADXL345.REG_DEVID_LEN))
   local result = string.unpack("B", buffer)
   return (status and #buffer >= 1 and
              ADXL345.REG_DEVID_RESULT == string.unpack("B", buffer))
end

he.power_set(true)
if check_for_sensor() then
   print("FOUND")
else
   print("NOT FOUND")
end
he.power_set(false)
