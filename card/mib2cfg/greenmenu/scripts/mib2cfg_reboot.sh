#!/bin/ksh
# mib2cfg-version 0.3.0
# MIB2 Configurator button: restarts the unit (works without the SD card or stick).
# The same steps as the MIB STD2 Toolbox's reboot: write everything out, stop the software download
# service, then shut down (the unit starts again by itself). Refused while an install or restore is still
# copying (its lock is in /tmp, which a reboot clears).
if [ -d /tmp/mib2cfg.lock ]; then
	echo "Not now: an install, restore or menu run is still busy. Wait for FINISHED, then press Reboot unit again."
	exit 0
fi
echo "Rebooting..."
sync
sleep 2
sync
slay tsd.mibstd2.system.swdownload 2>/dev/null
/bin/shutdown
