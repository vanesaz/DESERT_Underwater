# ==========================================================
# Default parameters for Module/UW/MI/PHY  (coil-aware version)
# ==========================================================

# === Transmit settings ===
Module/UW/MI/PHY set TxPower_            0.1        ;# W (0 dBW)

# === Environment / noise ===
Module/UW/MI/PHY set T_                  300        ;# Temperature [K]
Module/UW/MI/PHY set NF_dB_              3.0        ;# Receiver noise figure [dB]
Module/UW/MI/PHY set rxPowerThreshold_   -200.0     ;# [dBW] minimum detectable power

# === Data-rate & fallback bandwidth ===
Module/UW/MI/PHY set Rb_                 27000.0    ;# Bit rate [bps]
Module/UW/MI/PHY set B_                  10000.0    ;# Fallback BW if no mask/resonance [Hz]

# === Resonance model ===
Module/UW/MI/PHY set use_resonance_      1          ;# 1 = enable resonance limit
Module/UW/MI/PHY set f0_                 1e6        ;# Coil tuned frequency [Hz]
Module/UW/MI/PHY set Q_                  50.0       ;# Coil quality factor (f0/Q = 20 kHz BW)

# === Debug ===
Module/UW/MI/PHY set debug_              0
