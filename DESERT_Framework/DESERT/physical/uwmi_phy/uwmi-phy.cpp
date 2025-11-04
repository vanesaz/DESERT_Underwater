// ============================================================
// UwMiPhy PER Model:
//   - AWGN-based analytical PER computation for BPSK
//   - Suitable for theoretical MI link characterization
//   - Parameters tuned via NF_dB_, TxPower_, Rb_, and B_
// ============================================================


#include "uwmi-phy.h"
#include <mphy.h>
#include <mspectralmask.h>
#include <rect_spectral_mask.h>
#include <iostream>
#include <cmath>
#include <algorithm>

int UwMiPhy::mi_modid = 0;

static class UwMiPhyClass : public TclClass {
public:
    UwMiPhyClass() : TclClass("Module/UW/MI/PHY/Custom") {}
    TclObject* create(int, const char* const*) { return (new UwMiPhy); }
} class_UwMiPhyClass;

/* ============================================================
 *                      CONSTRUCTOR
 * ============================================================ */
UwMiPhy::UwMiPhy()
    : NF_dB_(40.0),
      rxPowerThreshold_(-200.0),
      Rb_(1000.0),
      B_(1000.0),
      use_resonance_(1),
      f0_(1.0e6),
      Q_(50.0),
      debug_(0),
      PktTx_(nullptr),
      PktRx(nullptr),
      txPending(false),
      NoiseMargin_dB_(0.0)
{
    std::cout << "UwMiPhy constructor: debug_ initial=" << debug_ << std::endl;

    static bool registered = false;
    if (!registered) {
        mi_modid = MPhy::registerModulationType(MAGIND_MODULATION_TYPE);
        registered = true;
    }

    bind("TxPower_", &TxPower_);
    bind("Rb_", &Rb_);
    bind("B_", &B_);
    bind("rxPowerThreshold_", &rxPowerThreshold_);
    bind("mi_debug_", &debug_);
    bind("NF_dB_", &NF_dB_);
    bind("use_resonance_", &use_resonance_);
    bind("f0_", &f0_);
    bind("Q_", &Q_);
    bind("Beff_Hz_", &Beff_Hz_);
    bind("Tnoise_K_", &Tnoise_K_);
    bind("NoiseMargin_dB_", &NoiseMargin_dB_);

    Beff_Hz_ = 10000.0;
    Tnoise_K_ = 293.0;
}

/* ============================================================
 *                      TRANSMIT SIDE
 * ============================================================ */

void UwMiPhy::startTx(Packet* p)
{
    hdr_MPhy* ph = HDR_MPHY(p);
    if (!ph) {
        std::cerr << "UwMiPhy::startTx() ERROR: null MPhy header\n";
        return;
    }

    ph->modulationType = mi_modid;

    // Convert dBm → W safely
    double tx_watt = std::pow(10.0, (TxPower_ - 30.0) / 10.0);
    if (!(tx_watt > 0.0) || std::isnan(tx_watt) || std::isinf(tx_watt))
        tx_watt = 1e-9; // fallback

    
    ph->Pt = tx_watt;

    if (debug_) {
        std::cerr << NOW << " UwMiPhy::startTx(): TxPower_=" << TxPower_
                  << " dBm (" << tx_watt << " W), ph->Pt=" << ph->Pt << std::endl;
    }

    // Create mask if missing
    if (!spectralmask_) {
        spectralmask_ = new RectSpectralMask();
        spectralmask_->setFreq(f0_);
        spectralmask_->setBandwidth(B_);
    }
    ph->srcSpectralMask = spectralmask_;
    ph->dstSpectralMask = spectralmask_;

    double tx_time = getTxDuration(p);


    MPhy_Bpsk::startTx(p);

    if (!txPending) {
        txPending = true;
        Scheduler::instance().schedule(this, &tx_end_ev_, tx_time);
    }
    PktTx_ = p;
}


void UwMiPhy::handle(Event *)
{
    if (debug_) std::cout << NOW << " UwMiPhy::handle() -> endTx()\n";
    if (PktTx_) endTx(PktTx_);
    PktTx_ = nullptr;
}

void UwMiPhy::endTx(Packet *p)
{
    if (txPending) {
        txPending = false;
        if (debug_) std::cout << NOW << " UwMiPhy::endTx(): notify MAC\n";
        this->Phy2MacEndTx(p);
    }
}

/* ============================================================
 *                      RECEIVE SIDE
 * ============================================================ */
void UwMiPhy::startRx(Packet *p)
{
    if ((PktRx == nullptr) && !txPending) {
        double Prx_W = getRxPower(p);  
        hdr_MPhy *ph = HDR_MPHY(p);
        double Prx_dBm = 10.0 * log10(Prx_W * 1000.0 + 1e-30);

        if (debug_) {
            std::cout << NOW << " UwMiPhy::startRx(): Prx=" << Prx_W
                      << " W (" << Prx_dBm << " dBm)"
                      << " thr=" << rxPowerThreshold_ << " dBm\n";
        }

        if (Prx_dBm < rxPowerThreshold_ && debug_)
            std::cout << NOW << " below threshold but continuing to apply PER\n";

        if (HDR_MPHY(p)->modulationType != mi_modid) {
            if (debug_) std::cout << NOW << " UwMiPhy::startRx(): drop (wrong modulation)\n";
            return;
        }

        if (!propagation_) {
            std::cerr << NOW << " UwMiPhy::startRx(): WARNING - no propagation model linked\n";
        }

        PktRx = p;
        Phy2MacStartRx(p);
        return;
    }

    if (debug_) std::cout << NOW << " UwMiPhy::startRx(): busy\n";
}


void UwMiPhy::endRx(Packet *p)
{
    if (PktRx != p) {
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
        std::cout << NOW << " UwMiPhy::endRx(): Prx=" << Prx_W
                  << " W bits=" << bits
                  << " PER=" << PER
                  << " -> " << (err ? "DROP" : "OK") << "\n";
    }

    if (err) {
        ch->error() = 1;
        Packet::free(p);
    } else {
        ch->error() = 0;
        sendUp(p);
    }

    PktRx = nullptr;
}

/* ============================================================
 *                    SAFE SENDDOWN OVERRIDE
 * ============================================================ */
void UwMiPhy::sendDown(Packet *p)
{
    hdr_MPhy* ph = HDR_MPHY(p);
    if (!ph) {
        std::cerr << NOW << " UwMiPhy::sendDown(): ERROR null hdr_MPhy\n";
        return;
    }

    // Guarantee Pt > 0 before passing to channel
    if (ph->Pt <= 0.0 || std::isnan(ph->Pt) || std::isinf(ph->Pt)) {
        double tx_watt = pow(10.0, (TxPower_ - 30.0) / 10.0);
        if (tx_watt <= 0.0) tx_watt = 1e-9;
        ph->Pt = tx_watt;
        if (debug_) {
            std::cerr << NOW << " UwMiPhy::sendDown(): corrected Pt="
                      << ph->Pt << " W (" << 10 * log10(ph->Pt * 1000.0)
                      << " dBm)\n";
        }
    }

    // Call base class method to actually send the packet down
    MPhy_Bpsk::sendDown(p);
}



/* ============================================================
 *                  POWER / NOISE / PER HELPERS
 * ============================================================ */
double UwMiPhy::getRxPower(Packet *p)
{
    hdr_MPhy *ph = HDR_MPHY(p);
    double gain_lin = 1.0;

    if (propagation_) {
        gain_lin = propagation_->getGain(p);  
    }

    // Compute received power in W
    double tx_power_lin = pow(10.0, (TxPower_ - 30.0) / 10.0);
    double Prx_W = tx_power_lin * gain_lin;

    if (ph) ph->Pr = Prx_W;

    if (debug_) {
        double Prx_dBm = 10.0 * log10(Prx_W * 1000.0 + 1e-30);
        std::cerr << NOW
                  << " UwMiPhy::getRxPower(): gain=" << gain_lin
                  << "  Tx=" << TxPower_ << " dBm"
                  << "  Prx=" << Prx_dBm << " dBm"
                  << std::endl << std::flush;
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
    return k * Tnoise_K_ * Beff_Hz * Flin;
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

    const double one_minus_ber = std::max(0.0, 1.0 - ber);
    double per = 1.0 - std::pow(one_minus_ber, static_cast<double>(bits));

    if (per < 0.0) per = 0.0;
    else if (per > 1.0) per = 1.0;
    return per;
}

double UwMiPhy::computePER_(double Prx_W, hdr_MPhy *ph, int bits)
{
    const double Beff = effectiveBandwidthHz_(ph);
    const double N_W = thermalNoise_W_(Beff);
    const double SNR_lin = std::min(1e12, std::max(1e-6, Prx_W / N_W));

    const double Rb = std::max(1.0, Rb_);
    const double ebn0_lin = SNR_lin * (Beff / Rb) / pow(10.0, NoiseMargin_dB_/10.0);
    const double BER = berBpskFromEbN0_(ebn0_lin);
    const double PER = perFromBer_(BER, bits);

    if (debug_) {
        const double ebn0_dB = 10.0 * log10(ebn0_lin + 1e-30);
        std::cout << NOW 
                  << " UwMiPhy::computePER_(): "
                  << "Beff=" << Beff << " Hz, "
                  << "N=" << N_W << " W, "
                  << "SNR=" << 10*log10(SNR_lin) << " dB, "
                  << "Eb/N0=" << ebn0_dB << " dB, "
                  << "BER=" << BER << ", "
                  << "PER=" << PER << std::endl;
    }

    return PER;
}

double UwMiPhy::computeNoisePower_()
{
    const double k = 1.38064852e-23;
    return k * Tnoise_K_ * Beff_Hz_;
}

double UwMiPhy::getTxDuration(Packet *p)
{
    hdr_cmn *ch = HDR_CMN(p);
    double bitrate = std::max(1.0, Rb_);
    return (ch->size() * 8.0) / bitrate;
}

int UwMiPhy::getModulationType(Packet *) { return mi_modid; }

double UwMiPhy::getNoisePower(Packet *p)
{
    const double Beff = effectiveBandwidthHz_(HDR_MPHY(p));
    return thermalNoise_W_(Beff);
}

/* ============================================================
 *                      TCL INTERFACE
 * ============================================================ */
int UwMiPhy::command(int argc, const char* const* argv)
{
    Tcl &tcl = Tcl::instance();

    if (argc == 4 && !strcasecmp(argv[1], "set") && !strcasecmp(argv[2], "debug_")) {
        std::cout << "UwMiPhy: debug_ set to " << argv[3] << std::endl;
    }

    if (argc == 2 && !strcasecmp(argv[1], "startTxTest")) {
        if (debug_) std::cout << NOW << " UwMiPhy: manual TX test triggered\n";
        Packet *p = Packet::alloc();
        hdr_cmn *ch = HDR_CMN(p);
        hdr_MPhy *ph = HDR_MPHY(p);
        ch->size() = 128;
        ch->ptype() = PT_CBR;
        ch->direction() = hdr_cmn::DOWN;
        ph->modulationType = mi_modid;
        if (!spectralmask_) {
            spectralmask_ = new RectSpectralMask();
            spectralmask_->setFreq(1.0e6);
            spectralmask_->setBandwidth(1.0e4);
        }
        ph->srcSpectralMask = spectralmask_;
        ph->dstSpectralMask = spectralmask_;
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
            if (debug_) std::cout << "UwMiPhy linked to channel " << argv[2] << "\n";
            return TCL_OK;
        }
        if (!strcasecmp(argv[1], "setPropagation")) {
            propagation_ = (UwMiCouplingPropagation*) TclObject::lookup(argv[2]);
            if (!propagation_) {
                tcl.resultf("Invalid propagation object %s", argv[2]);
                return TCL_ERROR;
            }
            if (debug_) std::cout << "UwMiPhy linked to propagation " << argv[2] << "\n";
            return TCL_OK;
        }
        if (!strcasecmp(argv[1], "setAntenna")) {
            antenna_ = (Antenna*) TclObject::lookup(argv[2]);
            if (!antenna_) {
                tcl.resultf("Invalid antenna object %s", argv[2]);
                return TCL_ERROR;
            }
            if (debug_) std::cout << "UwMiPhy linked to antenna " << argv[2] << "\n";
            return TCL_OK;
        }
    }

    int result = MPhy_Bpsk::command(argc, argv);
    if (result == TCL_ERROR) result = TclObject::command(argc, argv);
    return result;
}
