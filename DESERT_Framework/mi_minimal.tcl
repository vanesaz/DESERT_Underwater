# Core + EM + your MI model
load libMiracle.so
load libuwem_propagation.so
load libuwmi_propagation.so

# Simulator and channel
set ns [new Simulator]
set ch [new MChannel]

# Your MI propagation (enable prints)
set prop [new Module/UW/MI/Propagation]
$prop set T_ 20       ;# degC
$prop set S_ 35       ;# g/kg
$prop set debug_ 1    ;# show alpha/beta/PLtot etc.

# Attach propagation to channel (handle both APIs)
if {[catch { $ch set propagation_ $prop } err]} {
    if {[catch { $ch setPropagation $prop } err2]} {
        puts "ERROR attaching propagation: $err / $err2"; exit 1
    }
}

# Two miracle nodes
set n0 [$ns create-M_Node]
set n1 [$ns create-M_Node]

# Try to create the EM PHY (name can differ by build)
proc NewEmPhy {} {
    if {![catch { set p [new Module/UW/EM/PHY] }]} { return $p }
    if {![catch { set p [new Module/UW/EM/Phy] }]} { return $p }
    puts "No EM PHY class found (Module/UW/EM/PHY)."; exit 1
}
set phy0 [NewEmPhy]
set phy1 [NewEmPhy]

# Bind PHYs to channel (two possible setter styles)
if {[catch { $phy0 setChannel $ch }]} { catch { $phy0 set channel_ $ch } }
if {[catch { $phy1 setChannel $ch }]} { catch { $phy1 set channel_ $ch } }

# Operating frequency for your model (Hz)
catch { $phy0 set freq_ 1000000.0 }   ;# 1 MHz
catch { $phy1 set freq_ 1000000.0 }

# Optional transmit power if your PHY supports it (uncomment if present)
# catch { $phy0 set Pt_ 0.1 }          ;# 100 mW

# Mount PHYs in nodes
$ns add-module $n0 $phy0 0 "PHY"
$ns add-module $n1 $phy1 0 "PHY"

# Helper to set positions (works across builds)
proc SetPos {node x y z} {
    if {![catch { $node setX_ $x; $node setY_ $y; $node setZ_ $z }]} { return }
    set pos [$node getPosition]
    $pos setX_ $x; $pos setY_ $y; $pos setZ_ $z
}

# Place TX underwater (z<0) and RX above surface (z>=0) so MI model exercises uw+aw terms
SetPos $n0 0 0 -5
SetPos $n1 3 4  2

# Simple traffic: try UW/CBR (fallback to UW/VBR)
set app ""
if {![catch { set app [new Module/UW/CBR] }]} {
    $ns add-module $n0 $app 1 "APP"
    catch { $app set period_ 0.5 }
    catch { $app set pktSize_ 64 }
} elseif {![catch { set app [new Module/UW/VBR] }]} {
    $ns add-module $n0 $app 1 "APP"
    catch { $app set interval_ 0.5 }
    catch { $app set payload_size_ 64 }
} else {
    puts "No CBR/VBR app found; still fine—MI prints will appear on any PHY tx/rx."
}

# Wire app -> PHY (best-effort; not all stacks need this explicit connect)
catch { $ns connect $app $phy0 }

# Run briefly
$ns at 0.1 "catch {$app start}"
$ns at 2.0 "finish"
proc finish {} { puts "DONE"; exit 0 }

$ns run
