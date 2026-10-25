// faust2lv2 -double lcrmeter.dsp  &&  sed -i -e 's/in0/In/g' -e 's/in1/InInv/g' -e 's/out0/Out/g' -e 's/out1/OutInv/g' -e 's/out2/Resr_Ohm/g' -e 's/out3/C_uF/g' -e 's/out4/L_mH/g' -e '/lv2:name "Freq Num/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "Rref Num/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "Filter/a\\tlv2:portProperty lv2:integer ;' -e 's/out4/L_mH/g' -e '/lv2:name "LOS/a\\tlv2:portProperty lv2:integer ;' -e 's/out5/ToVUmeter/g' -e '/lv2:name "LOS/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "OVL/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "UNCAL/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "RESONANT/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "REACTIVE/a\\tlv2:portProperty lv2:integer ;' lcrmeter.lv2/lcrmeter.ttl  &&  cp -R lcrmeter.lv2/ /usr/local/lib/lv2/

declare name "LCRMeter"; // No spaces for better JACK port names.
declare version "2026";
declare author "jpka";
declare license "MIT";
declare description "LCR Meter using differential signalling. Use two series resistors between stereo line-in and headphone out, then connect DUT to inputs: OutL [1k] InL, OutR [1k] InR, InL [DUT] InR";

import("stdfaust.lib");

/* Extra: inverter */
inv = xor (1);

/* Extra: RS flipflop. Edge activated: r=1, s=1, r=0 give out==0 when s still set */
posedge(x, y) = ((x' == 0) & (x != 0)) | ((y' == 0) & (y != 0));
rsff(r, s) = select2(r, s, 0) * posedge(r, s) : + ~ *(1-posedge(r, s));

reset = (ba.time == 1); /* Will it roll over? FIXME */

/* There is no button vs checkbox (aka lock button) difference yet. button() should have 'lv2:trigger' bit, while checkbox() should not. See https://github.com/falkTX/Carla/issues/2082  Meanwhile, use two button press. */
change = reset | (f_num != f_num') | (tx_lvl != tx_lvl');
calib = button ("[00] Calib");
calib_open = rsff(change | ((calib == 1) & (calib' == 0)), calib'');
calib_rref = rsff(change | calib, calib : inv) :
  inv : hbargraph("[01] UNCAL", 0, 1) : inv;

/* Do not forget to check if frequency is adequate for current sample rate. */
F(x) = rdtable(waveform{10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000}, x);
f_num = hslider ("[02] Freq Num", 3, 0, 10, 1) : int;
f = F(f_num) : hbargraph("[03] Freq Hz", 1.0, 1e6);

/* Two precision, low inductance series resistors. Ohm, per wire. */
R(x) = rdtable(waveform{100, 1e3, 10e3, 100e3, 1e6}, x);
r_num = hslider ("[04] Rref Num", 1, 0, 4, 1) : int;
Rref = R(r_num) : hbargraph("[05] Rref Ohm", 1.0, 1e6);

/* Set alsamixer: PCM, Master & Headphone: 100%, Line-in to min position when OVL still lit.
 * Then fine tune this to be just a bit below OVL goes out. */
tx_lvl = hslider ("[06] Tx Level", 1.0, 0.75, 1.0, 0.01);

/* Transmitter: goes to TX output, and to receiver heterodyne input */
stimuliI = os.osccos(f);
stimuliQ = os.oscsin(f);

/* Coherent receiver, with some alarms */
rxI(x) = x * stimuliI : fi.lowpass(3, 3.3) : video_filter : video_filter_more;
rxQ(x) = x * stimuliQ : fi.lowpass(3, 3.3) : video_filter : video_filter_more;
rxMag(i, q) = sqrt(i^2 + q^2) * 2.0
  /* Loss of signal, or Overload */
  <: _,(((< (0.001)) | (> (1.001))) : hbargraph("[07] LOS or OVL", 0, 1)) : attach;
rxAng(i, q) = atan2(i, q);

/* Meters after calibration */
/* Normalized voltage, for differential setup it show ~half (single-ended) voltage. */
mag_meter = hbargraph("[08] Mag, Volts", 0.0, 9.999);
ph_meter  = hbargraph("[09] Ang, Deg", -180, 180);

/* Visual filter. Note that it is not changes BW nor SNR nor Sensitivity */
flt = hslider ("[10] Filter", 0, 0, 2, 1) : int;  /* Three position button */
video_filter      = _ <: select2(flt,     _, si.smooth(1 - 1e-3));
video_filter_more = _ <: select2(flt > 1, _, si.smooth(1 - 1e-5));

/* LCR Math. See Tek appnote 75W-28152-2 "Capacitance and Inductance Measurements..." */

/* Internal (output) resistance is sum of: headphone output of codec, its output series resistor and capacitor, connectors, wires @ 1 kHz. It is important to measure it as precise as possible, then keep stable. Ohm, per mono wire. */
// Rout = 65.4;
/* Now it's also calibrated, so calibration is two stage: open the circuit, button On, connect Rref, button Off. */

/* This is unity by definition, as we scale it at calibration */
Va1 = 1.0;     // Volts

IS_DIFF = 2.0; // 1.0 for single-ended

/* Equation 2 */
Z(Va2,ang) = IS_DIFF * Va2 / sqrt(Va1^2 - 2.0 * Va1 * Va2 * cos(ang) + Va2^2) :
  min(1e9) <: / (ba.latch(calib_rref) : max(ma.EPSILON)) :
  * (Rref) :
  hbargraph("[11] Z, Ohm", 0.0, 1e7);

/* Equation 3 */
A(Va2,ang) = ang - atan(-Va2 * sin(ang) / (Va1 - Va2 * cos(ang))) :
  (_ <: _,(ma.rad2deg : hbargraph("[12] A, Deg", -180, 180)) : attach);

/* Equation 4 or 6 */
Resr(Z, A) = Z * cos(A) :
  hbargraph("[14] Resr, Ohm", -1e6, 1e7) :
  /* If DUT isn't single unit, but some circuit or tank; or, measure beyond rezonant frequency. */
  (_ < 0.0) : hbargraph("[13] RESONANT", 0, 1);

is_reactive = (abs : ma.rad2deg > 5.0) : hbargraph("[15] REACTIVE", 0, 1);

/* Equation 5 */
C(Z, A) = -1.0 / (2.0 * ma.PI * f * Z * sin(A)) :
  * (is_reactive(A)) : hbargraph("[16] C, F", -1.0, 9.999);

/* Equation 7 */
L(Z, A) = Z * sin(A) / (2.0 * ma.PI * f) :
  * (is_reactive(A)) : hbargraph("[17] L, H", -1.0, 99.99);

process =
  /* Test tone TX output, differential */
  ( stimuliI, -stimuliI : par(i, 2, * (tx_lvl)) : _, _),

  (
    /* Differential input */
    (_ - _) / IS_DIFF <:

    /* Quadrature receiver */
    (_ <: rxI, rxQ <: rxMag, rxAng :

    /* De-embed ref magnitude */
    (_ <: _ , (_ <: / (ba.latch(calib_open) : max(ma.EPSILON))) :> select2(calib_open) : mag_meter ),

    /* De-embed ref phase, FIXME make it simpler */
    (_ <: - (ba.latch(calib_open)) + (ma.PI * 3) : % (ma.PI * 2) : - (ma.PI) : ma.rad2deg : ph_meter : ma.deg2rad)

    <: Z, A

    <: Resr, C, L)

    /* External single channel (i.e. non-differential) measurement of input,
     * like VU meter or Spectrum analyzer, can be connected here */
    , _
  )
;
