#!/bin/ksh
# MIB2 Configurator launcher for the MIB STD2 Toolbox: Tools > "Run toolbox.sh script from the root of the Toolbox drive".
# Runs mib2cfg/mib2cfg.sh from this drive; the mode comes from mib2cfg/mode (check if there is none).
for i in /media/mp00*; do
	if [ -f $i/mib2cfg/mib2cfg.sh ]; then
		ksh $i/mib2cfg/mib2cfg.sh
		exit 0
	fi
done
echo "ERROR: no SD card or USB stick with mib2cfg/mib2cfg.sh found"
exit 0
