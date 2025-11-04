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
    UwElectroMagneticChannel* channel_;      
    UwMiCouplingPropagation* propagation_;   
    Antenna* antenna_;
    UwMiPhy();
    virtual ~UwMiPhy() {}

    double getTxDuration(Packet* p) override;
    int    getModulationType(Packet* p) override;
    double getNoisePower(Packet* p) override;
    int command(int argc, const char* const* argv) override;
    void handle(Event* e) override;



protected:
    void   startTx(Packet* p) override;
    void   endTx(Packet* p) override;
    void   sendDown(Packet* p);
    void   startRx(Packet* p) override;
    void   endRx(Packet* p) override;

    double getRxPower(Packet *p) override;
    double effectiveBandwidthHz_(hdr_MPhy *ph) const;
    double thermalNoise_W_(double Beff_Hz) const;
    double berBpskFromEbN0_(double ebn0_lin) const;
    double perFromBer_(double ber, int bits) const;
    double computePER_(double Prx_W, hdr_MPhy *ph, int bits);
    double computeNoisePower_();

    // bindables
    double TxPower_;
    double NF_dB_;
    double rxPowerThreshold_;
    double Rb_;
    double B_;
    double Beff_Hz_;
    double Tnoise_K_;
    int    use_resonance_;
    double f0_;
    double Q_;
    int    debug_;
    double NoiseMargin_dB_;    // Optional margin for PER tuning [dB]

private:
    Packet* PktTx_;
    Packet* PktRx;
    bool    txPending;
    static int mi_modid;
    Event   tx_end_ev_; 
};

#endif /* UWMI_PHY_H */
