#ifndef UWMI_PHY_H
#define UWMI_PHY_H
#include "../../../.unpacked_folder/nsmiracle-1.1.7/mphy/bpsk.h"
#include <bpsk.h>
#include <rng.h>
#include <cmath>
#include <iostream>
#include <packet.h>

#include "../../channel/uwem_channel/uwem-channel.h"        
#include "../../physical/uwem_antenna/uwem-antenna.h"
#include "../../propagation/uwmi_coupling_propagation/uwmi-coupling-propagation.h"


#define MAGIND_MODULATION_TYPE "MAGIND_BPSK"

const double k_B = 1.38064852e-23;

class UwMiPhy : public MPhy_Bpsk {
public:
    // Links set via Tcl commands
    UwElectroMagneticChannel* channel_ = nullptr;
    UwMiCouplingPropagation*  propagation_ = nullptr;
    Antenna*                  antenna_ = nullptr;

    UwMiPhy();
    virtual ~UwMiPhy() {}

    double getTxDuration(Packet* p) override;
    int    getModulationType(Packet* p) override;
    double getNoisePower(Packet* p) override;
    int    command(int argc, const char* const* argv) override;

protected:
    void   startTx(Packet* p) override;
    void   startRx(Packet* p) override;
    void   endRx(Packet* p) override;

    double getRxPower(Packet* p) override;
    double effectiveBandwidthHz_(hdr_MPhy* ph) const;
    double thermalNoise_W_(double Beff_Hz) const;
    double berBpskFromEbN0_(double ebn0_lin) const;
    double perFromBer_(double ber, int bits) const;
    double computePER_(double Prx_W, hdr_MPhy* ph, int bits);

    // Bindables
    double TxPower_ = 0.0;      // W
    double NF_dB_ = 40.0;       // dB
    double AcquisitionThreshold_dB_ = 10.0;   // SNR gate
    int    use_auto_rx_power_gate_  = 1;      // if 1, Pthr = N + SNRreq
    double rxPowerThreshold_dBm_    = -140.0; // fallback absolute power gate
    double Rb_ = 1000.0;        // bps
    double B_  = 1000.0;        // Hz (mask width)
    double Beff_Hz_ = 10000.0;  // Hz 
    double Tnoise_K_ = 293.0;   // K
    int    use_resonance_ = 1;
    double f0_ = 1.0e6;         // Hz
    double Q_  = 50.0;
    int    debug_ = 0;
    double NoiseMargin_dB_ = 0.0;

private:
    static int mi_modid;
};

#endif /* UWMI_PHY_H */