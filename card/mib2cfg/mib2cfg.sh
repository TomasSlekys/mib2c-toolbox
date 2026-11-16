#!/bin/ksh
# mib2cfg-version 0.3.0
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
#   mib2cfg/backup/MANIFEST    size (and cksum) of every backup, checked before a restore
#   mib2cfg/backup/card.id     this card's id; the unit keeps it in its marker (mib2cfg.state, next to the menu)
#   mib2cfg/backup/unit.txt    the unit's firmware fingerprint when the first backup was made
#   mib2cfg/greenmenu/...      the screen (mib2cfg.esd) and its button scripts (scripts/mib2cfg_*.sh)
#   mib2cfg/logs/NNNN-mode.log one log per run, never overwritten; mib2cfg/log.txt is a copy of the latest run
#
# check:      changes nothing on the unit (writes only the logs): tests that this shell and the commands work,
#             lists every file install would replace (sizes, differs or same, backup state, refusals), free space.
# install:    replaces only files that already exist on the unit (nothing is added or deleted) and only when they
#             differ, after checking that each new file is plausible (not empty, right header, about the right
#             size, not another skin's file). Before the first replacement of a file its original is copied to the
#             backup (as .part, compared, renamed, flushed); that copy is never overwritten, so it stays the unit's
#             own file however often you install.
# restore:    copies every backed-up file back (each checked against MANIFEST first). The backup stays on the drive.
# menu:       adds or updates only this script's own menu files, mib2cfg*, in /tsd/etc/persistence/esd, and removes
#             our button scripts the card no longer has; reopen the green menu afterwards. An older menu than the
#             one on the unit is refused unless the mode is "menu force".
# removemenu: deletes those files again (the screen disappears after reopening the green menu). The small marker
#             mib2cfg.state stays: it says which card holds this unit's original files.
# A second word "reboot" ("install reboot", "restore reboot") restarts the unit at the end, but only when every
# file was copied, nothing failed and the system partition is read only again.
# Started without a mode the script sets the next one itself: after an install the next run restores, after a
# clean restore or menu change it only checks. The menu buttons always do what they say and leave mib2cfg/mode.
# Every file is copied next to its target, compared, then renamed over it (see put), and compared again.
# Restart the unit when it says FINISHED: the HMI keeps the old images.mcf open until then.
#
# Exit codes: 0 files changed cleanly (check: finished), 1 stopped before copying anything or a run-wide error,
# 2 some files failed, 3 nothing needed changing.

VERSION=0.3.0

# Everything that went to stderr shows in the green menu too.
exec 2>&1

# The unit's folders. The MIB2CFG_* variables are only for testing off the unit; leave them unset.
RES=${MIB2CFG_RESOURCES:-/tsd/hmi/Resources}
ESD=${MIB2CFG_ESD:-/tsd/etc/persistence/esd}
STARTANIM=${MIB2CFG_STARTANIM:-/tsd/etc/startanim}
HMIDIR=${MIB2CFG_HMI:-/tsd/hmi}
TMPD=${MIB2CFG_TMP:-/tmp}
SHUTDOWN=${MIB2CFG_SHUTDOWN:-/bin/shutdown}
PARTDEV=/dev/hd0t177
SKINS="skin0 skin1 skin2 skin3 skin4 skin5 skin6"
ROOT=$RES/skin0
SKIN=skin0

# Writes one line as it is, without echo's backslash handling (print on ksh, printf elsewhere).
if (print -r -- x) >/dev/null 2>&1; then
	out() { print -r -- "$1"; }
else
	out() { printf '%s\n' "$1"; }
fi

# True when command $1 exists.
have() {
	command -v "$1" >/dev/null 2>&1 || whence "$1" >/dev/null 2>&1
}

# The drive this file is on: the folder it was started from, or else the first SD card or USB stick with
# mib2cfg/mib2cfg.sh. CARDS counts every drive that has one: with more than one, nothing is written.
VOLUME=""
case "$0" in
*/mib2cfg/mib2cfg.sh) [ -f "$0" ] && VOLUME=${0%/mib2cfg/mib2cfg.sh} ;;
esac
CARDS=0
CARDLIST=""
for i in ${MIB2CFG_MEDIA:-/media/mp00*}; do
	if [ -f "$i/mib2cfg/mib2cfg.sh" ]; then
		CARDS=$((CARDS+1))
		CARDLIST="$CARDLIST $i"
		[ -z "$VOLUME" ] && VOLUME=$i
	fi
done
if [ -z "$VOLUME" ]; then
	out "ERROR: no SD card or USB stick with mib2cfg/mib2cfg.sh found"
	exit 1
fi

CFG=$VOLUME/mib2cfg
SRC=$CFG/skin0
BAKROOT=$CFG/backup
BAK=$BAKROOT/skin0
LOG=$CFG/log.txt
LOGDIR=$CFG/logs
MENU=$CFG/greenmenu
STATE=$ESD/mib2cfg.state
MANIFEST=$BAKROOT/MANIFEST
CARDIDFILE=$BAKROOT/card.id
UNITFILE=$BAKROOT/unit.txt
LOCK=$TMPD/mib2cfg.lock
OKMARK=$TMPD/mib2cfg.ok
PENDING=$TMPD/mib2cfg.reboot-pending

# Points ROOT (unit), SRC (drive) and BAK (backup) at skin $1. PFX goes in front of file names in messages:
# nothing for skin0, "skinN/" for a theme skin.
useskin() {
	SKIN=$1
	ROOT=$RES/$1
	SRC=$CFG/$1
	BAK=$BAKROOT/$1
	if [ "$1" = "skin0" ]; then PFX=""; else PFX="$1/"; fi
}

lower() {
	out "$1" | sed -e 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/' -e 's/[^a-z]//g'
}

# The mode: a menu button passes it (and maybe "reboot" or "force"); the Tools route reads it from mib2cfg/mode,
# whose CR, BOM and other non-letters are dropped (an empty file means check).
FROMFILE=""
MODE=""
WORD2=""
if [ -n "$1" ]; then
	MODE=$(lower "$1")
	WORD2=$(lower "$2")
elif [ -f "$CFG/mode" ]; then
	MODE=$(lower "$(head -1 "$CFG/mode")")
	FROMFILE=1
fi
[ -z "$MODE" ] && MODE=check
REBOOT=""
FORCE=""
case "$MODE" in
installreboot) MODE=install; REBOOT=1 ;;
restorereboot) MODE=restore; REBOOT=1 ;;
menuforce) MODE=menu; FORCE=1 ;;
esac
case "$WORD2" in
reboot) REBOOT=1 ;;
force) FORCE=1 ;;
esac
case "$MODE" in
check|install|restore|menu|removemenu) ;;
*)
	out "ERROR: unknown mode '$MODE' (check, install, restore, menu or removemenu). Nothing was changed."
	exit 1
	;;
esac

# --- The logs on the card: logs/NNNN-mode.log for this run (never overwritten) and log.txt, the latest run.
# NNNN is one more than the highest number there; there is no counter file a power cut could spoil.
# Writing them is tested before anything touches the unit: a card that can't be written stops the run here.
LOGFAIL=""
pad4() {
	p=$1
	while [ ${#p} -lt 4 ]; do p=0$p; done
	out "$p"
}
lognumber() {
	max=0
	for f in "$LOGDIR"/[0-9][0-9][0-9][0-9]-*.log; do
		[ -f "$f" ] || continue
		b=${f##*/}
		b=${b%%-*}
		b=$(out "$b" | sed 's/^0*//')
		[ -z "$b" ] && b=0
		case "$b" in *[!0-9]*) continue ;; esac
		[ "$b" -gt "$max" ] && max=$b
	done
	out $((max+1))
}
mkdir -p "$LOGDIR" 2>/dev/null
# Two runs at once (two buttons) must not pick the same name: a short lock on the card, taken over when stale.
tries=0
while ! mkdir "$LOGDIR/.lock" 2>/dev/null; do
	[ -d "$LOGDIR" ] || break
	tries=$((tries+1))
	if [ $tries -ge 10 ]; then rm -rf "$LOGDIR/.lock"; mkdir "$LOGDIR/.lock" 2>/dev/null; break; fi
	sleep 1
done
n=$(lognumber)
RUNLOG="$LOGDIR/$(pad4 $n)-$MODE.log"
while [ -f "$RUNLOG" ]; do
	n=$((n+1))
	RUNLOG="$LOGDIR/$(pad4 $n)-$MODE.log"
done
HEAD="MIB2 Configurator $VERSION: $MODE${REBOOT:+ reboot}${FORCE:+ force}"
{ out "$HEAD" > "$RUNLOG"; } 2>/dev/null
rmdir "$LOGDIR/.lock" 2>/dev/null
sync
if [ "$(head -1 "$RUNLOG" 2>/dev/null)" != "$HEAD" ] || ! { out "$HEAD" > "$LOG"; } 2>/dev/null; then
	out "ERROR: can't write the log on the card ($CFG): it is read only or full."
	out "Nothing was changed. Check the card (write protection switch, free space) and try again."
	exit 1
fi

# Shows a line and appends it to both logs. A failed log write never stops a copy half way: it only sets LOGFAIL,
# and the loops stop at the next file.
say() {
	out "$1"
	if ! { out "$1" >> "$RUNLOG"; } 2>/dev/null || ! { out "$1" >> "$LOG"; } 2>/dev/null; then
		LOGFAIL=1
	fi
}

# Creates an empty file $1; false when it can't. In a subshell: a failed redirection on ":" (a special built-in)
# would end the whole script.
touchfile() {
	( : > "$1" ) 2>/dev/null
}

# True when both files exist and are byte for byte the same.
same() {
	[ -f "$1" ] && [ -f "$2" ] && [ -z "$(cmp "$1" "$2" 2>&1)" ]
}

# Size in bytes; 0 when it can't be read.
size() {
	s=$(ls -l "$1" 2>/dev/null | awk '{print $5}')
	case "$s" in ''|*[!0-9]*) s=0 ;; esac
	out "$s"
}

# The cksum of $1, or - when the unit has no cksum.
sum() {
	if have cksum; then cksum "$1" 2>/dev/null | awk '{print $1}'; else out "-"; fi
}

# --- The system partition. Writing is switched on only when needed, and only after checking that the partition
# mounted on / is the one the unit's own tools remount. RW is set as soon as a remount was tried, so the exit
# trap always puts it back to read only; a test write proves it really is writable.
RW=""
RWEVER=""
ROOK=""
STOP=""
rootline() {
	mount 2>/dev/null | grep ' on / ' | head -1
}
writable() {
	wdir=${1:-$RES}
	if [ -z "$RW" ]; then
		case "$(rootline)" in
		*"$PARTDEV"*) ;;
		*)
			say "ERROR: / is not mounted from $PARTDEV on this unit ($(rootline)); nothing is written."
			STOP=1
			return 1
			;;
		esac
		RW=1
		RWEVER=1
		if ! mount -t qnx6 -o remount,rw $PARTDEV /; then
			say "ERROR: could not make the system partition writable (mount failed)."
			STOP=1
			return 1
		fi
	fi
	if ! touchfile "$wdir/.mib2cfg-rw"; then
		say "ERROR: the system partition is still read only ($wdir can't be written)."
		STOP=1
		return 1
	fi
	rm -f "$wdir/.mib2cfg-rw"
	return 0
}

# Back to read only, checked: ROOK is set only when a test write fails afterwards.
ro_again() {
	[ -n "$RW" ] || return 0
	sync
	if ! mount -t qnx6 -o remount,ro $PARTDEV /; then
		say "WARNING: making the system partition read only again failed; reboot the unit."
	fi
	if touchfile "$RES/.mib2cfg-rw"; then
		rm -f "$RES/.mib2cfg-rw"
		say "WARNING: the system partition is still writable; reboot the unit."
		ROOK=""
	else
		ROOK=1
	fi
	RW=""
}

# --- The run lock (only one writing run at a time, also against the Reboot button) and the exit trap, which
# always puts the partition back to read only.
HAVELOCK=""
LISTS=""
cleanup() {
	trap - EXIT HUP INT TERM 2>/dev/null
	ro_again
	[ -n "$LISTS" ] && rm -f $LISTS
	[ -n "$HAVELOCK" ] && rmdir "$LOCK" 2>/dev/null
	HAVELOCK=""
	sync
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

rm -f "$OKMARK" 2>/dev/null

# Replaces file $2 with a copy of $1 without ever writing into $2 itself: the copy goes next to it (named for this
# run), gets its mode ($3 = x: a script) before the rename, is compared, and is then renamed over it (one step on
# the same file system). A program that has the old file open, like the HMI with images.mcf, keeps reading the
# old file until it reopens it; a failed copy leaves $2 as it was.
# Returns 0 when $2 now equals $1, 1 when $2 was not touched, 2 when the rename left $2 different from $1.
put() {
	tmp="$2.mib2cfg-new.$$"
	rm -f "$tmp"
	say "       copying ${2##*/} ($(human "$1")); the unit's file was $(ls -l "$2" 2>/dev/null | awk '{print $1}')..."
	if ! copy "$1" "$tmp" || ! checked "$1" "$tmp"; then
		rm -f "$tmp"
		return 1
	fi
	chmod a+rw "$tmp"
	[ "$3" = "x" ] && chmod a+rx "$tmp"
	if ! mv -f "$tmp" "$2"; then
		rm -f "$tmp"
		return 1
	fi
	if checked "$1" "$2" "checking the installed file"; then return 0; fi
	return 2
}

# Writes the list of files under $1 (no dot files, no partial backups) into a new temp file.
# Loops read it with "while read -r f <&3 ... done 3< list", so names with spaces stay whole and the counters stay
# in this shell (a pipe into while would run the loop in a subshell on this ksh).
# Sets NL to the list's name (no $(...): a subshell couldn't count the lists).
NLIST=0
newlist() {
	NLIST=$((NLIST+1))
	NL="$TMPD/mib2cfg.list.$$.$NLIST"
	LISTS="$LISTS $NL"
	find "$1" -type f 2>/dev/null | grep -v '/\.' | grep -v '\.part$' > "$NL"
}

# Number of lines in list $1 (the unit has no wc).
count() {
	c=0
	while read -r x <&3; do c=$((c+1)); done 3< "$1"
	out $c
}

# Size in MB, rounded up.
mb() {
	out $(( ($(size "$1") + 1048575) / 1048576 ))
}

# Size for people: KB below 1 MB.
human() {
	h=$(size "$1")
	if [ "$h" -lt 1048576 ]; then out "$(( (h + 1023) / 1024 )) KB"; else out "$(mb "$1") MB"; fi
}

# A ten-step bar: bar 40 -> [####------]  40%
bar() {
	bn=$(($1 / 10))
	b=""
	i=0
	while [ $i -lt 10 ]; do
		if [ $i -lt $bn ]; then b="$b#"; else b="$b-"; fi
		i=$((i+1))
	done
	out "[$b] $1%"
}

# Copies $1 to the new file $2 with cp. For big files cp runs in the background while a bar line is printed every
# 10 percent of the new file's size (the unit has no dd; the green menu shows script output line by line, so the
# bar is repeated rather than redrawn). The bars go to the screen only, not into the logs.
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
		step=$((now / (total / 10 + 1)))
		if [ $step -gt $shown ] && [ $step -lt 10 ]; then
			out "       $(bar $((step * 10)))"
			shown=$step
		fi
	done
	wait $pid
	r=$?
	if [ $r -eq 0 ]; then out "       $(bar 100)"; fi
	return $r
}

# same, saying so first: comparing a big file takes a while on the unit.
checked() {
	if [ "$(mb "$1")" -gt 8 ]; then out "       ${3:-checking the copy}..."; fi
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

say "MIB2 Configurator $VERSION: $MODE${REBOOT:+ (reboot when finished)}${FORCE:+ (force)}"
say "card: $VOLUME; log: ${RUNLOG#$CFG/}"
if [ "$CARDS" -gt 1 ]; then say "cards with mib2cfg:$CARDLIST"; fi
say ""

# Free KB on the file system that holds $1: df -k's Available column (third from the end of its last line, which
# also works when a long device name pushes the numbers onto a line of their own). Empty when it can't be read.
freekb() {
	df -k "$1" 2>/dev/null | tail -1 | awk '{ if (NF >= 4) print $(NF-2) }' | sed 's/[^0-9]//g'
}

# "N MB free", or that it is unknown, from a KB count that may be empty.
freetext() {
	if [ -n "$1" ]; then out "$(($1 / 1024)) MB free"; else out "free space unknown"; fi
}

# Kept free on top of what the copies need, in KB.
MARGIN=16384

# The space a run needs, in KB, for files from $1 ("SRC": the stick's skin folders, install; "BAK": the backups,
# restore). NEEDUNIT: the HMI keeps the old images.mcf open until a reboot, so a replaced file keeps its space
# until then: every new file that differs counts in full, plus the largest once more (its copy next to the
# target). NEEDSTICK: the backups install still has to make, plus 1 MB for the logs.
needed() {
	newsum=0
	peak=0
	bak=0
	for s in $SKINS; do
		useskin $s
		if [ "$1" = "BAK" ]; then from=$BAK; else from=$SRC; fi
		[ -d "$from" ] || continue
		newlist "$from"
		nl=$NL
		while read -r f <&3; do
			rel=${f#$from/}
			dst=$ROOT/$rel
			[ -f "$dst" ] || continue
			n=$(size "$f")
			o=$(size "$dst")
			[ "$n" -eq "$o" ] && same "$f" "$dst" && continue
			newsum=$((newsum + n))
			[ $n -gt $peak ] && peak=$n
			[ "$1" = "SRC" ] && [ ! -f "$BAK/$rel" ] && bak=$((bak + o))
		done 3< "$nl"
	done
	NEEDUNIT=$(( (newsum + peak + 1023) / 1024 + MARGIN ))
	NEEDSTICK=$(( (bak + 1023) / 1024 + 1024 + MARGIN ))
}

# Copies an interrupted run left on the unit (power lost while copying): NAME.mib2cfg-new[.PID] next to a skin,
# menu or startup file.
leftovers() {
	find "$RES" "$ESD" "$STARTANIM" -type f -name "*.mib2cfg-new*" 2>/dev/null
}

# Removes those copies; they are never the unit's own files.
cleanleftovers() {
	lo="$TMPD/mib2cfg.leftovers.$$"
	LISTS="$LISTS $lo"
	leftovers > "$lo"
	while read -r f <&3; do
		writable "${f%/*}" || return 1
		rm -f "$f"
		if [ -f "$f" ]; then say "ERROR  could not remove the leftover copy $f"; else say "removed the leftover copy $f"; fi
	done 3< "$lo"
	return 0
}

# Stops before anything is copied when the unit or the stick is short of space ($1: what is being done).
spacecheck() {
	needed $2
	free=$(freekb "$RES")
	sfree=$(freekb "$CFG")
	say "Space on the unit: needs $((NEEDUNIT / 1024)) MB, $(freetext "$free")"
	if [ "$2" = "SRC" ]; then
		say "Space on the stick for backups and logs: needs $((NEEDSTICK / 1024)) MB, $(freetext "$sfree")"
	fi
	short=""
	if [ -n "$free" ] && [ $free -lt $NEEDUNIT ]; then short="the unit has $((free / 1024)) MB free, $((NEEDUNIT / 1024)) MB are needed"; fi
	if [ "$2" = "SRC" ] && [ -n "$sfree" ] && [ $sfree -lt $NEEDSTICK ]; then short="${short:+$short; }the stick has $((sfree / 1024)) MB free, $((NEEDSTICK / 1024)) MB are needed for the backups"; fi
	if [ -z "$free" ]; then say "WARNING: could not read the unit's free space; going on (a copy that does not fit is removed and the unit's file kept)"; fi
	[ -z "$short" ] && return 0
	say ""
	say "=================================================="
	say "  $1 STOPPED: NOT ENOUGH SPACE"
	say "  $short."
	say "  Nothing was copied. Free some space and try again."
	say "=================================================="
	exit 1
}

# --- Is a new file plausible? Prints why not (empty when it is fine).
# Refused: an empty file; for images.mcf / images.res / .boot a different header (first 4 bytes) than the unit's
# file, or (mcf, boot) a size outside half to double of the unit's; a file byte for byte the same as another skin's
# file on the unit (dropped into the wrong skin folder).
firstdiff() {
	d=$(cmp "$1" "$2" 2>&1)
	p=$(out "$d" | sed -n 's/.* char \([0-9][0-9]*\).*/\1/p')
	[ -z "$p" ] && p=$(out "$d" | sed -n 's/.* byte \([0-9][0-9]*\).*/\1/p')
	out "$p"
}
invalid() {
	vf=$1
	vd=$2
	vrel=$3
	vn=$(size "$vf")
	vo=$(size "$vd")
	if [ "$vn" -eq 0 ]; then out "the new file is empty"; return; fi
	case "${vrel##*/}" in
	images.mcf|images.res|*.boot)
		p=$(firstdiff "$vf" "$vd")
		if [ -n "$p" ] && [ "$p" -le 4 ]; then out "its header differs from the unit's file (not this kind of file?)"; return; fi
		;;
	esac
	case "${vrel##*/}" in
	images.mcf|*.boot)
		if [ "$vo" -gt 0 ] && { [ $((vn * 2)) -lt "$vo" ] || [ "$vn" -gt $((vo * 2)) ]; }; then
			out "its size ($vn bytes) is less than half or more than double the unit's file ($vo bytes)"
			return
		fi
		;;
	esac
	for s2 in $SKINS; do
		[ "$s2" = "$SKIN" ] && continue
		u=$RES/$s2/$vrel
		[ -f "$u" ] || continue
		[ "$(size "$u")" -eq "$vn" ] || continue
		if same "$vf" "$u"; then out "it is the same file as $s2's on the unit (wrong skin folder?)"; return; fi
	done
}

# --- Backup bookkeeping on the card and the marker on the unit.
# The unit's firmware fingerprint: size and name of every file in the HMI folder (changes with a firmware update).
fingerprint() {
	fpl=$(ls -l "$HMIDIR" 2>/dev/null | awk '$1 ~ /^-/ {print $5, $NF}')
	if [ -z "$fpl" ]; then out ""; return; fi
	if have cksum; then out "$fpl" | cksum | awk '{print "cksum " $1 " " $2}'; else out "$fpl" | awk '{printf "%s ", $0}'; fi
}
cardid() {
	[ -f "$CARDIDFILE" ] && head -1 "$CARDIDFILE"
}
statecard() {
	[ -f "$STATE" ] && sed -n 's/^card //p' "$STATE" | head -1
}
statehas() {
	[ -f "$STATE" ] && awk -v p="file $1" '$0 == p {f = 1} END {exit !f}' "$STATE"
}
# Rewrites the marker on the unit as the lines in temp file $1 (copied next to it, compared and renamed).
statewrite() {
	writable "$ESD" || return 1
	sw="$STATE.mib2cfg-new.$$"
	if cp "$1" "$sw" 2>/dev/null && same "$1" "$sw" && mv -f "$sw" "$STATE"; then return 0; fi
	rm -f "$sw"
	say "ERROR  could not write the unit's marker $STATE"
	return 1
}
# Adds "file $1" (and the card line) to the marker.
statemark() {
	sn="$TMPD/mib2cfg.state.$$"
	LISTS="$LISTS $sn"
	{
		out "card $(cardid)"
		[ -f "$STATE" ] && grep '^file ' "$STATE"
		out "file $1"
	} > "$sn"
	statewrite "$sn"
}
# Makes sure this card has an id and the firmware fingerprint before its first backup.
prepcard() {
	mkdir -p "$BAKROOT" 2>/dev/null
	if [ ! -f "$CARDIDFILE" ]; then
		out "c$RANDOM$RANDOM$$" > "$CARDIDFILE"
		sync
		say "this card's backup id: $(cardid)"
	fi
	if [ ! -f "$UNITFILE" ]; then
		fp=$(fingerprint)
		out "${fp:-unknown}" > "$UNITFILE"
		sync
	fi
}
# Stops the run (before copying) when this card's backups belong to another card or firmware.
cardcheck() {
	sc=$(statecard)
	cid=$(cardid)
	if [ -n "$sc" ] && [ "$sc" != "$cid" ]; then
		say ""
		say "=================================================="
		say "  $1 STOPPED: WRONG CARD"
		say "  This unit's original files are backed up on the card with id $sc,"
		say "  this card is ${cid:-new (no backups yet)}. Use that card."
		say "  Nothing was copied."
		say "=================================================="
		exit 1
	fi
	if [ -f "$UNITFILE" ]; then
		was=$(head -1 "$UNITFILE")
		now=$(fingerprint)
		if [ -z "$now" ] || [ "$was" = "unknown" ]; then
			say "WARNING: the firmware fingerprint can't be compared; going on."
		elif [ "$was" != "$now" ]; then
			say ""
			say "=================================================="
			say "  $1 STOPPED: OTHER FIRMWARE"
			say "  The backups on this card were made on other firmware than the unit runs now."
			say "  Move mib2cfg/backup to a PC (keep it) and start with an empty backup folder."
			say "  Nothing was copied."
			say "=================================================="
			exit 1
		fi
	fi
	if [ -z "$sc" ] && [ -n "$cid" ]; then
		say "NOTE: the unit has no marker yet; this card's backups are taken as the unit's originals."
	fi
}
# Backs up the unit's file $1 to $2 safely: as $2.part, compared, renamed, flushed, made read only, and recorded
# in MANIFEST as $3. A cut at any point leaves only a .part, which is ignored and redone next time.
backupfile() {
	mkdir -p "${2%/*}"
	rm -f "$2.part"
	if ! copy "$1" "$2.part" || ! checked "$1" "$2.part" || ! mv -f "$2.part" "$2"; then
		rm -f "$2.part"
		return 1
	fi
	sync
	chmod a-w "$2" 2>/dev/null
	out "$3 $(size "$2") $(sum "$2")" >> "$MANIFEST"
	sync
	same "$1" "$2"
}
# Checks backup $1 (recorded as $2) against MANIFEST; prints the problem, empty when fine or not recorded.
manifestbad() {
	[ -f "$MANIFEST" ] || return 0
	m=$(awk -v p="$2" '$1 == p {print $2, $3}' "$MANIFEST" | tail -1)
	[ -z "$m" ] && return 0
	ms=${m%% *}
	mc=${m#* }
	if [ "$(size "$1")" != "$ms" ]; then out "its size is not the recorded $ms bytes"; return 0; fi
	if [ "$mc" != "-" ] && have cksum && [ "$(sum "$1")" != "$mc" ]; then out "its checksum is not the recorded one"; fi
}

# --- Check: changes nothing on the unit.
if [ "$MODE" = "check" ]; then
	say "Read only: nothing on the unit is changed."
	say ""
	say "--- shell"
	say "uname: $(uname -a 2>&1)"
	say "shell: $SHELL $KSH_VERSION; ksh: $(command -v ksh 2>&1)"
	say "PATH: $PATH"
	say "id: $(id 2>&1); pwd: $(pwd 2>&1)"
	t=/a/b/c.gca
	n=3
	n=$((n+1))
	say "parameter expansion (want /a/b and c.gca): ${t%/*} and ${t##*/}"
	say "arithmetic (want 4): $n; leading zero 0012+1 (want 13): $(( $(out 0012 | sed 's/^0*//') + 1 ))"
	say "sed y (want restore): $(lower ReStore)"
	say "print: $( (print -r -- 'a\tb') 2>&1 ) (want a\\tb)"
	say "typeset -Z4 (want 0012): $( (typeset -Z4 z=12; out "$z") 2>&1 )"
	say "trap EXIT (want trap-ok): $( (trap 'out trap-ok' EXIT; exit 0) 2>&1 )"
	pw=0
	out a | while read x; do pw=1; done
	say "pipe into while keeps variables (0 on pdksh, mksh): $pw"
	if same "$CFG/../mib2cfg/mib2cfg.sh" "$CFG/mib2cfg.sh"; then say "cmp on identical files: same (good)"; else say "cmp on identical files: NOT same (bad)"; fi
	if same "$CFG/mib2cfg.sh" "$RUNLOG"; then say "cmp on different files: same (bad)"; else say "cmp on different files: differ (good)"; fi
	say "cmp's report format: $(cmp "$CFG/mib2cfg.sh" "$RUNLOG" 2>&1 | head -1)"
	say ""
	say "--- commands"
	for c in find cmp cp mv chmod rm kill sleep mkdir rmdir sed awk head tail grep ls df mount sync cksum od tr id slay; do
		say "$c: $(command -v $c 2>&1)"
	done
	say "head -c: $(out abc | head -c 1 2>&1)"
	say "awk -v (want ok): $(awk -v p=ok 'BEGIN {print p}' 2>&1)"
	say ""
	say "--- environment"
	el="$TMPD/mib2cfg.env.$$"
	LISTS="$LISTS $el"
	env > "$el" 2>&1
	while read -r x <&3; do say "  $x"; done 3< "$el"
	say ""
	say "--- system partition"
	say "root: $(rootline)"
	say "tsd: $(mount 2>&1 | grep tsd | head -3)"
	say "$(df -k / 2>&1 | tail -1)"
	say "$(df -k /tsd 2>&1 | tail -1)"
	say "startanim: $(df -k "$STARTANIM" 2>&1 | tail -1)"
	say ""
	if [ "$CARDS" -gt 1 ]; then
		say "WARNING: $CARDS cards have mib2cfg ($CARDLIST ). Install, restore and menu refuse to run until only one is in."
		say ""
	fi
	say "--- backups and marker"
	say "this card's id: $(cardid)"
	sc=$(statecard)
	say "unit marker: ${sc:-none}"
	if [ -n "$sc" ] && [ "$sc" != "$(cardid)" ]; then say "WARNING: the unit's originals are on another card ($sc)"; fi
	if [ -f "$UNITFILE" ]; then
		if [ "$(head -1 "$UNITFILE")" = "$(fingerprint)" ]; then say "firmware: same as when the backups were made"; else say "WARNING: firmware differs from when the backups were made"; fi
	fi
	if [ -f "$PENDING" ]; then say "reboot pending: yes, reboot before the next install or restore"; else say "reboot pending: no"; fi
	say ""
	for s in $SKINS; do
		useskin $s
		if [ "$s" != "skin0" ] && [ ! -d "$SRC" ]; then continue; fi
		say "--- unit $s"
		if [ -d "$ROOT" ]; then
			say "$ROOT is there"
			say "$(ls -l "$ROOT" 2>&1)"
		else
			say "ERROR: $ROOT is missing"
		fi
		say ""
		say "--- files install would replace (from mib2cfg/$s)"
		if [ -d "$SRC" ]; then
			newlist "$SRC"
			nl=$NL
			while read -r f <&3; do
				rel=${f#$SRC/}
				dst=$ROOT/$rel
				b=$BAK/$rel
				case "$rel" in *" "*) say "SKIP   $PFX$rel (a space in the name: not supported)"; continue ;; esac
				if [ ! -f "$dst" ]; then
					say "SKIP   $PFX$rel (not on the unit; names are case sensitive there)"
					continue
				fi
				if same "$f" "$dst"; then state="same as the unit"; else state="DIFFERS: would be replaced"; fi
				why=$(invalid "$f" "$dst" "$rel")
				[ -n "$why" ] && state="WOULD BE REFUSED: $why"
				if [ ! -f "$b" ]; then
					if statehas "$s/$rel"; then bstate="no backup on this card, but the unit's marker says one was made: would be refused"
					else bstate="no backup yet: the unit's file would be backed up"; fi
				elif same "$b" "$dst"; then bstate="backup = the unit's file"
				else bstate="backup is a different file (restore puts the backup back)"; fi
				[ -f "$b.part" ] && bstate="$bstate; a partial backup (.part) from an interrupted run is ignored"
				say "$PFX$rel"
				say "    unit $(size "$dst") bytes, stick $(size "$f") bytes: $state"
				say "    $bstate"
			done 3< "$nl"
		else
			say "(no mib2cfg/$s folder on the stick)"
		fi
		say ""
	done
	say "--- menu"
	cv=$(sed -n 's/^# mib2cfg-version //p' "$MENU/mib2cfg.esd" 2>/dev/null | head -1)
	uv=$(sed -n 's/^# mib2cfg-version //p' "$ESD/mib2cfg.esd" 2>/dev/null | head -1)
	if [ -n "$cv" ] && [ "$cv" = "$uv" ]; then mv2=": same"; else mv2=": differ (run menu to update)"; fi
	say "card menu ${cv:-unknown}, unit menu ${uv:-not installed or older than 0.3.0}$mv2"
	say ""
	say "--- space"
	needed SRC
	free=$(freekb "$RES")
	sfree=$(freekb "$CFG")
	say "unit: install needs $((NEEDUNIT / 1024)) MB, $(freetext "$free")"
	say "stick: backups and logs need $((NEEDSTICK / 1024)) MB, $(freetext "$sfree")"
	say ""
	say "--- leftover copies from interrupted runs (install and restore remove them)"
	l=$(leftovers)
	if [ -n "$l" ]; then say "$l"; else say "none"; fi
	say ""
	useskin skin0
	say "--- other copies of the car data on /tsd (zone files)"
	gl="$TMPD/mib2cfg.gca.$$"
	LISTS="$LISTS $gl"
	find "$SRC" -type f -name "*.gca" 2>/dev/null > "$gl"
	while read -r f <&3; do
		name=${f##*/}
		dir=${f%/*}
		car=${dir#$SRC/Data/}
		car=${car%%/*}
		say "$car/.../$name:"
		say "$(find /tsd -type f -name "$name" 2>/dev/null | grep "/$car/")"
	done 3< "$gl"
	say ""
	say "Check finished. Send mib2cfg/log.txt (or the newest file in mib2cfg/logs)."
	exit 0
fi

# --- Writing modes: one card only, one run at a time, and not twice without a reboot.
if [ "$CARDS" -gt 1 ]; then
	say "ERROR: $CARDS cards with mib2cfg are in ($CARDLIST ). Take out all but one and try again. Nothing was changed."
	exit 1
fi
if ! mkdir "$LOCK" 2>/dev/null; then
	say "ERROR: another MIB2 Configurator run is still busy (or one was cut off: reboot the unit). Nothing was changed."
	exit 1
fi
HAVELOCK=1
if [ "$MODE" = "install" ] || [ "$MODE" = "restore" ]; then
	if [ -f "$PENDING" ]; then
		say "ERROR: an earlier run replaced files and the unit has not rebooted since. Press Reboot unit first,"
		say "then run this again (the HMI keeps the old files open until a reboot). Nothing was changed."
		exit 1
	fi
fi

STEP=0
if [ "$MODE" = "install" ]; then
	COUNT=0
	FOUND=""
	for s in $SKINS; do
		useskin $s
		[ -d "$SRC" ] || continue
		FOUND=1
		newlist "$SRC"
		nl=$NL
		COUNT=$((COUNT + $(count "$nl")))
	done
	if [ -z "$FOUND" ]; then
		say "ERROR: $CFG/skin0 is missing. Put the edited files there."
		exit 1
	fi
	cardcheck INSTALL
	cleanleftovers || exit 1
	spacecheck INSTALL SRC
	say ""
	say "Installing $COUNT file(s). Keep the ignition on and the stick in until it says FINISHED."
	for s in $SKINS; do
		useskin $s
		[ -d "$SRC" ] || continue
		[ -n "$STOP" ] && break
		newlist "$SRC"
		nl=$NL
		while read -r f <&3; do
			[ -n "$STOP" ] && break
			if [ -n "$LOGFAIL" ]; then say "ERROR: the log can't be written any more; stopping before the next file."; STOP=1; FAILED=$((FAILED+1)); break; fi
			rel=${f#$SRC/}
			dst=$ROOT/$rel
			case "$rel" in *" "*) say "SKIP   $PFX$rel (a space in the name: not supported)"; continue ;; esac
			if [ ! -f "$dst" ]; then
				say "SKIP   $PFX$rel (not on the unit; names are case sensitive there)"
				continue
			fi
			STEP=$((STEP+1))
			say ""
			say "($STEP/$COUNT) $PFX$rel"
			if checked "$f" "$dst" "comparing with the unit's file"; then
				say "same   $PFX$rel (already on the unit)"
				continue
			fi
			why=$(invalid "$f" "$dst" "$rel")
			if [ -n "$why" ]; then
				say "ERROR  $PFX$rel: refused, $why; the unit's file is unchanged"
				FAILED=$((FAILED+1))
				continue
			fi
			b=$BAK/$rel
			if [ ! -f "$b" ]; then
				if statehas "$s/$rel"; then
					say "ERROR  $PFX$rel: the unit's marker says its original was backed up before, but this card has no backup."
					say "       Not replaced, so the edited file on the unit can't become the 'original'. Use the card with the backup."
					FAILED=$((FAILED+1))
					continue
				fi
				prepcard
				say "       backing up the unit's ${rel##*/} to the stick..."
				if ! backupfile "$dst" "$b" "$s/$rel"; then
					say "ERROR  $PFX$rel: could not back up the original; left as it was"
					FAILED=$((FAILED+1))
					continue
				fi
				say "backup $PFX$rel"
				if ! statemark "$s/$rel"; then FAILED=$((FAILED+1)); STOP=1; break; fi
			elif ! statehas "$s/$rel"; then
				# A backup from an older version (or a marker without this file): record it.
				prepcard
				if ! statemark "$s/$rel"; then FAILED=$((FAILED+1)); STOP=1; break; fi
			fi
			writable || { FAILED=$((FAILED+1)); break; }
			put "$f" "$dst"
			report $? "$PFX$rel" "Run restore."
		done 3< "$nl"
	done
elif [ "$MODE" = "restore" ]; then
	COUNT=0
	FOUND=""
	for s in $SKINS; do
		useskin $s
		[ -d "$BAK" ] || continue
		FOUND=1
		newlist "$BAK"
		nl=$NL
		COUNT=$((COUNT + $(count "$nl")))
	done
	if [ -z "$FOUND" ]; then
		say "Nothing to restore: $CFG/backup/skin0 is missing."
		exit 3
	fi
	cardcheck RESTORE
	cleanleftovers || exit 1
	spacecheck RESTORE BAK
	say ""
	say "Restoring $COUNT original file(s). Keep the ignition on and the stick in until it says FINISHED."
	for s in $SKINS; do
		useskin $s
		[ -d "$BAK" ] || continue
		[ -n "$STOP" ] && break
		newlist "$BAK"
		nl=$NL
		while read -r b <&3; do
			[ -n "$STOP" ] && break
			if [ -n "$LOGFAIL" ]; then say "ERROR: the log can't be written any more; stopping before the next file."; STOP=1; FAILED=$((FAILED+1)); break; fi
			rel=${b#$BAK/}
			dst=$ROOT/$rel
			case "$rel" in *" "*) say "SKIP   $PFX$rel (a space in the name: not supported)"; continue ;; esac
			if [ ! -f "$dst" ]; then
				say "SKIP   $PFX$rel (not on the unit: restore never adds files)"
				continue
			fi
			STEP=$((STEP+1))
			say ""
			say "($STEP/$COUNT) $PFX$rel"
			if checked "$b" "$dst" "comparing with the unit's file"; then
				say "same   $PFX$rel (already the original)"
				continue
			fi
			bad=$(manifestbad "$b" "$s/$rel")
			if [ -z "$bad" ] && [ "$(size "$b")" -eq 0 ]; then bad="it is empty"; fi
			if [ -n "$bad" ]; then
				say "ERROR  $PFX$rel: the backup is damaged ($bad); not restored, the unit's file is unchanged"
				FAILED=$((FAILED+1))
				continue
			fi
			writable || { FAILED=$((FAILED+1)); break; }
			put "$b" "$dst"
			report $? "$PFX$rel" "Try restore again."
		done 3< "$nl"
	done
elif [ "$MODE" = "menu" ]; then
	# Only our own files (mib2cfg*): the screen and its button scripts. Nothing else in the green menu is touched.
	# Every file is checked first (Unix line endings, the shell line, the screen line); then the scripts go in, the
	# screen last, and only when every script made it.
	CR=$( (print -n '\r') 2>/dev/null || printf '\r')
	bad=""
	ml="$TMPD/mib2cfg.menu.$$"
	LISTS="$LISTS $ml"
	find "$MENU" -type f -name "mib2cfg*" 2>/dev/null | grep -v '/\.' > "$ml"
	while read -r f <&3; do
		if grep "$CR" "$f" >/dev/null 2>&1; then bad="$bad ${f#$MENU/}(Windows line endings)"; fi
		case "$f" in
		*.sh) [ "$(head -1 "$f")" = "#!/bin/ksh" ] || bad="$bad ${f#$MENU/}(first line is not #!/bin/ksh)" ;;
		*.esd) grep '^screen MIB2_Configurator Main' "$f" >/dev/null 2>&1 || bad="$bad ${f#$MENU/}(no MIB2_Configurator screen)" ;;
		esac
	done 3< "$ml"
	if [ ! -f "$MENU/mib2cfg.esd" ]; then bad="$bad mib2cfg.esd(missing)"; fi
	if [ -n "$bad" ]; then
		say "ERROR: the menu files on the card are damaged:$bad"
		say "Copy them from the release zip again (don't open and save them on Windows). Nothing was changed."
		exit 1
	fi
	vnum() {
		out "$1" | awk -F. '{ if (NF == 3) print $1 * 10000 + $2 * 100 + $3; else print 0 }'
	}
	cv=$(sed -n 's/^# mib2cfg-version //p' "$MENU/mib2cfg.esd" | head -1)
	uv=$(sed -n 's/^# mib2cfg-version //p' "$ESD/mib2cfg.esd" 2>/dev/null | head -1)
	say "menu on the card: ${cv:-unknown}; on the unit: ${uv:-none or older}"
	if [ -n "$uv" ] && [ "$(vnum "$uv")" -gt "$(vnum "$cv")" ] && [ -z "$FORCE" ]; then
		say "ERROR: the unit's menu ($uv) is newer than the card's (${cv:-unknown}). Use a newer card,"
		say "or set mib2cfg/mode to 'menu force' to go back. Nothing was changed."
		exit 1
	fi
	cleanleftovers || exit 1
	SCRIPTFAILED=""
	for kind in sh esd; do
		if [ "$kind" = "esd" ] && [ -n "$SCRIPTFAILED" ]; then
			say "SKIP   mib2cfg.esd (a button script failed; the old screen stays)"
			continue
		fi
		while read -r f <&3; do
			case "$f" in *.$kind) ;; *) continue ;; esac
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
			writable "$ESD" || { FAILED=$((FAILED+1)); SCRIPTFAILED=1; break; }
			if [ "$kind" = "sh" ]; then put "$f" "$dst" x; else put "$f" "$dst"; fi
			r=$?
			[ $r -ne 0 ] && SCRIPTFAILED=1
			report $r "$rel" "Run menu again."
		done 3< "$ml"
	done
	# Our button scripts and screens the card no longer has.
	if [ -z "$SCRIPTFAILED" ]; then
		for f in "$ESD"/mib2cfg*.esd "$ESD"/scripts/mib2cfg_*.sh; do
			[ -f "$f" ] || continue
			[ -f "$MENU/${f#$ESD/}" ] && continue
			writable "$ESD" || { FAILED=$((FAILED+1)); break; }
			rm -f "$f"
			if [ -f "$f" ]; then say "ERROR  ${f#$ESD/}: could not delete the old file"; FAILED=$((FAILED+1)); else say "removed ${f#$ESD/} (no longer on the card)"; DONE=$((DONE+1)); fi
		done
	fi
elif [ "$MODE" = "removemenu" ]; then
	# Only our own files: the screen and the button scripts this script installed. The marker stays.
	for f in "$ESD"/mib2cfg*.esd "$ESD"/scripts/mib2cfg_*.sh; do
		[ -f "$f" ] || continue
		writable "$ESD" || { FAILED=$((FAILED+1)); break; }
		rm -f "$f"
		if [ -f "$f" ]; then
			say "ERROR  ${f#$ESD/}: could not delete it"
			FAILED=$((FAILED+1))
		else
			say "removed ${f#$ESD/}"
			DONE=$((DONE+1))
		fi
	done
	[ -f "$STATE" ] && say "kept mib2cfg.state: it says which card holds this unit's original files"
fi

# Read only again, checked; a partition that stays writable counts as an error.
ro_again
if [ -n "$RWEVER" ] && [ -z "$ROOK" ]; then FAILED=$((FAILED+1)); fi
if [ $DONE -gt 0 ] && { [ "$MODE" = "install" ] || [ "$MODE" = "restore" ]; }; then
	touchfile "$PENDING"
fi

# Tools route only: the next run undoes this one. After any install (also a failed one) it restores; after a clean
# restore or menu install it only checks; a restore or menu install with errors stays as it is, to be retried.
NEXT=""
if [ -n "$FROMFILE" ]; then
	if [ "$MODE" = "install" ]; then NEXT=restore
	elif [ $FAILED -eq 0 ]; then NEXT=check
	else NEXT=$MODE; fi
	out "$NEXT" > "$CFG/mode"
fi

case $MODE in
install) WHAT=INSTALL ;;
restore) WHAT=RESTORE ;;
menu) WHAT="MENU INSTALL" ;;
removemenu) WHAT="MENU REMOVAL" ;;
*) WHAT=$MODE ;;
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
	if [ "$MODE" = "install" ] && [ $DONE -gt 0 ]; then
		say "  Press Restore original files, then Reboot unit."
	else
		say "  Try again; the log is mib2cfg/log.txt"
	fi
	RC=2
elif [ $DONE -gt 0 ] && [ "$MODE" = "removemenu" ]; then
	say "  $WHAT FINISHED: $DONE file(s) removed"
	say "  Close and reopen the green menu."
	RC=0
elif [ $DONE -gt 0 ] && [ "$MODE" = "menu" ]; then
	say "  $WHAT FINISHED"
	say "  Close and reopen the green menu:"
	say "  Main > MIB2 Configurator"
	RC=0
elif [ $DONE -gt 0 ]; then
	say "  $WHAT FINISHED: $DONE file(s) copied"
	if [ -z "$REBOOT" ]; then
		say "  Now press Reboot unit. Look at the screens"
		say "  only after the reboot."
	fi
	RC=0
else
	say "  $WHAT FINISHED: nothing needed copying"
	say "  The unit already has these files."
	RC=3
fi
say "=================================================="

# Clean, writing run: the marker a launcher may check, then the reboot when it was asked for. Never after errors,
# after nothing changed, or when the partition could not be made read only.
DOREBOOT=""
if [ $RC -eq 0 ] && [ -n "$ROOK" ] && [ $DONE -gt 0 ]; then
	touchfile "$OKMARK"
	if [ -n "$REBOOT" ]; then
		if [ "$MODE" = "install" ] || [ "$MODE" = "restore" ]; then DOREBOOT=1
		else say "No reboot: $MODE doesn't need one (close and reopen the green menu)."; fi
	fi
elif [ -n "$REBOOT" ]; then
	say "No reboot: the run did not finish cleanly with files copied."
fi
if [ -n "$DOREBOOT" ]; then
	say "Rebooting in 10 seconds..."
	cleanup
	sleep 10
	sync
	slay tsd.mibstd2.system.swdownload 2>/dev/null
	$SHUTDOWN
fi
exit $RC
