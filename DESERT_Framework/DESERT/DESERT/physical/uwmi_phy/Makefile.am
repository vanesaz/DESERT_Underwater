AM_CXXFLAGS = -Wall -ggdb3

lib_LTLIBRARIES = libuwmi_phy.la

libuwmi_phy_la_SOURCES = initlib.cpp uwmi-phy.cpp
libuwmi_phy_la_CPPFLAGS = @NS_CPPFLAGS@ @NSMIRACLE_CPPFLAGS@ @DESERT_CPPFLAGS@
libuwmi_phy_la_LDFLAGS  = @NS_LDFLAGS@ @NSMIRACLE_LDFLAGS@ @DESERT_LDFLAGS@
libuwmi_phy_la_LIBADD   = @NS_LIBADD@ @NSMIRACLE_LIBADD@ @DESERT_LIBADD@

nodist_libuwmi_phy_la_SOURCES = InitTcl.cc
BUILT_SOURCES = InitTcl.cc
CLEANFILES = InitTcl.cc
TCL_FILES = uwmi-phy-default.tcl

InitTcl.cc: Makefile $(TCL_FILES)
	cat $(VPATH)/$(TCL_FILES) | @TCL2CPP@ UwMiPhyInitTclCode > InitTcl.cc

EXTRA_DIST = $(TCL_FILES)
