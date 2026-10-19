# lcrmeter.dsp
lcrmeter.dsp is LCR Meter using Linux, sound card, LV2, and JACK
---

While your bench top setup probably equipped with good LCR Meter already, still it's often not available like at field tests, or at remote sites. If regular desktop PC with Linux and sound card available, it can be used instead.

Note that we will need blue stereo Line input connector. **It is always of great importance to select motherboards with such connector**. Sometimes it is possible to use `hdajackretask` magic to turn pink mono Mic connector into stereo Line In input (separate article, TODO). I also assume that you are familiar with `alsamixer`, `jack`, and `LV2` plugins using `Carla`.

Please read [^1] to get an idea how we can built it.

My LCR Meter uses differential signalling. Hardware required is two resistors (let's start at _1k Ohm_ value) between Line-in and Headphone out: `OutL [1k] InL`, `OutR [1k] InR`. Connect DUT (device under test) to inputs: `InL [DUT] InR` (later; now we leave it open circuit).

To use this `.dsp` code, install [carla](https://github.com/twonoise/carla-patches) and `faust`. **Note** that this Carla tree is equipped with display buttons and meters, not merged to main tree yet.

Compile & install the `LCRMeter` code, as shown at its head.

Then load `LCRMeter` plugin with Carla, and connect its stereo input and output to system sound output and input, either with Carla `Patchbay` tab, or `Graph` of `QJackCtl`. Other **plugin hosts** are can be used, when you are familiar with them.

Next, using `alsamixer`, set PCM and Headphone level to 100%. At inputs tab (`F4`), set Line-in gain to minimal position when _OVL_ of `LCRMeter` still lit. Then, fine tune _TX Level_ of `LCRMeter` to be just a bit below of level when _OVL_ goes out. This gives most powerful output level, yet have non overloaded signal path.

Now it's time to press `Calib` button of `LCRMeter`. As momentary pushbuttons are not supported yet (please check `.dsp` code for more info), it's need to push it twice (leave it at 'off' state). Calibration is of key importance, as we do not have 2nd stereo line input to connect it as `Va1` meter (see article). Calibration latches amplitude and phase of currently selected frequency, and uses it as reference. Phase here includes all propagation delays between output and input, include codec, driver, JACK buffers, so calibration effectively cancels it all, but at current frequency only. Recalibrate when frequency is changed. Calibration requires open circuit (DUT disconnected).

Now it's time to measure some electronic parts, and compare results with DT-9935 or other industrial LCR meter. Please report results here. **Discharge capacitor before connect!**

Note that `.dsp` code also acts as documentation, and it is intended to user enhancements.

SNR and EMI
-----------
I have used differential signalling. It doubles amplitude, halves input noise power of ADC, and greatly reduces EMI. That's why stereo input and output need.

There is coherent receiver with 3 stage, 3.3 Hz BW low pass filters. Squeezing it even narrower, produces more ringing and longer settle time, but welcome to try. I also provide video filter. Note that it's switch button is three positional.

LICENSE
=======
This manual for `LCRMeter`, together with its inlined pictures, are licensed under Creative Commons Attribution 4.0. You are welcome to contribute to the manual in order to improve it so long as your contributions are made available under this same license.

`LCRMeter` is MIT license.


[^1]: Tek appnote 75W-28152-2 "Capacitance and Inductance Measurements Using an Oscilloscope and a Function Generator" Rev. 02.2022
