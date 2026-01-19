#ifndef UWMI_COUPLING_PROPAGATION_H
#define UWMI_COUPLING_PROPAGATION_H

#include <mpropagation.h>
#include <mphy.h>
#include <iostream>
#include <cmath>
#include <vector>

#ifndef MU_0
#define MU_0 (4.0e-7 * M_PI) // H/m
#endif


class UwElectroMagneticChannel;

class UwMiCouplingPropagation : public MPropagation
{
public:
    UwMiCouplingPropagation();
    virtual ~UwMiCouplingPropagation() {}

    virtual int command(int argc, const char *const *argv);
    virtual double getGain(Packet *p); // returns linear power gain [0..1]

protected:
    // Coil/transceiver params (bind-able from Tcl)
    int    Nt_coils_;   // number of physical coils at Tx (>=1)
    int    Nr_coils_;   // number of physical coils at Rx (>=1)
    double st_;         // spacing between Tx coils [m] (center-to-center along axis)
    double sr_;         // spacing between Rx coils [m]
    int    auto_scale_R_; // 0/1: if 1, Rt_/Rr_ are per-coil values (series connect)
    double Nt_;      // turns (Tx)
    double Nr_;      // turns (Rx)
    double at_;      // Tx coil radius [m]
    double ar_;      // Rx coil radius [m]
    double Rt_;      // Tx resistance [Ohm]
    double Rr_;      // Rx resistance [Ohm]
    double kappa_;   // orientation factor [0..1]
    double mu_r_;    // relative permeability (~1 in water)
    int  use_two_layer_;   // 0/1; 

    // Medium conductive loss
    int    use_cond_loss_; // 0/1
    double sigma_;         // conductivity [S/m]

    int debug_;            // verbose mode

    // Linked EM channel
    UwElectroMagneticChannel* channel_;

    // Helpers
    double distanceUnderwater_(Position* sp, Position* rp);
    double mutualInductance_onepair_(double d) const;
    double sumMutualInductance_(double d_center) const;
    void   coilOffsets_(int N, double s, std::vector<double>& out) const;
    double conductiveFactor_(double f, double d) const; // attenuation [0..1]
    struct TwoLayerSeg { double d_total; double d_water; };
    TwoLayerSeg splitUnderwaterAir_(Position* sp, Position* rp) const;

    // Store positions passed from Tcl
    std::vector<Position*> positionList_;
};

#endif /* UWMI_COUPLING_PROPAGATION_H */