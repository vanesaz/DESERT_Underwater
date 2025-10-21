// initlib.cpp  — libuwmi_propagation.so initializer

#include <tclcl.h>

// This symbol is generated from your default .tcl by the TCL2CPP step
extern EmbeddedTcl UwMiMPropagationInitTclCode;

extern "C" int
Uwmi_propagation_Init()
{
    UwMiMPropagationInitTclCode.load();
    return 0;
}
