#include "uwmi-phy.h"
#include <iostream>
#include <cmath>

static class UwMiPhyClass : public TclClass {
public:
    UwMiPhyClass() : TclClass("Module/UW/MI/PHY") {}
    TclObject* create(int, const char*const*) { return (new UwMiPhy); }
} class_UwMiPhyClass;

UwMiPhy::UwMiPhy()
: T_(300.0),
  NF_dB_(3.0),
  rxPowerThreshold_(-200.0),   // dBW
  Rb_(1000.0),                 // 1 kbps default
  B_(1000.0),                  // 1 kHz fallback
  use_resonance_(1),
  f0_(1.0e6),                  // default 1 MHz tuned center
  Q_(50.0),                    // example Q
  debug_(0)
{
    if (!MPhy_Bpsk::initialized) {
        MPhy_Bpsk::modid = MPhy::registerModulationType(MAGIND_MODULATION_TYPE);
        MPhy_Bpsk::initialized = true;
    }

    bind("T_", &T_);
    bind("B_", &B_);
    bind("rxPowerThreshold_", &rxPowerThreshold_);
    bind("debug_", &debug_);

    // New binds
    bind("NF_dB_", &NF_dB_);
    bind("Rb_", &Rb_);
    bind("use_resonance_", &use_resonance_);
    bind("f0_", &f0_);
    bind("Q_", &Q_);

    // Explicit noise control (for Tcl)
    bind("Beff_Hz_", &Beff_Hz_);
    bind("Tnoise_K_", &Tnoise_K_);

    Beff_Hz_ = 10000.0;   // Default 10 kHz effective noise bandwidth
    Tnoise_K_ = 293.0;    // Default receiver temperature
}

void UwMiPhy::startRx(Packet *p)
{
    hdr_MPhy *ph = HDR_MPHY(p);
    if ((PktRx == 0) && (txPending == false)) {
        // Threshold check in dBW 
        double Prx_W = getRxPower(p);
        double Prx_dBW = 10.0 * log10(Prx_W + 1e-30);

        if (Prx_dBW > rxPowerThreshold_) {
            if (ph->modulationType == MPhy_Bpsk::modid) {
                if (debug_) std::cout << "UwMiPhy: ACCEPT startRx, Prx_dBW=" << Prx_dBW << " thr=" << rxPowerThreshold_ << "\n";
                PktRx = p;
                Phy2MacStartRx(p);
                return;
            } else if (debug_) {
                std::cout << "UwMiPhy: drop wrong modulation\n";
            }
        } else if (debug_) {
            std::cout << "UwMiPhy: below threshold, Prx=" << Prx_dBW
                      << " dBW thr=" << rxPowerThreshold_ << "\n";
        }
    } else if (debug_) {
        std::cout << "UwMiPhy: busy receiving another pkt\n";
    }
}

void UwMiPhy::endRx(Packet *p)
{
    if (PktRx == p) {
        hdr_cmn *ch = HDR_CMN(p);
        hdr_MPhy *ph = HDR_MPHY(p);

        // Real packet length, not a fixed 1 kB
        const int pkt_bits = std::max(0, ch->size() * 8);

        const double Prx_W = getRxPower(p);
        const double PER = computePER_(Prx_W, ph, pkt_bits);

        if (debug_) {
            std::cout << "UwMiPhy: Prx=" << Prx_W << " W  pkt_bits=" << pkt_bits
                      << " => PER=" << PER << "\n";
        }

        ch->error() = (RNG::defaultrng()->uniform_double() < PER);
        sendUp(p);
        PktRx = 0;
    } else {
        Packet::free(p);
    }
}

double UwMiPhy::getRxPower(Packet *p)
{

    double totalLoss_dB = propagation_->getGain(p);
    double rx_power_dB = TxPower_ - totalLoss_dB; // dBW if TxPower_ is dBW
    return pow(10.0, rx_power_dB / 10.0);         // -> Watts
}

double UwMiPhy::effectiveBandwidthHz_(hdr_MPhy *ph) const
{
    // Mask BW if available; otherwise fallback to B_
    double Bmask = B_;
    if (ph && ph->srcSpectralMask) {
 
        if (ph->srcSpectralMask->getBandwidth() > 0) {
            Bmask = ph->srcSpectralMask->getBandwidth();
        }
    }

    if (!use_resonance_ || Q_ <= 0.0 || f0_ <= 0.0) return Bmask;

    const double Bres = f0_ / Q_;   // 3 dB bandwidth of RLC
    return std::max(1.0, std::min(Bmask, Bres));
}

double UwMiPhy::thermalNoise_W_(double Beff_Hz) const
{
    // k T B F
    const double Flin = std::pow(10.0, NF_dB_ / 10.0);
    return k_B * T_ * Beff_Hz * Flin;
}

double UwMiPhy::berBpskFromEbN0_(double ebn0_lin) const
{
    // BER = Q(sqrt(2 Eb/N0)) = 0.5 * erfc(sqrt(Eb/N0))
    if (ebn0_lin <= 0.0) return 0.5; // ~random
    return 0.5 * erfc(std::sqrt(ebn0_lin));
}

double UwMiPhy::perFromBer_(double ber, int bits) const
{
    if (bits <= 0) return 0.0;
    if (ber <= 0.0) return 0.0;
    if (ber >= 1.0) return 1.0;
    // PER = 1 - (1-BER)^{bits}
    const double one_minus_ber = std::max(0.0, 1.0 - ber);
    double per = 1.0 - std::pow(one_minus_ber, static_cast<double>(bits));
    if (per < 0.0) per = 0.0;
    if (per > 1.0) per = 1.0;
    return per;
}

double UwMiPhy::computePER_(double Prx_W, hdr_MPhy *ph, int bits)
{
    // Effective noise bandwidth (mask & resonance)
    const double Beff = effectiveBandwidthHz_(ph);

    // Thermal noise at the receiver
    const double N_W = thermalNoise_W_(Beff);

    // SNR over Beff
    const double SNR_lin = (N_W > 0.0) ? (Prx_W / N_W) : 0.0;

    // Convert to Eb/N0 using configured bit-rate (Rb_)
    const double Rb = std::max(1.0, Rb_);
    const double ebn0_lin = SNR_lin * (Beff / Rb);

    // Compute bit and packet error probabilities
    const double BER = berBpskFromEbN0_(ebn0_lin);
    const double PER = perFromBer_(BER, bits);

    if (debug_) {
        const double ebn0_dB = 10.0 * std::log10(ebn0_lin + 1e-30);
        const double N_dBW   = 10.0 * std::log10(N_W + 1e-30);
        std::cout << "UwMiPhy DBG: Beff=" << Beff
                  << " Hz  N=" << N_W << " W (" << N_dBW << " dBW)"
                  << "  Rb=" << Rb
                  << "  Eb/N0=" << ebn0_lin << " (" << ebn0_dB << " dB)"
                  << "  BER=" << BER << "  PER=" << PER << std::endl;
    }

    return PER;
}


double UwMiPhy::computeNoisePower_()
{
    const double k = 1.38064852e-23; // Boltzmann
    return k * Tnoise_K_ * Beff_Hz_;
}

