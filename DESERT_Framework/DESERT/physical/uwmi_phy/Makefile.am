AM_CXXFLAGS = -Wall -ggdb3

lib_LTLIBRARIES = libuwmi_phy.la
libuwmi_phy_la_SOURCES    = initlib.cpp uwmi-phy.cpp
nodist_libuwmi_phy_la_SOURCES = InitTcl.cc

libuwmi_phy_la_CPPFLAGS   = @NS_CPPFLAGS@ @NSMIRACLE_CPPFLAGS@ @DESERT_CPPFLAGS@
libuwmi_phy_la_LDFLAGS    = @NS_LDFLAGS@  @NSMIRACLE_LDFLAGS@  @DESERT_LDFLAGS@
libuwmi_phy_la_LIBADD     = @NS_LIBADD@   @NSMIRACLE_LIBADD@   @DESERT_LIBADD@

TCL_FILES = uwmi-phy-default.tcl
BUILT_SOURCES = InitTcl.cc
CLEANFILES    = InitTcl.cc

InitTcl.cc: Makefile $(TCL_FILES)
	@TCL2CPP@ UwMiPhyInitTclCode < $(VPATH)/$(TCL_FILES) > $@
