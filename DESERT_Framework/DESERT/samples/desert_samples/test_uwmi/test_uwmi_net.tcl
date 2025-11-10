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
    set opt(cltracefilename) "./uwmi_results.cltr"
} else {
    set opt(tracefilename) "/dev/null"
    set opt(cltracefilename) "/dev/null"
}
set opt(tracefile)     [open $opt(tracefilename) w]
set opt(cltracefile)   [open $opt(cltracefilename) w]

# ===============================
# Basic Simulation Configuration
# ===============================
set opt(start)    0
set opt(stop)     30
set opt(distance) 3
set opt(period)   1.2
set opt(pktsize)  128

set opt(seed) 12345

# ---- New radio defaults (override via CLI) ----
set opt(f_khz)      200
set opt(B)          5000
set opt(Rb)         1000
set opt(Q)          50
set opt(NF_dB)      18.0
set opt(Tnoise_K)   290
set opt(txpwr_dbm)  0      ;# 0 dBm default

# ---- Hardware defaults ----
set opt(Nt)     40
set opt(Nr)     40
set opt(at)     0.12
set opt(ar)     0.12
set opt(Rt)     4.0
set opt(Rr)     4.0
set opt(kappa)  0.7

# --- New multi-coil params ---
set opt(Nt_coils) 1
set opt(Nr_coils) 1
set opt(st) 0.0
set opt(sr) 0.0
set opt(auto_scale_R) 1 

# --- Geometry inputs (same for both modes) ---
# Accept: -dx (alias: -distance), -z1, -z2
# Defaults depend on -uw2aw
set opt(dx) ""
set opt(z1) ""
set opt(z2) ""


# Allow overrides from command line ( -uw2aw, -distance, -sigma, -period, -stop)
set opt(uw2aw) 0   ;# 0 = UW->UW (both underwater), 1 = UW->AW (Rx above water)
set opt(sigma) 4.0     ;# 4 S/m = saltwater by default
for {set i 0} {$i < $argc} {incr i} {
    set flag [lindex $argv $i]
    set val  [lindex $argv [expr {$i+1}]]
    switch -- $flag {
        "-uw2aw"    { set opt(uw2aw) $val }
        "-dx"       { set opt(dx) $val }
        "-z1"       { set opt(z1) $val }
        "-z2"       { set opt(z2) $val }
        "-distance" { set opt(dx) $val }   ;# alias
        "-sigma"    { set opt(sigma)    $val }
        "-period"   { set opt(period)   $val }
        "-stop"     { set opt(stop)     $val }
        "-seed"     { set opt(seed)     $val }
        
        "-f_khz"     { set opt(f_khz)     $val }
        "-B"         { set opt(B)         $val }
        "-Rb"        { set opt(Rb)        $val }
        "-Q"         { set opt(Q)         $val }
        "-NF_dB"     { set opt(NF_dB)     $val }
        "-Tnoise_K"  { set opt(Tnoise_K)  $val }
        "-txpwr_dbm" { set opt(txpwr_dbm) $val }

        "-Nt_coils" { set opt(Nt_coils) $val }
        "-Nr_coils" { set opt(Nr_coils) $val }
        "-st"       { set opt(st) $val }
        "-sr"       { set opt(sr) $val }
        "-auto_scale_R" { set opt(auto_scale_R) $val }

        "-Nt" { set opt(Nt) $val } "-Nr" { set opt(Nr) $val }
        "-at" { set opt(at) $val } "-ar" { set opt(ar) $val }
        "-Rt" { set opt(Rt) $val } "-Rr" { set opt(Rr) $val }
        "-kappa" { set opt(kappa) $val }

    }
}
puts "ARGS: uw2aw=$opt(uw2aw), dx=$opt(dx), z1=$opt(z1), z2=$opt(z2), sigma=$opt(sigma)"

# set ns RNG
if {[info commands ns-random] ne ""} {
    ns-random $opt(seed)
}

# ===============================
# Logs
# ===============================
set ::runlog [open "uwmi_runlog.txt" w]
set ::phylog [open "uwmi_phylog.txt" w]
flush $::runlog
flush $::phylog

# ===============================
# Spectral mask (required by PHY)
# ===============================
set mask [new MSpectralMask/Rect]
$mask setFreq [expr {$opt(f_khz) * 1000}]
$mask setBandwidth $opt(B)

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

#$miPhy1 set TxPower_     $opt(txpwr_dbm)
#$miPhy2 set TxPower_     $opt(txpwr_dbm)
$miPhy1 set Rb_          $opt(Rb)
$miPhy2 set Rb_          $opt(Rb)
$miPhy1 set B_           $opt(B)
$miPhy2 set B_           $opt(B)
$miPhy1 set f0_          [expr {$opt(f_khz) * 1000}]
$miPhy2 set f0_          [expr {$opt(f_khz) * 1000}]
$miPhy1 set Q_           $opt(Q)
$miPhy2 set Q_           $opt(Q)
$miPhy1 set NF_dB_       $opt(NF_dB)
$miPhy2 set NF_dB_       $opt(NF_dB)
$miPhy1 set Tnoise_K_    $opt(Tnoise_K)
$miPhy2 set Tnoise_K_    $opt(Tnoise_K)

$miPhy1 set AcquisitionThreshold_dB_ 10
$miPhy2 set AcquisitionThreshold_dB_ 10
$miPhy1 set use_auto_rx_power_gate_ 1
$miPhy2 set use_auto_rx_power_gate_ 1
# optional explicit fallback, not needed when auto is 1:
# $miPhy1 set rxPowerThreshold_dBm_ -120
# $miPhy2 set rxPowerThreshold_dBm_ -120

# Compute W from dBm
set txW [expr {pow(10.0, ($opt(txpwr_dbm) - 30.0) / 10.0)}]
puts [format "Tx Power: %.3f dBm (%.6g W)" $opt(txpwr_dbm) $txW]

# Set base MPhy variable in W (this is what MPhy::getTxPower returns)
$miPhy1 set TxPower_ $txW
$miPhy2 set TxPower_ $txW

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
$miPhy1 setChannel $channel
$miPhy2 setChannel $channel

# Connections
$node1 setConnection $app1 $udp1 0
$node1 setConnection $udp1 $ip1 0
$node1 setConnection $ip1  $rt1 0
$node1 setConnection $rt1  $mll1 0
$node1 setConnection $mll1 $mac1 0
$node1 setConnection $mac1 $miPhy1 0

$node2 setConnection $app2 $udp2 0
$node2 setConnection $udp2 $ip2 0
$node2 setConnection $ip2  $rt2 0
$node2 setConnection $rt2  $mll2 0
$node2 setConnection $mll2 $mac2 0
$node2 setConnection $mac2 $miPhy2 0


# ===============================
# Addressing & ARP
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
# Node positions (BEFORE propagation)
# ===============================
set position1 [new "Position/BM"]
$node1 addPosition $position1
set position2 [new "Position/BM"]
$node2 addPosition $position2

# Resolve geometry defaults based on uw2aw
# If user didn't pass a value, apply the per-mode defaults
set dx_final [expr {$opt(dx) eq "" ? 3.0 : double($opt(dx))}]

if {$opt(uw2aw) == 1} {
    # UW→AW defaults: z1=-5, z2=+1
    set z1_default -2.0
    set z2_default  1.0
} else {
    # UW→UW defaults: z1=-5, z2=-5
    set z1_default -5.0
    set z2_default -5.0
}
set z1_final [expr {$opt(z1) eq "" ? $z1_default : double($opt(z1))}]
set z2_final [expr {$opt(z2) eq "" ? $z2_default : double($opt(z2))}]

set opt(z1_used) $z1_final
set opt(z2_used) $z2_final

# Place nodes: Tx at origin, Rx at (dx, 0, z2_final)
$position1 setX_ 0.0
$position1 setY_ 0.0
$position1 setZ_ $z1_final

$position2 setX_ $dx_final
$position2 setY_ 0.0
$position2 setZ_ $z2_final

# Derived geometry (for logs/CSV)
set x1 [$position1 getX_]; set y1 [$position1 getY_]; set z1 [$position1 getZ_]
set x2 [$position2 getX_]; set y2 [$position2 getY_]; set z2 [$position2 getZ_]

set opt(dx) [expr {$x2 - $x1}]
set opt(dy) [expr {$y2 - $y1}]
set opt(dz) [expr {$z2 - $z1}]
set opt(distance_actual) [expr {sqrt($opt(dx)*$opt(dx) + $opt(dy)*$opt(dy) + $opt(dz)*$opt(dz))}]

# Segment split only when uw2aw==1 (two-layer propagation)
set opt(Lw_used) $opt(distance_actual)
set opt(La_used) 0.0
if {$opt(uw2aw) == 1 && $opt(dz) != 0} {
    # Parametric point where z(t) crosses 0
    set t0 [expr {(-$z1) / double($opt(dz))}]
    if {$t0 > 0.0 && $t0 < 1.0} {
        set opt(Lw_used) [expr {$opt(distance_actual) * $t0}]
        set opt(La_used) [expr {$opt(distance_actual) * (1.0 - $t0)}]
    }
}

# For user-facing prints and CSV "distance", report D_actual
set opt(distance) $opt(distance_actual)

puts [format "DEBUG: Node1=(%.3f,%.3f,%.3f)  Node2=(%.3f,%.3f,%.3f)  dx=%.3f dz=%.3f  D_actual=%.3f  mode=%s" \
      $x1 $y1 $z1 $x2 $y2 $z2 $opt(dx) $opt(dz) $opt(distance_actual) \
      [expr {$opt(uw2aw) ? "UW→AW(two-layer)" : "UW→UW(single-medium)"}]]

puts [format "GEOM: dx=%.3f dy=%.3f dz=%.3f  D_actual=%.3f  (Lw=%.3f, La=%.3f)" \
      $opt(dx) $opt(dy) $opt(dz) $opt(distance_actual) $opt(Lw_used) $opt(La_used)]

puts [format "DEPTHS: z1_used=%.3f  z2_used=%.3f" $opt(z1_used) $opt(z2_used)]

# ===============================
# Propagation
# ===============================
set miProp  [new Module/UW/MI/CouplingPropagation]
$miProp set Nt_coils_ $opt(Nt_coils)
$miProp set Nr_coils_ $opt(Nr_coils)
$miProp set st_       $opt(st)
$miProp set sr_       $opt(sr)
$miProp set auto_scale_R_ $opt(auto_scale_R)
$miProp set Nt_ $opt(Nt)
$miProp set Nr_ $opt(Nr)
$miProp set at_ $opt(at)
$miProp set ar_ $opt(ar)
$miProp set Rt_ $opt(Rt)
$miProp set Rr_ $opt(Rr)
$miProp set kappa_ $opt(kappa)
$miProp set use_cond_loss_ 1    ;# <-- set once here, do NOT override later
$miProp set sigma_ $opt(sigma)
$miProp set debug_ 1

# enable the UW→AW splitter in the propagation
$miProp set use_two_layer_ $opt(uw2aw)

$miProp setChannel $channel

# Attach positions now that they exist
$miProp addPosition $position1
$miProp addPosition $position2

# Bind propagation to PHYs
$miPhy1 setPropagation $miProp
$miPhy2 setPropagation $miProp

puts "DEBUG: Propagation attached with distance=$opt(distance), sigma=$opt(sigma)"

puts "\n---- Link budget estimate ----"
set txW [$miPhy1 set TxPower_]
set txdBm [expr {10*log10($txW*1000.0)}]
puts [format "Tx Power: %.3f dBm (%.6g W)" $txdBm $txW]
puts "Noise Figure: [$miPhy1 set NF_dB_] dB"
puts "Bandwidth: [$miPhy1 set B_] Hz"
puts "Bitrate: [$miPhy1 set Rb_] bps"
puts "----------------------------------\n"

puts "PHY1: TxPower=[format %.6g $txW] W (~[format %.1f $txdBm] dBm), \
Rb=[$miPhy1 set Rb_] bps, B=[$miPhy1 set B_] Hz, f0=[$miPhy1 set f0_] Hz"
puts "Mask: f=[$mask getFreq] Hz, BW=[$mask getBandwidth] Hz"
puts "PROP:  Nt=[$miProp set Nt_], Nr=[$miProp set Nr_]"

# ================================================================
#   One-Way Link
# ================================================================

$app1 set node_ $node1          ;# Transmitter
$app2 set node_ $node2          ;# Receiver

# Start RX app too (safe, no reverse traffic)
#$ns at 4.9 "$app2 start"
$ns at 5.0 "$app1 start"
$ns at 5.1 "puts \"Running one-way MI link test: Node1 → Node2\""

# -------------------------------
# Live logging configuration
# -------------------------------
proc log_counters {} {
    global ns app1 app2 runlog phylog miPhy1 miPhy2 miProp
    set t [$ns now]
    set s [$app1 getsentpkts]
    set r [$app2 getrecvpkts]

    puts $runlog "$t,sent=$s,rcv=$r"
    puts $phylog "\n==== Tcl tick t=$t ===="
    puts $phylog "  sent=$s, rcv=$r"

    # Keep debug on
    $miPhy1 set mi_debug_ 1
    $miPhy2 set mi_debug_ 1
    $miProp set debug_ 1

    flush $phylog
    flush $runlog

    $ns at [expr {$t + 1.0}] "log_counters"
}
$ns at 5.2 "log_counters"

# -------------------------------
# PHY–MAC binding and initialization
# -------------------------------

$mac1 setNoAckMode
$mac2 setNoAckMode

$mac1 set phy_ $miPhy1
$mac2 set phy_ $miPhy2
$miPhy1 set Mac_ $mac1
$miPhy2 set Mac_ $mac2
$mac1 initialize
$mac2 initialize


# ===============================
# Simulation runtime control
# ===============================
puts "Running UwMI simulation with distance = $opt(distance) m ..."
$miPhy1 set mi_debug_ 1
$miPhy2 set mi_debug_ 1

puts "---- Initialization complete ----"

# ===============================
# Results & finish
# ===============================
proc finish {} {
    global ns opt app1 app2 runlog phylog

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

    set outdir "results"
    if {![file isdirectory $outdir]} { file mkdir $outdir }

    set resultFile "$outdir/uwmi_results_summary_${opt(distance)}m.csv"
    set fd [open $resultFile a]
    puts $fd "distance=$opt(distance),sent=$sent,rcv=$rcv,per=$per,sigma=$opt(sigma),period=$opt(period),stop=$opt(stop)"
    close $fd

    set master "uwmi_results_summary_all.csv"
    set write_header 0
    if {![file exists $master]} { set write_header 1 }
    set fd [open $master a]
    if {$write_header} {
        puts $fd "distance_m,sent,rcv,per,sigma_Sperm,period_s,stop_s,seed,uw2aw,f_khz,Rb_bps,B_Hz,Q,NF_dB,Tnoise_K,txpwr_dbm,Nt,Nr,at_m,ar_m,Rt_ohm,Rr_ohm,kappa,pkt_bytes,distance_actual_m,Lw_m,La_m,dx_m,dy_m,dz_m,z1_m,z2_m,Nt_coils,Nr_coils,st_m,sr_m,auto_scale_R"

    }
    puts $fd "$opt(distance),$sent,$rcv,$per,$opt(sigma),$opt(period),$opt(stop),$opt(seed),$opt(uw2aw),$opt(f_khz),$opt(Rb),$opt(B),$opt(Q),$opt(NF_dB),$opt(Tnoise_K),$opt(txpwr_dbm),$opt(Nt),$opt(Nr),$opt(at),$opt(ar),$opt(Rt),$opt(Rr),$opt(kappa),$opt(pktsize),$opt(distance_actual),$opt(Lw_used),$opt(La_used),$opt(dx),$opt(dy),$opt(dz),$opt(z1_used),$opt(z2_used),$opt(Nt_coils),$opt(Nr_coils),$opt(st),$opt(sr),$opt(auto_scale_R)"



    close $fd

    flush $runlog
    flush $phylog
    close $runlog
    close $phylog

    $ns flush-trace
    close $opt(tracefile)
    close $opt(cltracefile)
    $ns halt
}
$ns at $opt(stop) "$app1 stop"
$ns at [expr {$opt(stop) + 6}] "finish"
$ns at [expr {$opt(stop) + 8}] "$ns halt"

# -------------------------------
# Start simulation
# -------------------------------
$ns run