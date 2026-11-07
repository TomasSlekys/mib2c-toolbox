#!/bin/ksh
# MIB2 Configurator button: restarts the unit (works without the SD card or stick).
# The same steps as the MIB STD2 Toolbox's reboot: write everything out, stop the software download
# service, then shut down (the unit starts again by itself).
echo "Rebooting..."
sync
slay tsd.mibstd2.system.swdownload 2>/dev/null
/bin/shutdown
