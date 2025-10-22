# ===========================================
# UwMI PHY + Propagation minimal integration
# ===========================================

# Load DESERT core libraries
load libMiracle.so
load libMiracleBasicMovement.so
load libmphy.so
load libuwcsmaaloha.so
load libuwip.so
load libuwstaticrouting.so
load libuwmll.so
load libuwudp.so
load libuwcbr.so
load libuwaloha.so
load libuwem_antenna.so

# ====== EM + MI modules ======
load libuwem_channel.so         ;# Needed for the base EM/Channel
load libuwmi_propagation.so
load libuwmi_phy.so

# Initialize simulator
set ns [new Simulator]
$ns use-Miracle


# ===============================
# Tracing configuration
# ===============================
set opt(tracefilename) "./uwmi_test.tr"
set tracefd [open $opt(tracefilename) w]
$ns trace-all $tracefd




# ===============================
# Basic Simulation Configuration
# ===============================
set opt(start) 0
set opt(stop) 20
set opt(distance) 3
set opt(temp) 20
set opt(sal) 35
set opt(txpower) 10
set opt(period) 1.0
set opt(pktsize) 128

# ===============================
# Channel and Propagation
# ===============================
set channel [new Module/UW/ElectroMagnetic/Channel] ;# Reuse EM channel for scheduling
set miProp [new Module/UW/MI/Propagation]
$miProp setT $opt(temp)
$miProp setS $opt(sal)
$miProp set debug_ 1

# ===============================
# Create PHYs
# ===============================
set miPhy1 [new Module/UW/MI/PHY]
set miPhy2 [new Module/UW/MI/PHY]
$miPhy1 set debug_ 1
$miPhy2 set debug_ 1
$miPhy1 setPropagation $miProp
$miPhy2 setPropagation $miProp
# ===============================
# Spectral mask (required by BPSK PHY)
# ===============================
set mask [new MSpectralMask/Rect]
$mask setFreq 1000000      ;# 1 MHz
$mask setBandwidth 10000   ;# 10 kHz

$miPhy1 setSpectralMask $mask
$miPhy2 setSpectralMask $mask


# --- Antennas (required by MPhy_Bpsk path) ---
set ant1 [new Module/UW/ElectroMagnetic/Antenna]
set ant2 [new Module/UW/ElectroMagnetic/Antenna]
$ant1 setGain 0
$ant2 setGain 0
$miPhy1 setAntenna $ant1
$miPhy2 setAntenna $ant2


# ===============================
# Create MAC and APP
# ===============================
set mac1 [new Module/UW/ALOHA]
set mac2 [new Module/UW/ALOHA]
set app1 [new Module/UW/CBR]
set app2 [new Module/UW/CBR]

$app1 set period_ $opt(period)
$app1 set packetSize_ $opt(pktsize)
$app2 set period_ $opt(period)
$app2 set packetSize_ $opt(pktsize)

# ===============================
# Enable debug output
# ===============================
$miPhy1 set debug_ 1
$miPhy2 set debug_ 1
$mac1 set debug_ 1
$mac2 set debug_ 1

# ===============================
# Module-level tracing (fallback)
# ===============================
set appTrace1 [open "./uwmi_app1.tr" w]
set appTrace2 [open "./uwmi_app2.tr" w]
set macTrace1 [open "./uwmi_mac1.tr" w]
set macTrace2 [open "./uwmi_mac2.tr" w]

# Redirect stdout to multiple trace files using custom procs
proc logApp1 {msg} { global appTrace1; puts $appTrace1 $msg; flush $appTrace1 }
proc logApp2 {msg} { global appTrace2; puts $appTrace2 $msg; flush $appTrace2 }
proc logMac1 {msg} { global macTrace1; puts $macTrace1 $msg; flush $macTrace1 }
proc logMac2 {msg} { global macTrace2; puts $macTrace2 $msg; flush $macTrace2 }

# Example: manually log key simulation events
puts "Tracing enabled"
logApp1 "CBR1 started"
logApp2 "CBR2 started"


# --- Create protocol stack modules ---
set udp1 [new Module/UW/UDP]
set ip1  [new Module/UW/IP]
set mll1 [new Module/UW/MLL]

set udp2 [new Module/UW/UDP]
set ip2  [new Module/UW/IP]
set mll2 [new Module/UW/MLL]
# --- Create nodes ---
set node1 [$ns create-M_Node]
set node2 [$ns create-M_Node]

# --- Add modules to nodes (layer ≥1, higher = upper layers) ---
$node1 addModule 6 $app1 0 "APP"
$node1 addModule 5 $udp1 0 "UDP"
$node1 addModule 4 $ip1  0 "IP"
$node1 addModule 3 $mll1 0 "MLL"
$node1 addModule 2 $mac1 0 "MAC"
$node1 addModule 1 $miPhy1 0 "PHY"

$node2 addModule 6 $app2 0 "APP"
$node2 addModule 5 $udp2 0 "UDP"
$node2 addModule 4 $ip2  0 "IP"
$node2 addModule 3 $mll2 0 "MLL"
$node2 addModule 2 $mac2 0 "MAC"
$node2 addModule 1 $miPhy2 0 "PHY"

# --- Wire the stack ---
$node1 setConnection $app1 $udp1 0
$node1 setConnection $udp1 $ip1  0
$node1 setConnection $ip1  $mll1 0
$node1 setConnection $mll1 $mac1 0
$node1 setConnection $mac1 $miPhy1 0
$node1 addToChannel  $channel $miPhy1 0

$node2 setConnection $app2 $udp2 0
$node2 setConnection $udp2 $ip2  0
$node2 setConnection $ip2  $mll2 0
$node2 setConnection $mll2 $mac2 0
$node2 setConnection $mac2 $miPhy2 0
$node2 addToChannel  $channel $miPhy2 0

# --- Addresses + ARP ---
$ip1 addr 1
$ip2 addr 2
$mac1 set MAC_addr_ 1
$mac2 set MAC_addr_ 2
$mll1 addentry [$ip2 addr] [$mac2 addr]
$mll2 addentry [$ip1 addr] [$mac1 addr]

# --- UDP ports + CBR destinations ---
set port1 [$udp1 assignPort $app1]
set port2 [$udp2 assignPort $app2]
$app1 set destAddr_ [$ip2 addr]
$app1 set destPort_ $port2
$app2 set destAddr_ [$ip1 addr]
$app2 set destPort_ $port1

# --- Initialize MACs (ALOHA needs this) ---
$mac1 initialize
$mac2 initialize


# --- Add positions to nodes ---
set position1 [new "Position/BM"]
$node1 addPosition $position1
set posdb1 [new "PlugIn/PositionDB"]
$node1 addPlugin $posdb1 20 "PDB"

set position2 [new "Position/BM"]
$node2 addPosition $position2
set posdb2 [new "PlugIn/PositionDB"]
$node2 addPlugin $posdb2 20 "PDB"

$posdb1 addpos [$ip1 addr] $position1
$posdb2 addpos [$ip2 addr] $position2

# ===============================
# Positions
# ===============================
$position1 setX_ 0
$position1 setY_ 0
$position1 setZ_ -5

$position2 setX_ $opt(distance)
$position2 setY_ 0
$position2 setZ_ -5



# ===============================
# Safe logging helpers
# ===============================
proc logAppEvent {trace msg} {
    global ns
    puts $trace "[$ns now] $msg"
    flush $trace
}

# ===============================
# Traffic setup with runtime timestamps
# ===============================
$ns at 1.0 "logAppEvent \$appTrace1 {Node1 starting CBR}; $app1 start"
$ns at 1.0 "logAppEvent \$appTrace2 {Node2 idle}"
$ns at 10.0 "logAppEvent \$appTrace1 {mid-simulation checkpoint}"
$ns at $opt(stop) "logAppEvent \$appTrace1 {Node1 stopping CBR}; $app1 stop"
$ns at [expr $opt(stop)+1] "finish"


proc finish {} {
    global ns tracefd appTrace1 appTrace2 macTrace1 macTrace2
    puts "UwMI test complete!"
    flush $tracefd; close $tracefd
    flush $appTrace1; close $appTrace1
    flush $appTrace2; close $appTrace2
    flush $macTrace1; close $macTrace1
    flush $macTrace2; close $macTrace2
    exit 0
}

puts "Running UwMI simulation..."
$ns run
