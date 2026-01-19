// ============================================================
// UwMiPhy PER Model (AWGN-based analytical PER for BPSK)
// ============================================================

#include "uwmi-phy.h"

#include <tclcl.h>
#include <mphy.h>
#include <mspectralmask.h>
#include <rect_spectral_mask.h>

#include <iostream>
#include <cmath>
#include <algorithm>
#include <cstdio>
#include <strings.h> // strcasecmp

int UwMiPhy::mi_modid = 0;

static class UwMiPhyClass : public TclClass {
public:
    UwMiPhyClass() : TclClass("Module/UW/MI/PHY") {}
    TclObject* create(int, const char* const*) { return (new UwMiPhy); }
} class_UwMiPhyClass;

/* ============================================================
 *                      CONSTRUCTOR
 * ============================================================ */
UwMiPhy::UwMiPhy()
    : NF_dB_(40.0),
      Rb_(1000.0),
      B_(1000.0),
      use_resonance_(1),
      f0_(1.0e6),
      Q_(50.0),
      debug_(0),
      Beff_Hz_(10000.0),
      Tnoise_K_(293.0),
      NoiseMargin_dB_(0.0)
{
    static bool registered = false;
    if (!registered) {
        mi_modid = MPhy::registerModulationType(MAGIND_MODULATION_TYPE);
        registered = true;
    }

    bind("TxPower_", &TxPower_);
    bind("Rb_", &Rb_);
    bind("B_", &B_);

    bind("AcquisitionThreshold_dB_", &AcquisitionThreshold_dB_);
    bind("use_auto_rx_power_gate_",  &use_auto_rx_power_gate_);
    bind("rxPowerThreshold_dBm_",    &rxPowerThreshold_dBm_);

    bind("rxPowerThreshold_",        &rxPowerThreshold_dBm_);

    bind("NF_dB_", &NF_dB_);
    bind("use_resonance_", &use_resonance_);
    bind("f0_", &f0_);
    bind("Q_", &Q_);

    bind("Beff_Hz_", &Beff_Hz_);
    bind("Tnoise_K_", &Tnoise_K_);

    bind("T_", &Tnoise_K_);

    // debug aliases 
    bind("debug_", &debug_);
    bind("mi_debug_", &debug_);

    bind("NoiseMargin_dB_", &NoiseMargin_dB_);
}

/* ===================== TRANSMIT SIDE ===================== */

void UwMiPhy::startTx(Packet* p)
{
    hdr_cmn*  ch = HDR_CMN(p);
    hdr_MPhy* ph = HDR_MPHY(p);

    if (!ph) {
        std::cerr << "UwMiPhy::startTx() ERROR: null MPhy header\n";
        return;
    }

    ph->modulationType = mi_modid;

    if (!spectralmask_) {
        spectralmask_ = new RectSpectralMask();
        spectralmask_->setFreq(f0_);
        spectralmask_->setBandwidth(B_);
    }
    ph->srcSpectralMask = spectralmask_;
    ph->dstSpectralMask = spectralmask_;

    double tx_watt = (TxPower_ > 0.0 && std::isfinite(TxPower_)) ? TxPower_ : 1e-9;
    ph->Pt = tx_watt;

    if (ch->txtime() <= 0.0) ch->txtime() = getTxDuration(p);

    ph->duration = ch->txtime();
    if (ph->duration <= 0.0) ph->duration = std::max(1e-9, getTxDuration(p));

    if (debug_) {
        std::cerr << NOW << " UwMiPhy::startTx(): Pt=" << ph->Pt
                  << " W (" << 10.0*log10(ph->Pt*1000.0) << " dBm)"
                  << " txtime=" << ch->txtime()
                  << " B=" << (spectralmask_ ? spectralmask_->getBandwidth() : B_) << " Hz"
                  << " f0=" << f0_ << " Hz\n";
    }

    MPhy_Bpsk::startTx(p);
}

/* ===================== RX SIDE ===================== */

void UwMiPhy::startRx(Packet* p)
{
    if ((PktRx == 0) && (txPending == false)) {
        hdr_MPhy* ph = HDR_MPHY(p);
        hdr_cmn*  ch = HDR_CMN(p);

        if (!spectralmask_) {
            spectralmask_ = new RectSpectralMask();
            spectralmask_->setFreq(f0_);
            spectralmask_->setBandwidth(B_);
        }

        if (ph) {
            if (!ph->srcSpectralMask) ph->srcSpectralMask = spectralmask_;
            if (!ph->dstSpectralMask) ph->dstSpectralMask = spectralmask_;
            if (!(ph->Pt > 0.0)) {
                double tx_watt = (TxPower_ > 0.0 && std::isfinite(TxPower_)) ? TxPower_ : 1e-9;
                ph->Pt = tx_watt;
            }

            const double Prx_W = getRxPower(p);
            const double N_W   = getNoisePower(p);
            ph->Pn = N_W;

            const double snr_dB  = 10.0*log10(std::max(Prx_W/N_W, 1e-12));
            const double thr_dB  = AcquisitionThreshold_dB_;

            const double Prx_dBm = 10.0*log10(Prx_W*1000.0 + 1e-30);
            const double N_dBm   = 10.0*log10(N_W*1000.0 + 1e-30);

            double Pthr_dBm = rxPowerThreshold_dBm_;
            if (use_auto_rx_power_gate_) {
                Pthr_dBm = N_dBm + AcquisitionThreshold_dB_;
            }

            if (debug_) {
                std::cout << NOW << " UwMiPhy::startRx(): "
                          << "snr_dB=" << snr_dB
                          << " thr_dB=" << thr_dB
                          << " Prx=" << Prx_dBm << " dBm"
                          << " N="   << N_dBm   << " dBm"
                          << " Pthr="<< Pthr_dBm << " dBm"
                          << " end@" << (NOW + ch->txtime())
                          << " size=" << ch->size() << std::endl;
            }

            if (snr_dB >= thr_dB && Prx_dBm >= Pthr_dBm) {
                ph->modulationType = mi_modid;
                PktRx = p;
                Phy2MacStartRx(p);
            }
            return;
        }
        return;
    }
    return;
}

void UwMiPhy::endRx(Packet *p)
{
    if (PktRx == 0) {
        if (debug_) std::cout << NOW << " UwMiPhy::endRx(): not synced -> drop\n";
        Packet::free(p);
        return;
    }

    if (PktRx != p) {
        if (debug_) std::cout << NOW << " UwMiPhy::endRx(): different pkt -> drop\n";
        Packet::free(p);
        return;
    }

    hdr_cmn *ch = HDR_CMN(p);
    hdr_MPhy *ph = HDR_MPHY(p);

    int bits = std::max(0, ch->size() * 8);

    double Prx_W = (ph && ph->Pr > 0.0) ? ph->Pr : getRxPower(p);
    double PER = computePER_(Prx_W, ph, bits);
    bool err = (RNG::defaultrng()->uniform_double() < PER);

    if (debug_) {
        std::cout << NOW << " UwMiPhy::endRx(): "
                  << "bits=" << bits
                  << " PER=" << PER
                  << " -> " << (err ? "ERR" : "OK") << std::endl;
    }

    sendUp(p);
    PktRx = 0;
}

/* ================= POWER / NOISE / PER HELPERS ================= */

double UwMiPhy::getRxPower(Packet *p)
{
    hdr_MPhy *ph = HDR_MPHY(p);

    double gain_lin = 1.0;
    if (propagation_) gain_lin = propagation_->getGain(p);

    double tx_power_lin = (TxPower_ > 0.0 && std::isfinite(TxPower_)) ? TxPower_ : 1e-9;
    double Prx_W = tx_power_lin * gain_lin;

    if (ph) ph->Pr = Prx_W;

    if (debug_) {
        std::cerr << NOW << " UwMiPhy::getRxPower(): "
                  << "gain=" << gain_lin
                  << " TxW=" << tx_power_lin << " W"
                  << " Prx=" << 10.0*log10(Prx_W*1000.0 + 1e-30) << " dBm\n";
    }

    return Prx_W;
}

double UwMiPhy::effectiveBandwidthHz_(hdr_MPhy *ph) const
{
    double Bmask = B_;
    if (ph && ph->srcSpectralMask && ph->srcSpectralMask->getBandwidth() > 0)
        Bmask = ph->srcSpectralMask->getBandwidth();

    if (!use_resonance_ || Q_ <= 0.0 || f0_ <= 0.0)
        return Bmask;

    const double Bres = f0_ / Q_;
    return std::max(1.0, std::min(Bmask, Bres));
}

double UwMiPhy::thermalNoise_W_(double Beff_Hz) const
{
    const double k = 1.38064852e-23;
    const double Flin = std::pow(10.0, NF_dB_ / 10.0);
    return std::max(1e-24, k * Tnoise_K_ * Beff_Hz * Flin);
}

double UwMiPhy::berBpskFromEbN0_(double ebn0_lin) const
{
    if (ebn0_lin <= 0.0) return 0.5;
    return 0.5 * std::erfc(std::sqrt(ebn0_lin));
}

double UwMiPhy::perFromBer_(double ber, int bits) const
{
    if (bits <= 0) return 0.0;
    if (ber <= 0.0) return 0.0;
    if (ber >= 1.0) return 1.0;

    const double p = 1.0 - ber;
    double per = 1.0 - std::pow(p, static_cast<double>(bits));

    if (per < 0.0) per = 0.0;
    else if (per > 1.0) per = 1.0;
    return per;
}

double UwMiPhy::computePER_(double Prx_W, hdr_MPhy* ph, int bits)
{
    const double Beff = std::max(1.0, effectiveBandwidthHz_(ph));
    const double N_W  = thermalNoise_W_(Beff);

    const double SNR_lin   = std::min(1e12, std::max(1e-12, Prx_W / N_W));
    const double Rb_lin    = std::max(1.0, Rb_);
    const double ebn0_lin  = SNR_lin * (Beff / Rb_lin)
                           / std::pow(10.0, NoiseMargin_dB_ / 10.0);

    const double BER = berBpskFromEbN0_(ebn0_lin);
    const double PER = perFromBer_(BER, bits);

    const double Prx_dBm = 10.0 * log10(Prx_W * 1000.0 + 1e-30);
    const double N_dBm   = 10.0 * log10(N_W   * 1000.0 + 1e-30);
    const double SNR_dB  = 10.0 * log10(SNR_lin + 1e-30);
    const double EbN0_dB = 10.0 * log10(ebn0_lin + 1e-30);

    std::printf("%0.6f UWMI_METRIC Prx_dBm=%g N_dBm=%g SNR_dB=%g EbN0_dB=%g Beff_Hz=%g Rb_bps=%g bits=%d PER_theory=%g\n",
                NOW, Prx_dBm, N_dBm, SNR_dB, EbN0_dB, Beff, Rb_lin, bits, PER);
    std::fflush(stdout);

    if (debug_) {
        std::cout << NOW << " UwMiPhy::computePER_(): "
                  << "Beff=" << Beff << " Hz, "
                  << "Bmask=" << B_ << " Hz, "
                  << "Q=" << Q_ << ", f0=" << f0_ << " Hz, "
                  << "NF=" << NF_dB_ << " dB, "
                  << "T=" << Tnoise_K_ << " K, "
                  << "Prx=" << Prx_W << " W, "
                  << "N=" << N_W << " W, "
                  << "SNR=" << SNR_dB << " dB, "
                  << "Eb/N0=" << EbN0_dB << " dB, "
                  << "BER=" << BER << ", "
                  << "PER=" << PER << std::endl;
    }
    return PER;
}

/* ===================== BASICS/UTILS ===================== */

double UwMiPhy::getTxDuration(Packet* p)
{
    hdr_cmn* ch = HDR_CMN(p);
    const double bitrate = std::max(1.0, Rb_);
    return (ch->size() * 8.0) / bitrate;
}

int UwMiPhy::getModulationType(Packet*) { return mi_modid; }

double UwMiPhy::getNoisePower(Packet* p)
{
    const double Beff = effectiveBandwidthHz_(HDR_MPHY(p));
    return thermalNoise_W_(Beff);
}

/* ===================== TCL INTERFACE ===================== */

int UwMiPhy::command(int argc, const char* const* argv)
{
    Tcl& tcl = Tcl::instance();

    if (argc == 2 && !strcasecmp(argv[1], "startTxTest")) {
        if (debug_) std::cout << NOW << " UwMiPhy: manual TX test\n";
        Packet* p = Packet::alloc();
        hdr_cmn*  ch = HDR_CMN(p);
        hdr_MPhy* ph = HDR_MPHY(p);
        ch->size() = 128;
        ch->ptype() = PT_CBR;
        ch->direction() = hdr_cmn::DOWN;
        if (!spectralmask_) {
            spectralmask_ = new RectSpectralMask();
            spectralmask_->setFreq(f0_);
            spectralmask_->setBandwidth(B_);
        }
        ph->srcSpectralMask = spectralmask_;
        ph->dstSpectralMask = spectralmask_;
        ph->modulationType  = mi_modid;
        startTx(p);
        return TCL_OK;
    }

    if (argc == 3) {
        if (!strcasecmp(argv[1], "setChannel")) {
            channel_ = (UwElectroMagneticChannel*) TclObject::lookup(argv[2]);
            if (!channel_) {
                tcl.resultf("Invalid channel name %s", argv[2]);
                return TCL_ERROR;
            }
            if (debug_) std::cout << "UwMiPhy: linked channel " << argv[2] << std::endl;
            return TCL_OK;
        }
        if (!strcasecmp(argv[1], "setPropagation")) {
            propagation_ = (UwMiCouplingPropagation*) TclObject::lookup(argv[2]);
            if (!propagation_) {
                tcl.resultf("Invalid propagation object %s", argv[2]);
                return TCL_ERROR;
            }
            if (debug_) std::cout << "UwMiPhy: linked propagation " << argv[2] << std::endl;
            return TCL_OK;
        }
        if (!strcasecmp(argv[1], "setAntenna")) {
            antenna_ = (Antenna*) TclObject::lookup(argv[2]);
            if (!antenna_) {
                tcl.resultf("Invalid antenna object %s", argv[2]);
                return TCL_ERROR;
            }
            if (debug_) std::cout << "UwMiPhy: linked antenna " << argv[2] << std::endl;
            return TCL_OK;
        }
    }

    int r = MPhy_Bpsk::command(argc, argv);
    if (r == TCL_ERROR) r = TclObject::command(argc, argv);
    return r;
}
