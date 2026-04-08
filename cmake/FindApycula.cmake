# nextpnr-himbaechel-gowin only
# Apycula database is used for Gowin chip database generation.
# The Ruby script gowin_arch_gen.rb processes the Apycula data.

if (DEFINED ENV{APYCULA_INSTALL_PREFIX})
    set(apycula_default_install_prefix $ENV{APYCULA_INSTALL_PREFIX})
endif()
set(APYCULA_INSTALL_PREFIX ${apycula_default_install_prefix} CACHE STRING
    "Apycula install prefix (database directory)")
if (NOT APYCULA_INSTALL_PREFIX STREQUAL "")
	message(STATUS "Apycula install prefix: ${APYCULA_INSTALL_PREFIX}")
endif()
