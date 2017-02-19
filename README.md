# A few Helium sensor libraries.

This repo contains Lua code I've used with the [Helium Atom](https://www.helium.com/products/atom-development-board/) to talk to various sensors. Among them, you'll find:

 * *ms5607.lua* - Farnell's altimeter module MS5607
 * *adxl345.lua* - Analog Devices' accelerometer ADXL345
 * *lps22hb.lua* - The temperature and pressure sensor on-board the Helium Atom development board; code is from [helium/api-examples](https://github.com/helium/api-examples/)

A few other useful things that are here:

 * *queue.lua* - A simple way to stash readings, until there are "enough" to bother with turning on the radio to send them. Note: *not* persisent; will be lost if power is disconnected before they are sent to Helium.
 * *tilt.lua* - An example of using the ADXL345 (and the queue)
 * *sink.lua* - An example of using the MS5607 and the LPS22HB (and the queue)
 * *Makefile* - A workaround for the fact that `helium-script` doesn't work with Lua's `require`

## Tilt and ADXL345

The `tilt` example expects you to be using an ADXL345 configured in the same default way that [OSEPP's breakout board](https://www.osepp.com/electronic-modules/sensor-modules/55-adxl345-accelerometer-module) is configured: I2C at address 0x53 (CS high, SDO low).

Using the ribbon cable that came with the Helium Atom, connect:

 * Blue -> GND
 * Red -> VCC
 * Purple -> INT1
 * Brown -> SDA
 * Orange -> SCL

Run `make`. This will produce a new file, `tilt_upload.lua`. With the Atom on and connected to USB, run

```
$ helium-script tilt_upload.lua`
```

You will shortly see readings appear in your console:

```
Reading: (-246.6, -1.5, 64.3) @ 1.0
```

In the parentheses is (*x*, *y*, *z*), each value being on the scale of -512 to +512, where 256 represents 1g of force, and -256 represents -1g of force. The reading is the average of 10 readings made very quickly. The value after the @ is a ratio of how many of those readings were successful (1.0 = all of them).

New readings are taken once per minute. If you let the script run for ten minutes, it will post all ten readings to Helium, as separate `x`, `y`, and `z` ports.

## Sink and MS5607/LPS22HB

The `sink` example expects you to be using an MS5607 configured in the same way as [Parallax's breakout board's](https://www.parallax.com/product/29124) default configuration: I2C, address 0x76 (PS high, CS high).

Using the ribbon cable that came with the Helium Atom, connect:

 * Blue -> GND
 * Red -> VIN
 * Orange -> SCL
 * Brown -> SDA

Run `make`. This will produce a new file, `sink_upload.lua`. With the Atom on and connected to USB, run

```
$ helium-script sink_upload.lua`
```

In about a second, you should see readings of temperature and pressure:

```
Internal Temperature: 24.86621132946C Internal Pressure: 1001.2066256974mbar
External Temperature: 25.273C External Pressure: 1003.9500732422mbar
```

`Internal` is the MS5607, while `External` is the LPS22HB. Yes, this seems backward, but for my use case, the MS5607 (which you might expect to be "external" to the atom) is inside a carboy, and the LPS22HB (which you might consider "internal" to the atom) is outside the carboy.

New readings are taken every minute. If you let the script run for 10 minutes, it will post all ten readings to Helium.
