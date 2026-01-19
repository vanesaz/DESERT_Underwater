#include "uwmi-coupling-propagation.h"

#include <node-core.h>
#include <packet.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <iostream>
#include <strings.h>

static class UwMiCouplingPropagationClass : public TclClass
{
public:
    UwMiCouplingPropagationClass()
        : TclClass("Module/UW/MI/CouplingPropagation")
    {
    }

    TclObject* create(int, const char* const*)
    {
        return (new UwMiCouplingPropagation);
    }
} class_UwMiCouplingPropagation;

UwMiCouplingPropagation::UwMiCouplingPropagation()
    : Nt_coils_(1)
    , Nr_coils_(1)
    , st_(0.0)
    , sr_(0.0)
    , auto_scale_R_(0)
    , Nt_(20)
    , Nr_(20)
    , at_(0.10)
    , ar_(0.10)
    , Rt_(2.0)
    , Rr_(2.0)
    , kappa_(1.0)
    , mu_r_(1.0)
    , use_cond_loss_(1)
    , sigma_(4.0)
    , debug_(0)
    , use_two_layer_(1)
    , channel_(nullptr)
{
    bind("Nt_coils_", &Nt_coils_);
    bind("Nr_coils_", &Nr_coils_);
    bind("st_", &st_);
    bind("sr_", &sr_);
    bind("auto_scale_R_", &auto_scale_R_);

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

    bind("use_two_layer_", &use_two_layer_);
}

int UwMiCouplingPropagation::command(int argc, const char* const* argv)
{
    Tcl& tcl = Tcl::instance();

    // setChannel <ChannelObj>
    if (argc == 3 && strcasecmp(argv[1], "setChannel") == 0) {
        channel_ = (UwElectroMagneticChannel*) TclObject::lookup(argv[2]);
        if (channel_ == nullptr) {
            tcl.resultf("UwMiCouplingPropagation: invalid channel object %s", argv[2]);
            return TCL_ERROR;
        }
        if (debug_) {
            std::cout << "UwMiCouplingPropagation: linked to channel " << argv[2] << std::endl;
        }
        return TCL_OK;
    }

    // addPosition <PositionObj>
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
    const double dx = sp->getX() - rp->getX();
    const double dy = sp->getY() - rp->getY();
    const double dz = sp->getZ() - rp->getZ();
    return std::sqrt(dx*dx + dy*dy + dz*dz);
}

double UwMiCouplingPropagation::mutualInductance_onepair_(double d) const
{
    const double mu = MU_0 * mu_r_;
    const double At = M_PI * at_ * at_;
    const double Ar = M_PI * ar_ * ar_;
    return (mu * Nt_ * Nr_ * At * Ar) / (2.0 * M_PI * std::pow(d, 3.0));
}

void UwMiCouplingPropagation::coilOffsets_(int N, double s, std::vector<double>& out) const
{
    out.clear();
    if (N <= 0) return;
    if (N == 1) { out.push_back(0.0); return; }

    // center the stack around 0: offsets = (i - (N-1)/2)*s
    const double c = 0.5 * (N - 1);
    out.reserve(N);
    for (int i = 0; i < N; ++i) {
        out.push_back((i - c) * s);
    }
}

double UwMiCouplingPropagation::sumMutualInductance_(double d_center) const
{
    std::vector<double> tOff, rOff;
    coilOffsets_(std::max(1, Nt_coils_), st_, tOff);
    coilOffsets_(std::max(1, Nr_coils_), sr_, rOff);

    double Msum = 0.0;
    for (double dt : tOff) {
        for (double dr : rOff) {
            const double dij = std::fabs(d_center + dr - dt);
            const double d_safe = (dij > 1e-9) ? dij : 1e-9;
            Msum += mutualInductance_onepair_(d_safe);
        }
    }
    return Msum;
}

double UwMiCouplingPropagation::conductiveFactor_(double f, double d) const
{
    if (!use_cond_loss_ || sigma_ <= 0.0) return 1.0;

    const double mu = MU_0 * mu_r_;
    const double w  = 2.0 * M_PI * f;
    if (w <= 0.0) return 1.0;

    const double delta = std::sqrt(2.0 / (w * mu * sigma_));
    const double L = std::exp(-2.0 * d / delta);
    return (L < 1e-12) ? 1e-12 : L;
}

UwMiCouplingPropagation::TwoLayerSeg
UwMiCouplingPropagation::splitUnderwaterAir_(Position* sp, Position* rp) const
{
    const double x1 = sp->getX(), y1 = sp->getY(), z1 = sp->getZ();
    const double x2 = rp->getX(), y2 = rp->getY(), z2 = rp->getZ();

    const double dx = x2 - x1, dy = y2 - y1, dz = z2 - z1;
    const double d_total = std::sqrt(dx*dx + dy*dy + dz*dz);
    if (d_total <= 0.0) return {0.0, 0.0};

    // both below water
    if (z1 < 0.0 && z2 < 0.0) return {d_total, d_total};
    // both in air
    if (z1 >= 0.0 && z2 >= 0.0) return {d_total, 0.0};

    // crossing case: guard dz
    if (std::fabs(dz) < 1e-12) {
        const double d_water = (z1 < 0.0) ? d_total : 0.0;
        return {d_total, d_water};
    }

    // crosses the interface at z=0: P(t)=P1 + t*(P2-P1)
    const double t0 = (0.0 - z1) / dz;

    double d_water = 0.0;
    if (z1 < 0.0 && z2 >= 0.0) {
        const double wx = dx * t0, wy = dy * t0, wz = dz * t0;
        d_water = std::sqrt(wx*wx + wy*wy + wz*wz);
    } else {
        const double wx = dx * (1.0 - t0), wy = dy * (1.0 - t0), wz = dz * (1.0 - t0);
        d_water = std::sqrt(wx*wx + wy*wy + wz*wz);
    }
    return {d_total, d_water};
}

double UwMiCouplingPropagation::getGain(Packet* p)
{
    if (debug_) {
        std::cout << NOW << " UwMiCouplingPropagation::getGain() CALLED" << std::endl;
    }

    hdr_MPhy* ph = HDR_MPHY(p);
    if (!ph || !ph->srcSpectralMask) {
        if (debug_) std::cerr << "UwMiCouplingPropagation: missing MPhy header/spectral mask.\n";
        return 1e-30;
    }

    const double f = ph->srcSpectralMask->getFreq();

    Position* sp = (positionList_.size() >= 2) ? positionList_[0] : ph->srcPosition;
    Position* rp = (positionList_.size() >= 2) ? positionList_[1] : ph->dstPosition;

    if (!sp || !rp) {
        if (debug_) std::cerr << "UwMiCouplingPropagation: missing positions!\n";
        return 1e-30;
    }

    TwoLayerSeg seg;
    if (use_two_layer_) {
        seg = splitUnderwaterAir_(sp, rp);
    } else {
        const double dx = rp->getX() - sp->getX();
        const double dy = rp->getY() - sp->getY();
        const double dz = rp->getZ() - sp->getZ();
        const double d  = std::sqrt(dx*dx + dy*dy + dz*dz);
        seg = { d, d };
    }

    const double d_total = seg.d_total;
    if (d_total <= 0.0) return 1e-30;

    const double M  = sumMutualInductance_(d_total);
    const double w  = 2.0 * M_PI * f;

    const double Rt_eff = (auto_scale_R_ ? std::max(1, Nt_coils_) * Rt_ : Rt_);
    const double Rr_eff = (auto_scale_R_ ? std::max(1, Nr_coils_) * Rr_ : Rr_);

    const double Gc = (kappa_ * kappa_) * (w*w * M*M) / (4.0 * Rt_eff * Rr_eff);

    const double Lm = (use_cond_loss_) ? conductiveFactor_(f, seg.d_water) : 1.0;

    double G = Gc * Lm;
    if (G < 1e-30) G = 1e-30;
    if (G > 1.0)   G = 1.0;

    if (debug_) {
        std::cout << NOW
                  << " UwMiCouplingPropagation:"
                  << " d_tot="    << d_total
                  << " d_water="  << seg.d_water
                  << " Nt_coils=" << Nt_coils_
                  << " Nr_coils=" << Nr_coils_
                  << " st="       << st_
                  << " sr="       << sr_
                  << " Rt_eff="   << Rt_eff
                  << " Rr_eff="   << Rr_eff
                  << " Msum="     << M
                  << " Gc="       << Gc
                  << " Lm="       << Lm
                  << " PL="       << (-10.0 * std::log10(G)) << " dB"
                  << std::endl;
    }

    return G;
}
