#!/bin/sh
# Off-unit tests for card/mib2cfg/mib2cfg.sh, run inside the test image by tests/run.sh.
# Each case builds a fake unit (skins, green menu folder, startanim, HMI folder), a fake card at media/mp000 and
# stubs that come first in PATH: mount (lists / with a read-only or writable state, remounts by changing the fake
# unit's permissions, can be made to fail), df (set free space), shutdown and slay (record that they ran), sleep
# (instant) and wc, dd, date (missing on the unit, so they exit 127).
# SH picks the shell that runs mib2cfg.sh: mksh (default) or busybox.

SH=${SH:-mksh}
case "$SH" in busybox) RUN="busybox sh" ;; *) RUN=$SH ;; esac
PASS=0
FAILS=0
BASE=/tmp/t

ok() {
	if eval "$2"; then PASS=$((PASS+1)); else FAILS=$((FAILS+1)); echo "FAIL [$CASE] $1 (rc=$RC)"; echo "----- output"; tail -25 "$T/out"; echo "-----"; fi
}

mcf() { printf '\211MCF\r\n\032\n%s' "$1"; }
res() { printf '\005\000\000\000SkrX%s' "$1"; }
pad() { i=0; s=""; while [ $i -lt 40 ]; do s="$s$1"; i=$((i+1)); done; printf '%s' "$s"; }

setup() {
	CASE=$1
	T=$BASE/$1
	chmod -R u+w "$T" 2>/dev/null
	rm -rf "$T"
	U=$T/unit
	C=$T/media/mp000
	mkdir -p "$U/Resources/skin0/Data/x" "$U/Resources/skin1" "$U/esd/scripts" "$U/startanim" "$U/hmi" "$T/tmp" "$T/stub" "$C"
	mcf "$(pad orig0)" > "$U/Resources/skin0/images.mcf"
	mcf "$(pad orig0)" > "$T/orig0"
	printf 'gca-orig' > "$U/Resources/skin0/Data/x/0.gca"
	mcf "$(pad orig1)" > "$U/Resources/skin1/images.mcf"
	res "$(pad r1)" > "$U/Resources/skin1/images.res"
	printf 'boot' > "$U/startanim/startup_0.boot"
	printf 'firmware-1' > "$U/hmi/tsd.mibstd2.hmi.ifs"
	cp -r /repo/card/. "$C/"
	mkdir -p "$C/mib2cfg/skin0"
	printf 'check\n' > "$C/mib2cfg/mode"
	echo 900000 > "$T/unitfree"
	echo 900000 > "$T/cardfree"
	echo ro > "$T/rw"
	cat > "$T/stub/mount" <<EOF
#!/bin/sh
echo "mount \$*" >> $T/mount.log
if [ \$# -eq 0 ]; then echo "\${ROOTDEV:-/dev/hd0t177} on / type qnx6 (\$(cat $T/rw))"; exit 0; fi
case "\$*" in
*remount,rw*) [ -f $T/fail-rw ] && exit 1; chmod -R u+w $U; echo rw > $T/rw ;;
*remount,ro*) [ -f $T/fail-ro ] && exit 1; chmod -R a-w $U; echo ro > $T/rw ;;
esac
exit 0
EOF
	cat > "$T/stub/df" <<EOF
#!/bin/sh
case "\$2" in $T/media*) f=\$(cat $T/cardfree) ;; *) f=\$(cat $T/unitfree) ;; esac
echo "Filesystem 1K-blocks Used Available Use% Mounted on"
echo "/dev/x 9999999 1 \$f 1% /"
EOF
	printf '#!/bin/sh\ntouch %s/shutdown-called\n' "$T" > "$T/stub/shutdown"
	printf '#!/bin/sh\ntouch %s/slay-called\n' "$T" > "$T/stub/slay"
	printf '#!/bin/sh\nexit 0\n' > "$T/stub/sleep"
	for c in wc dd date; do printf '#!/bin/sh\necho "%s: not found" >&2\nexit 127\n' "$c" > "$T/stub/$c"; done
	chmod +x "$T"/stub/*
	chmod -R a-w "$U"
}

# Runs the card's script (or $SCRIPT) with the arguments; output in $T/out, exit code in RC.
run() {
	( cd / && env PATH="$T/stub:$PATH" MIB2CFG_RESOURCES="$U/Resources" MIB2CFG_ESD="$U/esd" MIB2CFG_STARTANIM="$U/startanim" \
		MIB2CFG_HMI="$U/hmi" MIB2CFG_MEDIA="$T/media/mp00*" MIB2CFG_TMP="$T/tmp" MIB2CFG_SHUTDOWN=shutdown \
		$RUN "${SCRIPT:-$C/mib2cfg/mib2cfg.sh}" "$@" ) > "$T/out" 2>&1
	RC=$?
}
edit0() { mcf "$(pad new0)" > "$C/mib2cfg/skin0/images.mcf"; }
reboot_sim() { rm -rf "$T/tmp"; mkdir -p "$T/tmp"; }
isrw() { [ "$(cat "$T/rw")" = rw ]; }
grepq() { grep -q -- "$1" "$T/out"; }

# --- check
setup check
edit0
run check
ok "check exits 0" '[ $RC -eq 0 ]'
ok "check writes a numbered log" '[ -f $C/mib2cfg/logs/0001-check.log ] && [ -f $C/mib2cfg/log.txt ]'
ok "check never remounts" '! grep -q remount $T/mount.log 2>/dev/null'
ok "check lists the file" 'grepq "DIFFERS: would be replaced"'
ok "check shows the menu version" 'grepq "card menu 0.3.0"'

# --- install, then restore
setup install
edit0
mkdir -p "$C/mib2cfg/skin0/Data/x"; printf 'gca-new' > "$C/mib2cfg/skin0/Data/x/0.gca"
run install
ok "install exits 0" '[ $RC -eq 0 ]'
ok "install replaced images.mcf" 'cmp -s $C/mib2cfg/skin0/images.mcf $U/Resources/skin0/images.mcf'
ok "install replaced the gca" '[ "$(cat $U/Resources/skin0/Data/x/0.gca)" = gca-new ]'
ok "backup is the original" '[ "$(cat $C/mib2cfg/backup/skin0/Data/x/0.gca)" = gca-orig ]'
ok "backup is read only" '[ ! -w $C/mib2cfg/backup/skin0/images.mcf ]'
ok "no .part left" '[ -z "$(find $C/mib2cfg/backup -name "*.part")" ]'
ok "MANIFEST has both files" '[ "$(grep -c "^skin0/" $C/mib2cfg/backup/MANIFEST)" = 2 ]'
ok "card id and unit fingerprint written" '[ -s $C/mib2cfg/backup/card.id ] && [ -s $C/mib2cfg/backup/unit.txt ]'
ok "unit marker names this card" 'grep -q "^card $(cat $C/mib2cfg/backup/card.id)" $U/esd/mib2cfg.state'
ok "unit read only again" '! isrw'
ok "ok marker written" '[ -f $T/tmp/mib2cfg.ok ]'
ok "lock released" '[ ! -d $T/tmp/mib2cfg.lock ]'
ok "no reboot without the word" '[ ! -f $T/shutdown-called ]'
ok "no leftover copies on the unit" '[ -z "$(find $U -name "*.mib2cfg-new*")" ]'
run install
ok "second install before a reboot is refused" '[ $RC -eq 1 ] && grepq "has not rebooted"'
reboot_sim
run install
ok "install again after reboot: nothing to do (3)" '[ $RC -eq 3 ]'
run restore
ok "restore exits 0" '[ $RC -eq 0 ]'
ok "restore brought the original back" '[ "$(cat $U/Resources/skin0/Data/x/0.gca)" = gca-orig ]'
ok "each run has its own log" '[ "$(ls $C/mib2cfg/logs | grep -c "\.log$")" = 4 ]'

# --- install reboot
setup reboot
edit0
run install reboot
ok "install reboot: clean run reboots" '[ $RC -eq 0 ] && [ -f $T/shutdown-called ]'
setup rebootnothing
mcf "$(pad orig0)" > "$C/mib2cfg/skin0/images.mcf"
run install reboot
ok "install reboot with nothing to change: no reboot" '[ $RC -eq 3 ] && [ ! -f $T/shutdown-called ]'
setup rebootfail
: > "$C/mib2cfg/skin0/images.mcf"
run install reboot
ok "install reboot with a refused file: no reboot, exit 2" '[ $RC -eq 2 ] && [ ! -f $T/shutdown-called ] && [ ! -f $T/tmp/mib2cfg.ok ]'
setup rebootold
edit0
SCRIPT=/repo/tests/fixtures/mib2cfg-0.2.1.sh run install reboot
ok "an old card script ignores reboot" '[ ! -f $T/shutdown-called ]'
SCRIPT=""

# --- validation
setup validate
mcf "x" > "$C/mib2cfg/skin0/images.mcf"
run install
ok "much smaller images.mcf refused" '[ $RC -eq 2 ] && grepq "less than half"'
setup header
printf 'XXXXXXXXXXXX%s' "$(pad new0)" > "$C/mib2cfg/skin0/images.mcf"
run install
ok "wrong header refused" 'grepq "header differs"'
setup wrongskin
mkdir -p "$C/mib2cfg/skin1"
cp "$U/Resources/skin0/images.mcf" "$C/mib2cfg/skin1/images.mcf"
run install
ok "skin0's file in skin1 refused" 'grepq "same file as skin0"'
ok "refused file left the unit alone" '! cmp -s $U/Resources/skin0/images.mcf $U/Resources/skin1/images.mcf'

# --- names, mode file, leftovers
setup space
edit0
chmod -R u+w "$U"; printf 'q' > "$U/Resources/skin0/Data/x/a b.gca"; chmod -R a-w "$U"
printf 'r' > "$C/mib2cfg/skin0/Data/x/a b.gca" 2>/dev/null || { mkdir -p "$C/mib2cfg/skin0/Data/x"; printf 'r' > "$C/mib2cfg/skin0/Data/x/a b.gca"; }
run install
ok "a name with a space is skipped whole" 'grepq "SKIP   Data/x/a b.gca (a space"'
ok "the other file still installed" '[ $RC -eq 0 ]'
setup modefile
edit0
printf '\357\273\277Install\r\n' > "$C/mib2cfg/mode"
run
ok "BOM + CRLF mode file read as install" 'grepq ": install"'
ok "Tools route sets restore next" '[ "$(cat $C/mib2cfg/mode)" = restore ]'
setup emptymode
: > "$C/mib2cfg/mode"
run
ok "empty mode file means check" '[ $RC -eq 0 ] && grepq ": check"'
setup leftovers
edit0
chmod -R u+w "$U"; printf 'x' > "$U/Resources/skin0/images.mcf.mib2cfg-new.123"; printf 'x' > "$U/esd/scripts/mib2cfg_x.sh.mib2cfg-new"; chmod -R a-w "$U"
run install
ok "leftovers removed, also in the menu folder" '[ -z "$(find $U -name "*.mib2cfg-new*")" ]'

# --- refusals before copying
setup twocards
edit0
mkdir -p "$T/media/mp001/mib2cfg" && cp "$C/mib2cfg/mib2cfg.sh" "$T/media/mp001/mib2cfg/"
run install
ok "two cards: install refused" '[ $RC -eq 1 ] && grepq "2 cards"'
ok "two cards: unit untouched" '! cmp -s $C/mib2cfg/skin0/images.mcf $U/Resources/skin0/images.mcf'
run check
ok "two cards: check still runs and warns" '[ $RC -eq 0 ] && grepq "WARNING: 2 cards"'
setup rocard
edit0
chmod -R a-w "$C/mib2cfg"
run install
ok "read-only card: stops before the unit" '[ $RC -eq 1 ] && grepq "read only or full" && ! grep -q remount $T/mount.log 2>/dev/null'
chmod -R u+w "$C/mib2cfg"
setup mountfail
edit0
touch "$T/fail-rw"
run install
ok "mount rw failure: error, nothing replaced, no reboot" '[ $RC -eq 2 ] && ! cmp -s $C/mib2cfg/skin0/images.mcf $U/Resources/skin0/images.mcf && [ ! -f $T/tmp/mib2cfg.ok ]'
setup rofail
edit0
touch "$T/fail-ro"
run install reboot
ok "read-only remount failure: error and no reboot" '[ $RC -eq 2 ] && grepq "still writable" && [ ! -f $T/shutdown-called ]'
setup rootdev
edit0
ROOTDEV=/dev/hd9t9 run install
ok "unexpected root device: nothing written" '[ $RC -eq 2 ] && grepq "is not mounted from /dev/hd0t177" && ! grep -q remount $T/mount.log 2>/dev/null'
setup lowspace
edit0
echo 1000 > "$T/unitfree"
run install
ok "low space: stopped" '[ $RC -eq 1 ] && grepq "NOT ENOUGH SPACE"'
ok "low space: read only" '! isrw'
setup locked
edit0
mkdir "$T/tmp/mib2cfg.lock"
run install
ok "busy lock: refused and the lock kept" '[ $RC -eq 1 ] && [ -d $T/tmp/mib2cfg.lock ]'

# --- backups: partial, wrong card, other firmware, damaged
setup partial
edit0
mkdir -p "$C/mib2cfg/backup/skin0"; printf 'cut' > "$C/mib2cfg/backup/skin0/images.mcf.part"
run install
ok "partial backup ignored and redone" '[ $RC -eq 0 ] && cmp -s $C/mib2cfg/backup/skin0/images.mcf $T/orig0 && [ ! -f $C/mib2cfg/backup/skin0/images.mcf.part ]'
setup wrongcard
edit0
chmod -R u+w "$U"; printf 'card cOTHER\nfile skin0/images.mcf\n' > "$U/esd/mib2cfg.state"; chmod -R a-w "$U"
run install
ok "unit marker of another card: install refused" '[ $RC -eq 1 ] && grepq "WRONG CARD"'
run restore
ok "unit marker of another card: restore refused" '[ $RC -ne 0 ]'
setup firmware
edit0
run install
reboot_sim
chmod -R u+w "$U"; printf 'firmware-two' > "$U/hmi/tsd.mibstd2.hmi.ifs"; chmod -R a-w "$U"
run restore
ok "other firmware: restore refused" '[ $RC -eq 1 ] && grepq "OTHER FIRMWARE"'
setup damaged
edit0
run install
reboot_sim
f="$C/mib2cfg/backup/skin0/images.mcf"; chmod u+w "$f"; printf 'junk' >> "$f"
run restore
ok "damaged backup not restored" '[ $RC -eq 2 ] && grepq "backup is damaged" && cmp -s $C/mib2cfg/skin0/images.mcf $U/Resources/skin0/images.mcf'
setup restoreextra
edit0
run install
reboot_sim
printf 'x' > "$C/mib2cfg/backup/skin0/new.gca"; printf 'x' > "$C/mib2cfg/backup/skin0/._images.mcf"
run restore
ok "restore never adds files" '[ ! -f $U/Resources/skin0/new.gca ] && [ ! -f $U/Resources/skin0/._images.mcf ]'

# --- menu
setup menu
run menu
ok "menu installs" '[ $RC -eq 0 ] && [ -f $U/esd/mib2cfg.esd ] && [ -x $U/esd/scripts/mib2cfg_install.sh ]'
chmod -R u+w "$U"; printf '#!/bin/ksh\n' > "$U/esd/scripts/mib2cfg_old.sh"; chmod -R a-w "$U"
run menu
ok "menu removes a stale button script" '[ ! -f $U/esd/scripts/mib2cfg_old.sh ]'
chmod -R u+w "$U"; sed -i 's/^# mib2cfg-version .*/# mib2cfg-version 9.0.0/' "$U/esd/mib2cfg.esd"; chmod -R a-w "$U"
run menu
ok "menu refuses a downgrade" '[ $RC -eq 1 ] && grepq "is newer"'
run menu force
ok "menu force downgrades" '[ $RC -eq 0 ] && grep -q "0.3.0" $U/esd/mib2cfg.esd'
printf '#!/bin/ksh\r\necho x\r\n' > "$C/mib2cfg/greenmenu/scripts/mib2cfg_check.sh"
run menu
ok "menu refuses CRLF files" '[ $RC -eq 1 ] && grepq "Windows line endings"'
setup removemenu
edit0
run install
run removemenu
ok "removemenu removes the screen but keeps the marker" '[ ! -f $U/esd/mib2cfg.esd ] && [ -f $U/esd/mib2cfg.state ]'

# --- logs
setup logs
mkdir -p "$C/mib2cfg/logs"; : > "$C/mib2cfg/logs/0007-install.log"; : > "$C/mib2cfg/logs/abcd-x.log"; : > "$C/mib2cfg/logs/0012-y.txt"
run check
ok "log number follows the highest NNNN log" '[ -f $C/mib2cfg/logs/0008-check.log ]'
( run check ) & ( run check ) & wait
ok "two runs at once get two logs" '[ "$(ls $C/mib2cfg/logs | grep -c check.log)" = 3 ]'

echo "$SH: $PASS passed, $FAILS failed"
[ $FAILS -eq 0 ]
