// faust2lv2 -double lcrmeter.dsp  &&  sed -i -e 's/in0/In/g' -e 's/in1/InInv/g' -e 's/out0/Out/g' -e 's/out1/OutInv/g' -e 's/out2/Resr_Ohm/g' -e 's/out3/C_F/g' -e 's/out4/L_H/g' -e '/lv2:name "Freq/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "Rref/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "Filter/a\\tlv2:portProperty lv2:integer ;' -e 's/out4/L_mH/g' -e '/lv2:name "LOS/a\\tlv2:portProperty lv2:integer ;' -e 's/out5/Thru/g' -e 's/out6/NoiseOut/g' -e 's/out7/NoiseOutInv/g' -e '/lv2:name "LOS/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "OVL/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "UNCAL/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "RESONANT/a\\tlv2:portProperty lv2:integer ;' -e '/lv2:name "REACTIVE/a\\tlv2:portProperty lv2:integer ;' lcrmeter.lv2/lcrmeter.ttl  &&  cp -R lcrmeter.lv2/ /usr/local/lib/lv2/

declare name "LCRMeter"; // No spaces for better JACK port names.
declare version "2026";
declare author "jpka";
declare license "MIT";
declare description "LCR Meter using differential signalling. Use two series resistors between stereo line-in and headphone out, then connect DUT to inputs: OutL [1k] InL, OutR [1k] InR, InL [DUT] InR";

import("stdfaust.lib");

IS_DIFF = 2.0; // 1.0 for single-ended


/* I. Heterodyne section.
 * Goes to both: transmitter output, as well as, receiver heterodyne input */

stimuliI = os.osccos(f);
stimuliQ = os.oscsin(f);


/* II. Transmitter section */

/* Do not forget to check if frequency is adequate for current sample rate. */
F(x) = rdtable(waveform{10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000}, x);
f_num = hslider ("[02] [style:knob] Freq", 3, 0, 10, 1) : int;
f = F(f_num) : hbargraph("[03] [style:numerical] Freq Hz [unit:Hz]", 1.0, 1e6);

/* Two precision, low inductance series resistors. Ohm, per wire. */
R(x) = rdtable(waveform{100, 1e3, 10e3, 100e3}, x);
r_num = hslider ("[04] [style:knob] Rref", 1, 0, 3, 1) : int;
Rref = R(r_num) : hbargraph("[05] [style:numerical] Rref Ohm [unit:Ohm]", 1.0, 100e3);

/* Set alsamixer: PCM, Master & Headphone: 100%, Line-in to min position when OVL still lit.
 * Then fine tune this to be just a bit below OVL goes out. */
tx_lvl = hslider ("[06] [style:knob] Tx Level [unit:%]", 100, 75, 100, 0.1);


/* IIIa. Receiver section: Calibration latches */

/* Extra: inverter */
inv = xor (1);

/* Extra: RS flipflop. Edge activated: r=1, s=1, r=0 give out==0 when s still set */
posedge(x, y) = ((x' == 0) & (x != 0)) | ((y' == 0) & (y != 0));
rsff(r, s) = select2(r, s, 0) * posedge(r, s) : + ~ *(1-posedge(r, s));

/* There is no button vs checkbox (aka lock button) difference yet. button() should have 'lv2:trigger' bit, while checkbox() should not. See https://github.com/falkTX/Carla/issues/2082  Meanwhile, use two button press. */
change = (f_num != f_num') | (tx_lvl != tx_lvl');
calib = checkbox ("[00] Calib");

/* 1. Open the circuit (disconnect DUT), then 2. press Calib */
calib_open = rsff(change | ((calib == 1) & (calib' == 0)), calib'');

/* 3. Connect resistor same as Rref, then 4. release Calib, see UNCAL goes off */
calib_rref = rsff(change | calib, calib : inv) :
  inv : hbargraph("[01] [style:led] UNCAL", 0, 1) : inv;


/* IIIb. Receiver section: Heterodyne driven quadrature receiver */

/* Coherent receiver, with some alarms */
rxI(x) = x * stimuliI : fi.lowpass(3, 3.3) : video_filter : video_filter_more;
rxQ(x) = x * stimuliQ : fi.lowpass(3, 3.3) : video_filter : video_filter_more;
rxMag(i, q) = sqrt(i^2 + q^2) * 2.0
  /* Normal = 0, Loss of signal = 1 (Warning), Overload = 2 (Alarm) */
  <: _,(((< (0.001)) + (> (1.001)) * 2) : hbargraph("[07] [style:led] LOS OVL", 0, 2)) : attach;
rxAng(i, q) = atan2(i, q);

/* Meters after calibration */
/* Normalized voltage, for differential setup it show ~half (single-ended) voltage. */
mag_meter = hbargraph("[08] [style:numerical] Mag Volts [unit:V]", 0.0, 9.999);
ph_meter  = hbargraph("[09] [style:numerical] Ang Deg [unit:Deg]", -180, 180);

/* Visual filter. Note that it is not changes BW nor SNR nor Sensitivity */
flt = hslider ("[10] [style:menu{'Off':0;'Mid':1;'Full':2}] Filter", 0, 0, 2, 1) : int;  /* Three position button */
video_filter      = _ <: select2(flt,     _, si.smooth(1 - 1e-3));
video_filter_more = _ <: select2(flt > 1, _, si.smooth(1 - 1e-5));


/* IV. Processing section */

/* This is unity by definition, as we scale it at calibration */
Va1 = 1.0;     // Volts

/* LCR Math. See Tek appnote 75W-28152-2 "Capacitance and Inductance Measurements..." */
/* Equation 2 */
Z(Va2,ang) = IS_DIFF * Va2 / sqrt(Va1^2 - 2.0 * Va1 * Va2 * cos(ang) + Va2^2) :
  min(1e9) <: / (ba.latch(calib_rref) : max(ma.EPSILON)) :
  * (Rref) :
  hbargraph("[11] [style:numerical] Z Ohm [unit:Ohm]", 0.0, 1e7);

/* Equation 3 */
A(Va2,ang) = ang - atan(-Va2 * sin(ang) / (Va1 - Va2 * cos(ang))) :
  (_ <: _,(ma.rad2deg : hbargraph("[12] [style:numerical] A Deg [unit:Deg]", -180, 180) :
  /* Resistive = 0; Reactive = 1 (Info); Resonant = 2 (Alarm), which means DUT isn't single unit, but some circuit or tank; or, measure beyond rezonant frequency. */
  abs <: ((> (5.0)) + (> (90.0))) : hbargraph("[13] [style:led] REACTIVE", 0, 2)) :
  attach);

/* Equation 4 or 6 */
Resr(Z, A) = Z * cos(A) :
  hbargraph("[14] [style:numerical] Resr Ohm [unit:Ohm]", -1e6, 1e7);

is_good_reactive = (abs : ma.rad2deg <: (> (5.0)) * (< (90.0)));

/* Equation 5 */
C(Z, A) = -1.0 / (2.0 * ma.PI * f * Z * sin(A)) :
  * (is_good_reactive(A)) : hbargraph("[15] [style:numerical] C, F [unit:F]", -1.0, 9.9999);

/* Equation 7 */
L(Z, A) = Z * sin(A) / (2.0 * ma.PI * f) :
  * (is_good_reactive(A)) : hbargraph("[16] [style:numerical] L, H [unit:H]", -1.0, 99.999);


/* V. Standalone White Gaussian Noise source for Bode plots */
wgn = no.noise <: * (1), * (-1);


/* I/O and interconnections */

process = hgroup("LCR Meter",
  /* Test tone TX output, differential */
  (stimuliI <: * (tx_lvl) / 100.0, * (-tx_lvl) / 100.0 : _, _),

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

    <: Resr, C, L) /* With output pin for each */

    /* Thru output (after diff-to-single ended conversion).
     * VU meter or Spectrum analyzer can be connected here */
    , _
  ),

  (wgn : _, _)
);
