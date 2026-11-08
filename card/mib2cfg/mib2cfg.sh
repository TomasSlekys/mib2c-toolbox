#!/bin/ksh
# MIB2 Configurator: put edited skin files (skin0 and the theme skins skin1..skin6) on a MIB2 Standard (PQ/ZR)
# unit, or put the originals back.
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
#   mib2cfg/skin1/ ... skin6/  the same for the theme skins (mainly images.mcf, images.res), e.g.
#                                mib2cfg/skin3/images.mcf
#                              an edit there applies to that theme only. Skins without files are skipped.
#   mib2cfg/backup/skinN/...   written here: each unit file as it was before this script first replaced it
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

# The unit's skin folders: skin0 and the theme skins skin1..skin6 side by side.
# MIB2CFG_RESOURCES, MIB2CFG_MEDIA and MIB2CFG_ESD are only for testing off the unit; leave them unset.
RES=${MIB2CFG_RESOURCES:-/tsd/hmi/Resources}
SKINS="skin0 skin1 skin2 skin3 skin4 skin5 skin6"
ROOT=$RES/skin0

# The drive this file is on: the first SD card or USB stick with mib2cfg/mib2cfg.sh.
VOLUME=""
for i in ${MIB2CFG_MEDIA:-/media/mp00*}; do
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

ESD=${MIB2CFG_ESD:-/tsd/etc/persistence/esd}
MENU=$CFG/greenmenu

# Points ROOT (unit), SRC (drive) and BAK (backup) at skin $1. PFX goes in front of file names in messages:
# nothing for skin0, "skinN/" for a theme skin.
useskin() {
	ROOT=$RES/$1
	SRC=$CFG/$1
	BAK=$CFG/backup/$1
	if [ "$1" = "skin0" ]; then PFX=""; else PFX="$1/"; fi
}

# True when folder $1 holds at least one file.
hasfiles() {
	[ -d "$1" ] && [ -n "$(find "$1" -type f 2>/dev/null | head -1)" ]
}

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

# Free KB on the file system that holds $1: df -k's Available column (third from the end of its last line, which
# also works when a long device name pushes the numbers onto a line of their own). Empty when it can't be read.
freekb() {
	df -k "$1" 2>/dev/null | tail -1 | awk '{ if (NF >= 4) print $(NF-2) }' | sed 's/[^0-9]//g'
}

# "N MB free", or that it is unknown, from a KB count that may be empty.
freetext() {
	if [ -n "$1" ]; then echo "$(($1 / 1024)) MB free"; else echo "free space unknown"; fi
}

# Kept free on top of what the copies need, in KB.
MARGIN=4096

# The space a run needs, in KB, for files from $1 ("SRC": the stick's skin folders, install; "BAK": the backups,
# restore). NEEDUNIT: each file is first copied next to its target, so the unit needs the largest file once more,
# plus everything the new files are bigger than the ones they replace. NEEDSTICK: the backups install still has to
# make (unit files with no backup yet). Files already the same are counted too, so it errs on the safe side.
needed() {
	grow=0
	peak=0
	bak=0
	for s in $SKINS; do
		useskin $s
		if [ "$1" = "BAK" ]; then from=$BAK; else from=$SRC; fi
		[ -d $from ] || continue
		for f in $(find $from -type f); do
			rel=${f#$from/}
			dst=$ROOT/$rel
			[ -f "$dst" ] || continue
			n=$(size "$f")
			o=$(size "$dst")
			[ $n -gt $peak ] && peak=$n
			[ $n -gt $o ] && grow=$((grow + n - o))
			[ "$1" = "SRC" ] && [ ! -f "$BAK/$rel" ] && bak=$((bak + o))
		done
	done
	NEEDUNIT=$(( (grow + peak + 1023) / 1024 + MARGIN ))
	NEEDSTICK=$(( (bak + 1023) / 1024 + MARGIN ))
}

# Copies an interrupted run left on the unit (power lost while copying): FILE.mib2cfg-new next to a skin file.
leftovers() {
	find $RES -type f -name "*.mib2cfg-new" 2>/dev/null
}

# Removes those copies; they are never the unit's own files.
cleanleftovers() {
	for f in $(leftovers); do
		writable
		rm -f "$f"
		if [ -f "$f" ]; then say "ERROR  could not remove the leftover copy $f"; else say "removed the leftover copy $f"; fi
	done
}

# Stops before anything is copied when the unit or the stick is short of space ($1: what is being done).
spacecheck() {
	needed $2
	free=$(freekb $RES)
	sfree=$(freekb $CFG)
	say "Space on the unit: needs $((NEEDUNIT / 1024)) MB, $(freetext "$free")"
	if [ "$2" = "SRC" ]; then
		say "Space on the stick for backups: needs $((NEEDSTICK / 1024)) MB, $(freetext "$sfree")"
	fi
	short=""
	if [ -n "$free" ] && [ $free -lt $NEEDUNIT ]; then short="the unit has $((free / 1024)) MB free, $((NEEDUNIT / 1024)) MB are needed"; fi
	if [ "$2" = "SRC" ] && [ -n "$sfree" ] && [ $sfree -lt $NEEDSTICK ]; then short="${short:+$short; }the stick has $((sfree / 1024)) MB free, $((NEEDSTICK / 1024)) MB are needed for the backups"; fi
	if [ -z "$free" ]; then say "WARNING: could not read the unit's free space; going on (a copy that does not fit is removed and the unit's file kept)"; fi
	[ -z "$short" ] && return 0
	if [ -n "$RW" ]; then
		sync
		mount -t qnx6 -o remount,ro /dev/hd0t177 /
	fi
	say ""
	say "=================================================="
	say "  $1 STOPPED: NOT ENOUGH SPACE"
	say "  $short."
	say "  Nothing was copied. Free some space and try again."
	say "=================================================="
	exit 1
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
	# skin0 always; a theme skin only when the stick has files for it.
	for s in $SKINS; do
		useskin $s
		if [ "$s" != "skin0" ] && ! hasfiles $SRC; then continue; fi
		say "--- unit $s"
		if [ -d $ROOT ]; then
			say "$ROOT is there"
			say "$(ls -l $ROOT 2>&1)"
		else
			say "ERROR: $ROOT is missing"
		fi
		say ""
		say "--- files install would replace (from mib2cfg/$s)"
		if [ -d $SRC ]; then
			for f in $(find $SRC -type f); do
				rel=${f#$SRC/}
				dst=$ROOT/$rel
				b=$BAK/$rel
				if [ ! -f "$dst" ]; then
					say "SKIP   $PFX$rel (not on the unit)"
					continue
				fi
				if same "$f" "$dst"; then state="same as the unit"; else state="DIFFERS: would be replaced"; fi
				if [ ! -f "$b" ]; then bstate="no backup yet: the unit's file would be backed up"
				elif same "$b" "$dst"; then bstate="backup = the unit's file"
				else bstate="backup is a different file (restore puts the backup back)"; fi
				say "$PFX$rel"
				say "    unit $(size "$dst") bytes, stick $(size "$f") bytes: $state"
				say "    $bstate"
			done
		else
			say "(no mib2cfg/skin0 folder on the stick)"
		fi
		say ""
	done
	say "--- space"
	needed SRC
	free=$(freekb $RES)
	sfree=$(freekb $CFG)
	say "unit: install needs $((NEEDUNIT / 1024)) MB, $(freetext "$free")"
	say "stick: backups need $((NEEDSTICK / 1024)) MB, $(freetext "$sfree")"
	say ""
	say "--- leftover copies from interrupted runs (install and restore remove them)"
	l=$(leftovers)
	if [ -n "$l" ]; then say "$l"; else say "none"; fi
	say ""
	useskin skin0
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
	COUNT=0
	FOUND=""
	for s in $SKINS; do
		useskin $s
		[ -d $SRC ] || continue
		FOUND=1
		COUNT=$((COUNT + $(count $SRC)))
	done
	if [ -z "$FOUND" ]; then
		say "ERROR: $CFG/skin0 is missing. Put the edited files there."
		exit 1
	fi
	cleanleftovers
	spacecheck INSTALL SRC
	say ""
	say "Installing $COUNT file(s). Keep the ignition on and the stick in until it says FINISHED."
	for s in $SKINS; do
		useskin $s
		[ -d $SRC ] || continue
		for f in $(find $SRC -type f); do
			rel=${f#$SRC/}
			dst=$ROOT/$rel
			if [ ! -f "$dst" ]; then
				say "SKIP   $PFX$rel (not on the unit)"
				continue
			fi
			STEP=$((STEP+1))
			say ""
			say "($STEP/$COUNT) $PFX$rel"
			if checked "$f" "$dst" "comparing with the unit's file"; then
				say "same   $PFX$rel (already on the unit)"
				continue
			fi
			b=$BAK/$rel
			if [ ! -f "$b" ]; then
				mkdir -p "${b%/*}"
				say "       backing up the unit's ${rel##*/} to the stick..."
				copy "$dst" "$b"
				if ! checked "$dst" "$b"; then
					rm -f "$b"
					say "ERROR  $PFX$rel: could not back up the original; left as it was"
					FAILED=$((FAILED+1))
					continue
				fi
				say "backup $PFX$rel"
			fi
			writable
			put "$f" "$dst"
			report $? "$PFX$rel" "Run restore."
		done
	done
elif [ "$MODE" = "restore" ]; then
	COUNT=0
	FOUND=""
	for s in $SKINS; do
		useskin $s
		[ -d $BAK ] || continue
		FOUND=1
		COUNT=$((COUNT + $(count $BAK)))
	done
	if [ -z "$FOUND" ]; then
		say "Nothing to restore: $CFG/backup/skin0 is missing."
		exit 0
	fi
	cleanleftovers
	spacecheck RESTORE BAK
	say ""
	say "Restoring $COUNT original file(s). Keep the ignition on and the stick in until it says FINISHED."
	for s in $SKINS; do
		useskin $s
		[ -d $BAK ] || continue
		for b in $(find $BAK -type f); do
			rel=${b#$BAK/}
			dst=$ROOT/$rel
			STEP=$((STEP+1))
			say ""
			say "($STEP/$COUNT) $PFX$rel"
			if checked "$b" "$dst" "comparing with the unit's file"; then
				say "same   $PFX$rel (already the original)"
				continue
			fi
			writable
			put "$b" "$dst"
			report $? "$PFX$rel" "Try restore again."
		done
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
