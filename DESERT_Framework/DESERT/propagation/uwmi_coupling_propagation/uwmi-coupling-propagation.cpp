#include "uwmi-coupling-propagation.h"
#include <node-core.h>

static class UwMiCouplingPropagationClass : public TclClass {
public:
    UwMiCouplingPropagationClass() : TclClass("Module/UW/MI/CouplingPropagation") {}
    TclObject* create(int, const char*const*) { return (new UwMiCouplingPropagation); }
} class_UwMiCouplingPropagation;

UwMiCouplingPropagation::UwMiCouplingPropagation()
: Nt_(20), Nr_(20), at_(0.10), ar_(0.10),
  Rt_(2.0), Rr_(2.0),
  kappa_(1.0), mu_r_(1.0),
  use_cond_loss_(1), sigma_(4.0),
  debug_(0),
  channel_(nullptr)   // ✅ initialize to null
{
    bind("Nt_", &Nt_);
    bind("Nr_", &Nr_);
    bind("at_", &at_);
    bind("ar_", &ar_);
    bind("Rt_", &Rt_);
    bind("Rr_", &Rr_);
    bind("kappa_", &kappa_);
    bind("mu_r_", &mu_r_);
    bind("use_cond_loss_", &use_cond_loss_);
    bind("sigma_", &sigma_);
    bind("debug_", &debug_);
}

int UwMiCouplingPropagation::command(int argc, const char*const* argv)
{
    Tcl& tcl = Tcl::instance();

    //Handle Tcl command: setChannel <ChannelObj>
    if (argc == 3 && strcasecmp(argv[1], "setChannel") == 0) {
        channel_ = (UwElectroMagneticChannel*) TclObject::lookup(argv[2]);
        if (channel_ == nullptr) {
            tcl.resultf("UwMiCouplingPropagation: invalid channel object %s", argv[2]);
            return TCL_ERROR;
        }
        if (debug_) {
            std::cout << "UwMiCouplingPropagation: linked to channel "
                      << argv[2] << std::endl;
        }
        return TCL_OK;
    }

    // Handle Tcl command: addPosition <PositionObj>
    if (argc == 3 && strcmp(argv[1], "addPosition") == 0) {
        Position* p = dynamic_cast<Position*>(TclObject::lookup(argv[2]));
        if (p) {
            positionList_.push_back(p);
            if (debug_) {
                std::cout << "UwMiCouplingPropagation: added position "
                          << p->getX() << "," << p->getY() << "," << p->getZ() << std::endl;
            }
            return TCL_OK;
        } else {
            std::cerr << "UwMiCouplingPropagation: invalid position object!" << std::endl;
            return TCL_ERROR;
        }
    }

    
    return MPropagation::command(argc, argv);
}

double UwMiCouplingPropagation::distanceUnderwater_(Position* sp, Position* rp)
{
    double dx = sp->getX() - rp->getX();
    double dy = sp->getY() - rp->getY();
    double dz = sp->getZ() - rp->getZ();
    return sqrt(dx*dx + dy*dy + dz*dz);
}

double UwMiCouplingPropagation::mutualInductance_(double d) const
{
    const double mu = MU_0 * mu_r_;
    const double At = M_PI * at_ * at_;
    const double Ar = M_PI * ar_ * ar_;
    return (mu * Nt_ * Nr_ * At * Ar) / (2.0 * M_PI * std::pow(d, 3.0));
}

double UwMiCouplingPropagation::conductiveFactor_(double f, double d) const
{
    if (!use_cond_loss_ || sigma_ <= 0.0) return 1.0;
    const double mu = MU_0 * mu_r_;
    const double w  = 2.0 * M_PI * f;
    const double delta = std::sqrt(2.0 / (w * mu * sigma_));
    const double L = std::exp(-2.0 * d / delta);
    return (L < 1e-12) ? 1e-12 : L;
}

double UwMiCouplingPropagation::getGain(Packet* p)
{
    if (debug_) std::cout << NOW << " UwMiCouplingPropagation::getGain() CALLED" << std::endl;
    hdr_MPhy *ph = HDR_MPHY(p);
    double f = ph->srcSpectralMask->getFreq();

    Position *sp = nullptr;
    Position *rp = nullptr;

    if (positionList_.size() >= 2) {
        sp = positionList_[0];
        rp = positionList_[1];
    } else {
        sp = ph->srcPosition;
        rp = ph->dstPosition;
    }

    if (!sp || !rp) {
        if (debug_)
            std::cerr << "UwMiCouplingPropagation: missing positions!" << std::endl;
        return 1e-30; // huge path loss if no positions
    }

    const double d = distanceUnderwater_(sp, rp);

    if (debug_) {
        std::cout << NOW << " UwMiCouplingPropagation: d=" << d
                  << " f=" << f << " Hz" << std::endl;
    }

    if (d <= 0.0) return 0.0;

    // --- Core coupling + medium losses ---
    const double M = mutualInductance_(d);
    const double w = 2.0 * M_PI * f;
    const double G_coupling = (kappa_ * kappa_) * (w * w * M * M) / (4.0 * Rt_ * Rr_);
    const double L_medium = conductiveFactor_(f, d);

    double G_total = G_coupling * L_medium;
    if (G_total < 1e-30)
        G_total = 1e-30;
    if (G_total > 1.0)   G_total = 1.0;

    const double PL_dB = -10.0 * std::log10(G_total);

    if (debug_) {
        std::cout << NOW << " UwMiCouplingPropagation: M=" << M
                  << " Gc=" << G_coupling
                  << " Lmed=" << L_medium
                  << " PLtot=" << PL_dB << " dB"
                  << " G_total=" << G_total 
                  << " (" << 10.0*log10(G_total) << " dB)"
                  << std::endl;
    }
    return G_total;

}
