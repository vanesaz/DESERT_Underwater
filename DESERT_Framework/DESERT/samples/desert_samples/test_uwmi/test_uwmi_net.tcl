# ===========================================
# UwMI PHY + Propagation minimal integration
# ===========================================

# -------- Load DESERT core libraries --------
load libMiracle.so
load libMiracleBasicMovement.so
load libmphy.so
load libUwmStd.so

load libuwphy_clmsgs.so
load libuwstats_utilities.so
load libuwinterference.so
load libuwsmposition.so
load libuwphysical.so
load libuwphysicalnoise.so
load libuwgainfromdb.so

# -------- Networking stack --------
load libuwcsmaaloha.so
load libuwip.so
load libuwstaticrouting.so
load libuwmll.so
load libuwudp.so
load libuwcbr.so
load libuwem_channel.so
load libuwem_antenna.so

# -------- MI Modules --------
load libuwmi_propagation.so
load libuwmi_coupling_propagation.so
load libuwmi_phy.so

# -------- Initialize simulator --------
set ns [new Simulator]
$ns use-Miracle

puts "\n==== Starting UwMI PHY Simulation ===="

#############################
# Tracing configuration
#############################
set opt(trace_files) 0

if {$opt(trace_files)} {
    set opt(tracefilename) "./uwmi_results.tr"
    set opt(tracefile) [open $opt(tracefilename) w]
    set opt(cltracefilename) "./uwmi_results.cltr"
    set opt(cltracefile) [open $opt(cltracefilename) w]
} else {
    set opt(tracefilename) "/dev/null"
    set opt(tracefile) [open $opt(tracefilename) w]
    set opt(cltracefilename) "/dev/null"
    set opt(cltracefile) [open $opt(cltracefilename) w]
}

# ===============================
# Basic Simulation Configuration
# ===============================
set opt(start)    0
set opt(stop)     30
set opt(distance) 3
set opt(txpower) 0.0001
set opt(period)   1.2
set opt(pktsize)  128

set opt(seed) 12345

# Allow overrides from command line (-distance, -sigma, -period, -stop)
set opt(sigma) 4.0     ;# 4 S/m = saltwater by default
for {set i 0} {$i < $argc} {incr i} {
    set flag [lindex $argv $i]
    set val  [lindex $argv [expr {$i+1}]]
    switch -- $flag {
        "-distance" { set opt(distance) $val }
        "-sigma"    { set opt(sigma)    $val }
        "-period"   { set opt(period)   $val }
        "-stop"     { set opt(stop)     $val }
        "-seed"     { set opt(seed)     $val }
    }
}

# set ns RNG
if {[info commands ns-random] ne ""} {
    ns-random $opt(seed)
}

# --- Debug: show parsed CLI arguments ---
puts "ARGS: distance=$opt(distance), sigma=$opt(sigma), period=$opt(period), stop=$opt(stop)"

set ::stdout [open "uwmi_stdout_log.txt" w]
puts $::stdout "=== UwMI PHY debug log ==="
flush $::stdout

set ::runlog [open "uwmi_runlog.txt" w]
flush $::runlog
set ::phylog [open "uwmi_phylog.txt" w]
flush $::phylog

# ===============================
# Spectral mask (required by PHY)
# ===============================
set mask [new MSpectralMask/Rect]
$mask setFreq 200000    ;# 200 kHz
$mask setBandwidth 5000 ;# 5 kHz

# ===============================
# Create PHYs 
# ===============================
set miPhy1 [new Module/UW/MI/PHY/Custom]
set miPhy2 [new Module/UW/MI/PHY/Custom]
$miPhy1 setSpectralMask $mask
$miPhy2 setSpectralMask $mask

# Enable detailed debug for verification
$miPhy1 set mi_debug_ 1
$miPhy2 set mi_debug_ 1

# Antennas
set ant1 [new Module/UW/ElectroMagnetic/Antenna]
set ant2 [new Module/UW/ElectroMagnetic/Antenna]
$ant1 setGain 0
$ant2 setGain 0
$miPhy1 setAntenna $ant1
$miPhy2 setAntenna $ant2

# ===============================
# PHY parameters
# ===============================
$miPhy1 set TxPower_ $opt(txpower)
$miPhy2 set TxPower_ $opt(txpower)
$miPhy1 set Rb_ 1000
$miPhy2 set Rb_ 1000
$miPhy1 set B_ 5000
$miPhy2 set B_ 5000
$miPhy1 set rxPowerThreshold_ -120
$miPhy2 set rxPowerThreshold_ -120
$miPhy1 set f0_ 200000
$miPhy2 set f0_ 200000
$miPhy1 set Q_ 50
$miPhy2 set Q_ 50
$miPhy1 set NF_dB_ 80.0
$miPhy2 set NF_dB_ 80.0
$miPhy1 set Tnoise_K_ 290
$miPhy2 set Tnoise_K_ 290

# --- Ensure base MPhy Pt_ (in Watts) is positive, for channel compatibility ---
set txW [expr {pow(10.0, ($opt(txpower) - 30.0) / 10.0)}]
$miPhy1 set Pt_ $txW
$miPhy2 set Pt_ $txW
puts "DEBUG: forced Pt_ = $txW W in both PHYs"

# ===============================
# MAC + Network + App Layers
# ===============================
set mac1 [new Module/UW/CSMA_ALOHA]
set mac2 [new Module/UW/CSMA_ALOHA]
$mac1 set debug_ 1
$mac2 set debug_ 1

set app1 [new Module/UW/CBR]
set app2 [new Module/UW/CBR]
$app1 set period_ $opt(period)
$app2 set period_ $opt(period)
$app1 set packetSize_ $opt(pktsize)
$app2 set packetSize_ $opt(pktsize)
$app1 set debug_ 1
$app2 set debug_ 1

set udp1 [new Module/UW/UDP]
set ip1  [new Module/UW/IP]
set mll1 [new Module/UW/MLL]
set rt1  [new Module/UW/StaticRouting]

set udp2 [new Module/UW/UDP]
set ip2  [new Module/UW/IP]
set mll2 [new Module/UW/MLL]
set rt2  [new Module/UW/StaticRouting]

# ===============================
# Nodes
# ===============================
set node1 [$ns create-M_Node $opt(tracefile) $opt(cltracefile)]
set node2 [$ns create-M_Node $opt(tracefile) $opt(cltracefile)]

$node1 addModule 7 $app1 0 "APP"
$node1 addModule 6 $udp1 0 "UDP"
$node1 addModule 5 $ip1  0 "IP"
$node1 addModule 4 $rt1  0 "RT"
$node1 addModule 3 $mll1 0 "MLL"
$node1 addModule 2 $mac1 0 "MAC"
$node1 addModule 1 $miPhy1 0 "PHY"

$node2 addModule 7 $app2 0 "APP"
$node2 addModule 6 $udp2 0 "UDP"
$node2 addModule 5 $ip2  0 "IP"
$node2 addModule 4 $rt2  0 "RT"
$node2 addModule 3 $mll2 0 "MLL"
$node2 addModule 2 $mac2 0 "MAC"
$node2 addModule 1 $miPhy2 0 "PHY"

# ===============================
# Channel
# ===============================
set channel [new Module/UW/ElectroMagnetic/Channel]

$node1 addToChannel $channel $miPhy1 0
$node2 addToChannel $channel $miPhy2 0

# Connections
$node1 setConnection $app1 $udp1 0
$node1 setConnection $udp1 $ip1 0
$node1 setConnection $ip1  $rt1 0
$node1 setConnection $rt1  $mll1 0
$node1 setConnection $mll1 $mac1 0
$node1 setConnection $mac1 $miPhy1 0

$miPhy1 setChannel $channel

$node2 setConnection $app2 $udp2 0
$node2 setConnection $udp2 $ip2 0
$node2 setConnection $ip2  $rt2 0
$node2 setConnection $rt2  $mll2 0
$node2 setConnection $mll2 $mac2 0
$node2 setConnection $mac2 $miPhy2 0

$miPhy2 setChannel $channel

# ===============================
# Addressing & ARP (needed for CBR->UDP->IP)
# ===============================
$ip1 addr 1
$ip2 addr 2
$mac1 set MAC_addr_ 1
$mac2 set MAC_addr_ 2
$mll1 addentry [$ip2 addr] [$mac2 addr]
$mll2 addentry [$ip1 addr] [$mac1 addr]

# Static routing table
$rt1 addRoute [$ip2 addr] [$ip2 addr]
$rt2 addRoute [$ip1 addr] [$ip1 addr]

# UDP port binding (ONLY ONCE)
set port1 [$udp1 assignPort $app1]
set port2 [$udp2 assignPort $app2]
$app1 set destAddr_ [$ip2 addr]
$app1 set destPort_ $port2
$app2 set destAddr_ [$ip1 addr]
$app2 set destPort_ $port1

# ===============================
# Node positions (set BEFORE propagation)
# ===============================
set position1 [new "Position/BM"]
$node1 addPosition $position1
set position2 [new "Position/BM"]
$node2 addPosition $position2

$position1 setX_ 0
$position1 setY_ 0
$position1 setZ_ -5
$position2 setX_ $opt(distance)
$position2 setY_ 0
$position2 setZ_ -5

puts "DEBUG: Node1 X=[ $position1 getX_ ], Node2 X=[ $position2 getX_ ], distance=$opt(distance)"

# ===============================
# Channel and Propagation (correct order)
# ===============================
set miProp  [new Module/UW/MI/CouplingPropagation]
$miProp set Nt_ 200
$miProp set Nr_ 200
$miProp set at_ 0.2
$miProp set ar_ 0.2
$miProp set Rt_ 1.0
$miProp set Rr_ 1.0
$miProp set kappa_ 1.0
$miProp set f_ 200000 
$miProp set use_cond_loss_ 1    ;# <-- set once here, do NOT override later
$miProp set sigma_ $opt(sigma)
$miProp set debug_ 1

# Attach positions now that they exist
$miProp addPosition $position1
$miProp addPosition $position2

# Bind propagation to PHYs (only now)
$miPhy1 setPropagation $miProp
$miPhy2 setPropagation $miProp

puts "DEBUG: Propagation attached with distance=$opt(distance), sigma=$opt(sigma)"

puts "\n---- Link budget estimate ----"
puts "Tx Power: [$miPhy1 set TxPower_] dBm"
puts "Noise Figure: [$miPhy1 set NF_dB_] dB"
puts "Bandwidth: [$miPhy1 set B_] Hz"
puts "Bitrate: [$miPhy1 set Rb_] bps"
puts "(Propagation getGain() will be computed dynamically during packet reception)"
puts "----------------------------------\n"


puts "PHY1: TxPower=[ $miPhy1 set TxPower_ ] dBm, Rb=[ $miPhy1 set Rb_ ] bps, B=[ $miPhy1 set B_ ] Hz, f0=[ $miPhy1 set f0_ ] Hz"
puts "Mask: f=[ $mask getFreq ] Hz, BW=[ $mask getBandwidth ] Hz"
puts "PROP: f=[ $miProp set f_ ] Hz, Nt=[ $miProp set Nt_ ], Nr=[ $miProp set Nr_ ]"


# ================================================================
#   UwMI One-Way Link Validation Test
#   (Thesis: Magnetic Induction PHY Characterization)
#   Node1 → Node2 unidirectional transmission
# ================================================================

# -------------------------------
# Application configuration
# -------------------------------
$app1 set node_ $node1          ;# Transmitter
$app2 set node_ $node2          ;# Receiver
$app1 set packetSize_ $opt(pktsize)
$app2 set packetSize_ $opt(pktsize)
$app1 set period_ $opt(period)
$app2 set period_ $opt(period)
$app1 set PoissonTraffic_ 0
$app2 set PoissonTraffic_ 0
$app1 set debug_ 1
$app2 set debug_ 1

# -------------------------------
# One-way traffic setup (Node1→Node2)
# -------------------------------
$ns at 5.0 "$app1 start"
$ns at 5.1 "puts \"Running one-way MI link test: Node1 → Node2\""
$ns at 5.2 "$app1 sendPkt" ;# kick off first transmission

# Node2 acts purely as passive receiver (no start)
# $app2 is not started (no reverse traffic)

# -------------------------------
# Live logging configuration
# -------------------------------
set ::runlog [open "uwmi_runlog.txt" w]
set ::phylog [open "uwmi_phylog.txt" w]

proc log_counters {} {
    global ns app1 app2 runlog miPhy1 miPhy2 miProp phylog
    set t [$ns now]
    set s [$app1 getsentpkts]
    set r [$app2 getrecvpkts]

    puts $runlog "$t,sent=$s,rcv=$r"
    puts $phylog "\n==== Tcl tick t=$t ===="
    puts $phylog "  sent=$s, rcv=$r"

    # Re-enable debug every second (ensures C++ printf remains active)
    $miPhy1 set mi_debug_ 1
    $miPhy2 set mi_debug_ 1
    $miProp set mi_debug_ 1

    flush $phylog
    flush $runlog

    # Schedule next tick (1 s)
    $ns at [expr {$t + 1.0}] "log_counters"
}
$ns at 5.2 "log_counters"

# -------------------------------
# PHY–MAC binding and initialization
# -------------------------------
$mac1 set phy_ $miPhy1
$mac2 set phy_ $miPhy2
$miPhy1 set Mac_ $mac1
$miPhy2 set Mac_ $mac2
$mac1 initialize
$mac2 initialize

# -------------------------------
# Simulation runtime control
# -------------------------------
puts "Running UwMI simulation with distance = $opt(distance) m ..."
puts "Forcing PHY debug manually..."
$miPhy1 set mi_debug_ 1
$miPhy2 set mi_debug_ 1
puts "PHY1 debug = [$miPhy1 set mi_debug_]"
puts "PHY2 debug = [$miPhy2 set mi_debug_]"

puts "---- Initialization complete, starting one-way traffic ----"
puts "App1 (TX) -> Addr [$app1 set destAddr_] Port [$app1 set destPort_]"
puts "App2 (RX) -> Addr [$app2 set destAddr_] Port [$app2 set destPort_]"

puts "Loaded PHY library path: [info sharedlib]"

# ================================================================
#   Results collection and end procedure
# ================================================================
proc finish {} {
    global ns opt app1 app2

    # Gather final results
    set sent [$app1 getsentpkts]
    set rcv  [$app2 getrecvpkts]
    set per  [expr {$sent > 0 ? (1.0 - double($rcv)/double($sent)) : 1.0}]

    puts "\n--------------------------------------------------------"
    puts "UwMI One-Way Simulation Complete"
    puts "Distance (m): $opt(distance)"
    puts "Sent packets     : $sent"
    puts "Received packets : $rcv"
    puts "Packet Error Rate: $per"
    puts "--------------------------------------------------------"

    # Save summary to files
    set resultFile "uwmi_results_summary_${opt(distance)}m.csv"
    set fd [open $resultFile a]
    puts $fd "distance=$opt(distance),sent=$sent,rcv=$rcv,per=$per,sigma=$opt(sigma),period=$opt(period),stop=$opt(stop)"
    close $fd

    set master [open "uwmi_results_summary_all.csv" a]
    puts $master "$opt(distance),$sent,$rcv,$per,$opt(sigma),$opt(period),$opt(stop),$opt(seed)"
    close $master

    # Clean shutdown of logs
    flush $::runlog
    flush $::phylog
    close $::runlog
    close $::phylog

    $ns flush-trace
    close $opt(tracefile)
    close $opt(cltracefile)
    $ns halt
}

# Schedule end
$ns at $opt(stop) "$app1 stop"
$ns at [expr {$opt(stop) + 0.5}] "finish"
$ns at [expr {$opt(stop) + 5.0}] "$ns halt"

# -------------------------------
# Start simulation
# -------------------------------
$ns run
