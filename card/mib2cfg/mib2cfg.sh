#!/bin/ksh
# MIB2 Configurator: put edited skin0 files on a MIB2 Standard (PQ/ZR) unit, or put the originals back.
#
# Standalone: it needs nothing on the unit but the Green Engineering Menu. It installs the car data files under
# Data/ too (zone files with the ambient light points and touch areas), which the toolbox's Customization > Skins
# leaves out.
#
# Its own green menu screen, MIB2 Configurator (Main > MIB2 Configurator), has one button each for check, install,
# restore and reboot; the buttons run this file from the drive as "mib2cfg.sh <mode>". The screen is installed
# once with mode "menu", started any way that can run a script from the drive, e.g. olli991's MIB STD2 PQ/ZR
# Toolbox: Tools > "Run toolbox.sh script from the root of the Toolbox drive" runs toolbox.sh, which runs this file
# with the mode from mib2cfg/mode. Keep Unix line endings in every file.
#
# On the drive (SD card or USB stick):
#   toolbox.sh                 launcher for the toolbox's Tools route (first install of the screen)
#   mib2cfg/mib2cfg.sh         this file
#   mib2cfg/mode               the mode when started without one: check (the default, read only), install,
#                              restore, menu or removemenu
#   mib2cfg/skin0/...          the files to install, at their place in skin0, e.g.
#                                mib2cfg/skin0/images.mcf
#                                mib2cfg/skin0/Data/0204080200/GenericCarAdjuster/AmbianceLight/0.gca
#   mib2cfg/backup/skin0/...   written here: each unit file as it was before this script first replaced it
#   mib2cfg/greenmenu/...      the screen (mib2cfg.esd) and its button scripts (scripts/mib2cfg_*.sh)
#   mib2cfg/log.txt            what the last run did
#
# check:      changes nothing on the unit (writes only mib2cfg/log.txt): tests that this shell and the commands
#             work, lists every file install would replace (sizes, differs or same, backup state), free space.
# install:    replaces only files that already exist on the unit (nothing is added or deleted) and only when they
#             differ. Before the first replacement of a file its original is copied to the backup and compared;
#             that copy is never overwritten, so it stays the unit's own file however often you install.
# restore:    copies every backed-up file back. The backup stays on the drive.
# menu:       adds (or updates) only this script's own menu files, mib2cfg*, in /tsd/etc/persistence/esd; reopen
#             the green menu afterwards. Nothing else there is touched.
# removemenu: deletes those files again (the screen disappears after reopening the green menu).
# Started without a mode the script sets the next one itself: after an install the next run restores, after a
# clean restore or menu change it only checks. The menu buttons always do what they say and leave mib2cfg/mode.
# Every file is copied next to its target, compared, then renamed over it (see put), and compared again.
# Restart the unit when it says FINISHED: the HMI keeps the old images.mcf open until then.

ROOT=/tsd/hmi/Resources/skin0

# The drive this file is on: the first SD card or USB stick with mib2cfg/mib2cfg.sh.
VOLUME=""
for i in /media/mp00*; do
	if [ -f $i/mib2cfg/mib2cfg.sh ]; then
		VOLUME=$i
		break
	fi
done
if [ -z "$VOLUME" ]; then
	echo "ERROR: no SD card or USB stick with mib2cfg/mib2cfg.sh found"
	exit 1
fi

CFG=$VOLUME/mib2cfg
SRC=$CFG/skin0
BAK=$CFG/backup/skin0
LOG=$CFG/log.txt

ESD=/tsd/etc/persistence/esd
MENU=$CFG/greenmenu

lower() {
	echo "$1" | sed -e 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/' -e 's/[^a-z]//g'
}

# A menu button passes the mode; the Tools route reads it from mib2cfg/mode.
FROMFILE=""
MODE=check
if [ -n "$1" ]; then
	MODE=$(lower "$1")
elif [ -f $CFG/mode ]; then
	MODE=$(lower "$(head -1 $CFG/mode)")
	FROMFILE=1
fi

: > $LOG
say() {
	echo "$1"
	echo "$1" >> $LOG
}

# True when both files exist and are byte for byte the same.
same() {
	[ -f "$1" ] && [ -f "$2" ] && [ -z "$(cmp "$1" "$2" 2>&1)" ]
}

RW=""
writable() {
	if [ -z "$RW" ]; then
		# The system partition is read only; this is how the unit's own tools remount it.
		mount -t qnx6 -o remount,rw /dev/hd0t177 /
		RW=1
	fi
}

# Replaces file $2 with a copy of $1 without ever writing into $2 itself: the copy goes next to it, is compared,
# and is then renamed over it (one step on the same file system). A program that has the old file open, like the
# HMI with images.mcf, keeps reading the old file until it reopens it; a failed copy leaves $2 as it was.
# Returns 0 when $2 now equals $1, 1 when $2 was not touched, 2 when the rename left $2 different from $1.
put() {
	tmp="$2.mib2cfg-new"
	rm -f "$tmp"
	say "       copying ${2##*/} ($(human "$1"))..."
	if ! copy "$1" "$tmp" || ! checked "$1" "$tmp"; then
		rm -f "$tmp"
		return 1
	fi
	chmod a+rw "$tmp"
	if ! mv -f "$tmp" "$2"; then
		rm -f "$tmp"
		return 1
	fi
	if checked "$1" "$2" "checking the installed file"; then return 0; fi
	return 2
}

# Number of files under $1 (the unit has no wc).
count() {
	n=0
	for f in $(find "$1" -type f); do n=$((n+1)); done
	echo $n
}

# Size in MB, rounded up.
mb() {
	echo $(( ($(size "$1") + 1048575) / 1048576 ))
}

# Size for people: KB below 1 MB.
human() {
	n=$(size "$1")
	if [ "$n" -lt 1048576 ]; then echo "$(( (n + 1023) / 1024 )) KB"; else echo "$(mb "$1") MB"; fi
}

# A ten-step bar: bar 40 -> [####------]  40%
bar() {
	n=$(($1 / 10))
	b=""
	i=0
	while [ $i -lt 10 ]; do
		if [ $i -lt $n ]; then b="$b#"; else b="$b-"; fi
		i=$((i+1))
	done
	echo "[$b] $1%"
}

# Copies $1 to the new file $2 with cp. For big files cp runs in the background while a bar line is printed every
# 10 percent of the new file's size (the unit has no dd; the green menu shows script output line by line, so the
# bar is repeated rather than redrawn).
copy() {
	total=$(size "$1")
	if [ "$total" -le 8388608 ]; then
		cp "$1" "$2" 2>/dev/null
		return $?
	fi
	cp "$1" "$2" 2>/dev/null &
	pid=$!
	shown=0
	while kill -0 $pid 2>/dev/null; do
		sleep 1
		now=$(size "$2")
		[ -z "$now" ] && now=0
		step=$((now / (total / 10 + 1)))
		if [ $step -gt $shown ] && [ $step -lt 10 ]; then
			echo "       $(bar $((step * 10)))"
			shown=$step
		fi
	done
	wait $pid
	r=$?
	if [ $r -eq 0 ]; then echo "       $(bar 100)"; fi
	return $r
}

# same, saying so first: comparing a big file takes a while on the unit.
checked() {
	if [ "$(mb "$1")" -gt 8 ]; then echo "       ${3:-checking the copy}..."; fi
	same "$1" "$2"
}

# Reports put's result for one file.
report() {
	case $1 in
	0)	say "OK     $2"; DONE=$((DONE+1)) ;;
	1)	say "ERROR  $2: could not copy it (full?); the unit's file is unchanged"; FAILED=$((FAILED+1)) ;;
	*)	say "ERROR  $2: the file on the unit differs after copying. $3"; FAILED=$((FAILED+1)) ;;
	esac
}

DONE=0
FAILED=0

say "MIB2 Configurator: $MODE ($ROOT)"
say ""

size() {
	ls -l "$1" 2>/dev/null | awk '{print $5}'
}

if [ "$MODE" = "check" ]; then
	say "Read only: nothing on the unit is changed."
	say ""
	say "--- shell"
	say "uname: $(uname -a 2>&1)"
	say "shell: $SHELL $KSH_VERSION"
	t=/a/b/c.gca
	n=3
	n=$((n+1))
	say "parameter expansion (want /a/b and c.gca): ${t%/*} and ${t##*/}"
	say "arithmetic (want 4): $n"
	say "sed y (want restore): $(echo ReStore | sed -e 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/' -e 's/[^a-z]//g')"
	if same $CFG/../mib2cfg/mib2cfg.sh $CFG/mib2cfg.sh; then say "cmp on identical files: same (good)"; else say "cmp on identical files: NOT same (bad)"; fi
	if same $CFG/mib2cfg.sh $LOG; then say "cmp on different files: same (bad)"; else say "cmp on different files: differ (good)"; fi
	say ""
	say "--- commands"
	for c in find cmp cp mv chmod rm kill sleep mkdir sed awk head ls df mount sync; do
		say "$c: $(command -v $c 2>&1)"
	done
	say ""
	say "--- system partition"
	say "$(mount 2>&1 | grep ' / ' )"
	say "$(df -k / 2>&1 | tail -1)"
	say "$(df -k /tsd 2>&1 | tail -1)"
	say ""
	say "--- unit skin0"
	if [ -d $ROOT ]; then
		say "$ROOT is there"
		say "$(ls -l $ROOT 2>&1)"
	else
		say "ERROR: $ROOT is missing"
	fi
	say ""
	say "--- files install would replace (from mib2cfg/skin0)"
	if [ -d $SRC ]; then
		for f in $(find $SRC -type f); do
			rel=${f#$SRC/}
			dst=$ROOT/$rel
			b=$BAK/$rel
			if [ ! -f "$dst" ]; then
				say "SKIP   $rel (not on the unit)"
				continue
			fi
			if same "$f" "$dst"; then state="same as the unit"; else state="DIFFERS: would be replaced"; fi
			if [ ! -f "$b" ]; then bstate="no backup yet: the unit's file would be backed up"
			elif same "$b" "$dst"; then bstate="backup = the unit's file"
			else bstate="backup is a different file (restore puts the backup back)"; fi
			say "$rel"
			say "    unit $(size "$dst") bytes, stick $(size "$f") bytes: $state"
			say "    $bstate"
		done
	else
		say "(no mib2cfg/skin0 folder on the stick)"
	fi
	say ""
	say "--- other copies of the car data on /tsd (zone files)"
	for f in $(find $SRC -type f -name "*.gca" 2>/dev/null); do
		name=${f##*/}
		dir=${f%/*}
		car=${dir#$SRC/Data/}
		car=${car%%/*}
		say "$car/.../$name:"
		say "$(find /tsd -type f -name "$name" 2>/dev/null | grep "/$car/")"
	done
	say ""
	say "Check finished. Send mib2cfg/log.txt."
	exit 0
fi

STEP=0
if [ "$MODE" = "install" ]; then
	if [ ! -d $SRC ]; then
		say "ERROR: $SRC is missing. Put the edited files there."
		exit 1
	fi
	COUNT=$(count $SRC)
	say "Installing $COUNT file(s). Keep the ignition on and the stick in until it says FINISHED."
	for f in $(find $SRC -type f); do
		rel=${f#$SRC/}
		dst=$ROOT/$rel
		if [ ! -f "$dst" ]; then
			say "SKIP   $rel (not on the unit)"
			continue
		fi
		STEP=$((STEP+1))
		say ""
		say "($STEP/$COUNT) $rel"
		if checked "$f" "$dst" "comparing with the unit's file"; then
			say "same   $rel (already on the unit)"
			continue
		fi
		b=$BAK/$rel
		if [ ! -f "$b" ]; then
			mkdir -p "${b%/*}"
			say "       backing up the unit's ${rel##*/} to the stick..."
			copy "$dst" "$b"
			if ! checked "$dst" "$b"; then
				rm -f "$b"
				say "ERROR  $rel: could not back up the original; left as it was"
				FAILED=$((FAILED+1))
				continue
			fi
			say "backup $rel"
		fi
		writable
		put "$f" "$dst"
		report $? "$rel" "Run restore."
	done
elif [ "$MODE" = "restore" ]; then
	if [ ! -d $BAK ]; then
		say "Nothing to restore: $BAK is missing."
		exit 0
	fi
	COUNT=$(count $BAK)
	say "Restoring $COUNT original file(s). Keep the ignition on and the stick in until it says FINISHED."
	for b in $(find $BAK -type f); do
		rel=${b#$BAK/}
		dst=$ROOT/$rel
		STEP=$((STEP+1))
		say ""
		say "($STEP/$COUNT) $rel"
		if checked "$b" "$dst" "comparing with the unit's file"; then
			say "same   $rel (already the original)"
			continue
		fi
		writable
		put "$b" "$dst"
		report $? "$rel" "Try restore again."
	done
elif [ "$MODE" = "menu" ]; then
	# Only our own files (mib2cfg*): the screen and its button scripts. Nothing else in the green menu is touched.
	for f in $(find $MENU -type f -name "mib2cfg*"); do
		rel=${f#$MENU/}
		dst=$ESD/$rel
		if [ ! -d "${dst%/*}" ]; then
			say "SKIP   $rel (${dst%/*} is not on the unit)"
			continue
		fi
		if same "$f" "$dst"; then
			say "same   $rel"
			continue
		fi
		writable
		put "$f" "$dst"
		r=$?
		case "$dst" in *.sh) chmod a+rx "$dst" ;; esac
		report $r "$rel" "Run menu again."
	done
elif [ "$MODE" = "removemenu" ]; then
	# Only our own files: the screen and the button scripts this script installed.
	for f in $ESD/mib2cfg*.esd $ESD/scripts/mib2cfg_*.sh; do
		[ -f "$f" ] || continue
		writable
		rm -f "$f"
		if [ -f "$f" ]; then
			say "ERROR  ${f#$ESD/}: could not delete it"
			FAILED=$((FAILED+1))
		else
			say "removed ${f#$ESD/}"
			DONE=$((DONE+1))
		fi
	done
else
	say "ERROR: unknown mode '$MODE' (check, install, restore, menu or removemenu)"
	exit 1
fi

if [ -n "$RW" ]; then
	sync
	mount -t qnx6 -o remount,ro /dev/hd0t177 /
fi

# Tools route only: the next run undoes this one. After any install (also a failed one) it restores; after a clean
# restore or menu install it only checks; a restore or menu install with errors stays as it is, to be retried.
NEXT=""
if [ -n "$FROMFILE" ]; then
	if [ "$MODE" = "install" ]; then NEXT=restore
	elif [ $FAILED -eq 0 ]; then NEXT=check
	else NEXT=$MODE; fi
	echo "$NEXT" > $CFG/mode
fi

case $MODE in
install) WHAT=INSTALL ;;
restore) WHAT=RESTORE ;;
menu) WHAT="MENU INSTALL" ;;
*) WHAT="MENU REMOVAL" ;;
esac

say ""
say "$DONE file(s) changed, $FAILED error(s)."
if [ "$NEXT" = "restore" ]; then
	say "Tools route: the NEXT RUN RESTORES the original files (mib2cfg/mode now says restore)."
elif [ "$NEXT" = "check" ]; then
	say "Tools route: the next run only checks (mib2cfg/mode now says check)."
fi
say ""
say "=================================================="
if [ $FAILED -gt 0 ]; then
	say "  $WHAT FAILED: $FAILED error(s), see the lines above"
	if [ "$MODE" = "install" ]; then
		say "  Press Restore original files, then Reboot unit."
	else
		say "  Try again; the log is mib2cfg/log.txt"
	fi
elif [ $DONE -gt 0 ] && [ "$MODE" = "removemenu" ]; then
	say "  $WHAT FINISHED: $DONE file(s) removed"
	say "  Close and reopen the green menu."
elif [ $DONE -gt 0 ] && [ "$MODE" = "menu" ]; then
	say "  $WHAT FINISHED"
	say "  Close and reopen the green menu:"
	say "  Main > MIB2 Configurator"
elif [ $DONE -gt 0 ]; then
	say "  $WHAT FINISHED: $DONE file(s) copied"
	say "  Now press Reboot unit. Look at the screens"
	say "  only after the reboot."
else
	say "  $WHAT FINISHED: nothing needed copying"
	say "  The unit already has these files."
fi
say "=================================================="
exit 0
