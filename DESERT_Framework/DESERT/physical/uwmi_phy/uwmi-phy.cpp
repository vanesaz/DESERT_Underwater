#include "uwmi-phy.h"
#include <iostream>
#include <cmath>

static class UwMiPhyClass : public TclClass {
public:
    UwMiPhyClass() : TclClass("Module/UW/MI/PHY") {}
    TclObject* create(int, const char*const*) { return (new UwMiPhy); }
} class_UwMiPhyClass;

UwMiPhy::UwMiPhy()
: T_(300), B_(1000), rxPowerThreshold_(-200)
{
    if (!MPhy_Bpsk::initialized) {
        MPhy_Bpsk::modid = MPhy::registerModulationType(MAGIND_MODULATION_TYPE);
        MPhy_Bpsk::initialized = true;
    }
    bind("T_", &T_);
    bind("B_", &B_);
    bind("rxPowerThreshold_", &rxPowerThreshold_);
    bind("debug_", &debug_);
}

void UwMiPhy::startRx(Packet *p)
{
    hdr_MPhy *ph = HDR_MPHY(p);
    if ((PktRx == 0) && (txPending == false)) {
        double rx_power_dB = 10 * log10(getRxPower(p));
        if (rx_power_dB > rxPowerThreshold_) {
            if (ph->modulationType == MPhy_Bpsk::modid) {
                PktRx = p;
                Phy2MacStartRx(p);
                return;
            } else if (debug_)
                std::cout << "UwMiPhy: drop wrong modulation\n";
        } else if (debug_) {
            std::cout << "UwMiPhy: below threshold, Prx=" << rx_power_dB
                      << " thr=" << rxPowerThreshold_ << "\n";
        }
    } else if (debug_)
        std::cout << "UwMiPhy: busy receiving another pkt\n";
}

void UwMiPhy::endRx(Packet *p)
{
    if (PktRx == p) {
        hdr_cmn *ch = HDR_CMN(p);
        double Prx_W = getRxPower(p);
        double PER = computePER(Prx_W);

        if (debug_)
            std::cout << "UwMiPhy: Prx=" << Prx_W
                      << " W  => PER=" << PER << "\n";

        ch->error() = (RNG::defaultrng()->uniform_double() < PER);
        sendUp(p);
        PktRx = 0;
    } else
        Packet::free(p);
}

double UwMiPhy::getRxPower(Packet *p)
{
    hdr_MPhy *ph = HDR_MPHY(p);
    double totalLoss_dB = propagation_->getGain(p);
    double rx_power_dB = TxPower_ - totalLoss_dB;
    return pow(10.0, rx_power_dB / 10.0); // Watts
}

double UwMiPhy::computePER(double Prx_W)
{
    double Nt = k_B * T_ * B_; // noise power
    double SNR = Prx_W / Nt;
    if (SNR <= 0) return 1.0;

    double BER = 0.5 * erfc(std::sqrt(SNR));
    double L_bits = 1024 * 8.0; // assume 1 kB packet
    double PER = 1.0 - pow(1.0 - BER, L_bits);
    if (PER < 0) PER = 0; if (PER > 1) PER = 1;
    return PER;
}
