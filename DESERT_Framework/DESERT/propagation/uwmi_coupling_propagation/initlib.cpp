#include <tclcl.h>
extern EmbeddedTcl UwMiCouplingPropagationInitTclCode;

extern "C" int
Uwmi_coupling_propagation_Init()
{
    UwMiCouplingPropagationInitTclCode.load();
    return 0;
}
