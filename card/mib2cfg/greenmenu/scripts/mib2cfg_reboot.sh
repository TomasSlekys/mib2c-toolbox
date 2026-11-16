#!/bin/ksh
# mib2cfg-version 0.4.0
# MIB2 Configurator button: restarts the unit (works without the SD card or stick).
# The same steps as the MIB STD2 Toolbox's reboot: write everything out, stop the software download
# service, then shut down (the unit starts again by itself). Refused while an install, restore or menu run is
# still busy: its lock in /tmp (which a reboot clears) holds its process id. A lock whose process is gone (a run
# that was killed) doesn't block the reboot.
# MIB2CFG_TMP and MIB2CFG_SHUTDOWN are only for testing off the unit.
LOCK=${MIB2CFG_TMP:-/tmp}/mib2cfg.lock
if [ -d "$LOCK" ]; then
	lp=$(head -1 "$LOCK/pid" 2>/dev/null)
	case "$lp" in ''|*[!0-9]*) lp="" ;; esac
	if [ -n "$lp" ] && kill -0 "$lp" 2>/dev/null; then
		echo "Not now: an install, restore or menu run is still busy. Wait for FINISHED, then press Reboot unit again."
		exit 0
	fi
	echo "An old lock from a run that is gone was found; rebooting anyway."
fi
echo "Rebooting..."
sync
sleep 2
sync
slay tsd.mibstd2.system.swdownload 2>/dev/null
${MIB2CFG_SHUTDOWN:-/bin/shutdown}
