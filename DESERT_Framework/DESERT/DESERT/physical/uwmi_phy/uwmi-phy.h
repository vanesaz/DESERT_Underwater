#ifndef UWMI_PHY_H
#define UWMI_PHY_H

#include <bpsk.h>
#include <rng.h>
#include <cmath>
#include <iostream>
#include <packet.h>


#define MAGIND_MODULATION_TYPE "MAGIND_BPSK"

// Physical constants
const double k_B = 1.38064852e-23; // Boltzmann constant [J/K]

/**
 * MI-aware PHY:
 * - Uses effective noise bandwidth = min(maskBW, f0/Q) if use_resonance_=1, else maskBW (or B_ fallback).
 * - Converts Prx -> SNR -> Eb/N0 using data rate Rb_.
 * - Computes BER (BPSK in AWGN) and PER for the actual packet length.
 */
class UwMiPhy : public MPhy_Bpsk
{
public:
    UwMiPhy();
    virtual ~UwMiPhy() {}

protected:

    virtual void startRx(Packet *p);
    virtual void endRx(Packet *p);

    // Helpers
    double getRxPower(Packet *p);                          // Watts
    double effectiveBandwidthHz_(hdr_MPhy *ph) const;      // Hz
    double thermalNoise_W_(double Beff_Hz) const;          // Watts
    double berBpskFromEbN0_(double ebn0_lin) const;        // unitless
    double perFromBer_(double ber, int bits) const;        // unitless [0..1]
    double computePER_(double Prx_W, hdr_MPhy *ph, int bits);
    double computeNoisePower_();                            // total noise k*T*B (optional)

    // ====== Bindable knobs (Tcl) ======
    // Environment / receiver
    double T_;                // Temperature [K] for kTB (default 300)
    double NF_dB_;            // Receiver noise figure [dB] (default 3 dB)
    double rxPowerThreshold_; // Power threshold [dBW] for carrier detect (default -200 dBW)

    // Data rate & fallback bandwidth
    double Rb_;               // Bit rate used by modem [bps] (default 1000)
    double B_;                // Fallback noise BW [Hz] if mask/resonance missing (default 1000)

    double Beff_Hz_;          // Effective bandwidth [Hz] for noise power
    double Tnoise_K_;         // Receiver noise temperature [K]

    // Resonance model
    int    use_resonance_;    // 0/1: limit noise BW to f0/Q when enabled
    double f0_;               // Coil resonance / tuned center frequency [Hz]
    double Q_;                // Coil quality factor (BW_res = f0/Q)

    // Debug
    int    debug_;
};

#endif /* UWMI_PHY_H */
