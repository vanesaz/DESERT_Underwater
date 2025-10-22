#ifndef UWMI_PHY_H
#define UWMI_PHY_H

#include <bpsk.h>
#include <rng.h>
#include <cmath>
#include <iostream>
#include <packet.h>

#define MAGIND_MODULATION_TYPE "MAGIND_BPSK"
const double k_B = 1.38064852e-23; // Boltzmann constant

class UwMiPhy : public MPhy_Bpsk
{
public:
    UwMiPhy();
    virtual ~UwMiPhy() {}

protected:
    virtual void startRx(Packet *p);
    virtual void endRx(Packet *p);

    double getRxPower(Packet *p);
    double computePER(double Prx_W);

    double T_;                // temperature
    double B_;                // bandwidth
    double rxPowerThreshold_; // dB threshold
    int    debug_;
};

#endif /* UWMI_PHY_H */
