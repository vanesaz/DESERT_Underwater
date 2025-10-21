# Minimal loader test: can we load the lib and instantiate the module?

# Load core deps (order matters in ns-2/Miracle)
load libMiracle.so
load libmphy.so

# Load our new library
load libuwmi_propagation.so

# Create instance and set parameters via both methods (bind + command)
set miProp [new Module/UW/MI/Propagation]
$miProp set debug_ 1
$miProp setT  18
$miProp setS  35

puts "Created MI propagation: $miProp"
puts "Sanity OK."
exit 0
