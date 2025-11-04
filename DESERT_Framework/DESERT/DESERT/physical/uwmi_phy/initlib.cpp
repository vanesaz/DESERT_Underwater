#include <tclcl.h>

extern EmbeddedTcl UwMiPhyInitTclCode;

extern "C" int
Uwmi_phy_Init()
{
    UwMiPhyInitTclCode.load();
    return 0;
}
