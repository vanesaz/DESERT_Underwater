load libMiracle.so
load libmphy.so
load libuwmi_propagation.so
load libuwmi_phy.so

set miProp [new Module/UW/MI/Propagation]
set miPhy  [new Module/UW/MI/PHY]
$miPhy set debug_ 1

puts "UwMI_PHY loaded successfully"
exit 0
