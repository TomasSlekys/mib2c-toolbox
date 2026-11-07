#!/bin/ksh
# MIB2 Configurator button: runs mib2cfg/mib2cfg.sh removemenu from the SD card or USB stick.
for i in /media/mp00*; do
	if [ -f $i/mib2cfg/mib2cfg.sh ]; then
		ksh $i/mib2cfg/mib2cfg.sh removemenu
		exit 0
	fi
done
echo "ERROR: no SD card or USB stick with mib2cfg/mib2cfg.sh found"
exit 0
