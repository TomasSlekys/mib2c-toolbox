# mib2c-toolbox

Installs skin files and startup screens edited with the [MIB2 Configurator](https://mib2c.pqisa.eu) on a
**VW MIB2 Standard (PQ/ZR)** head unit, and puts the unit's original files back.

Unlike the toolbox's Customization › Skins, it also installs the car data files under `Data/` (ambient light points,
touch areas), so moved zones and points arrive too. Besides `skin0` it installs the theme skins `skin1` … `skin6`
(mainly `images.mcf`, sometimes `images.res`). It keeps a backup of every file it replaces.

It adds its own screen to the Green Engineering Menu, **Main › MIB2 Configurator**:

- **Check (read only):** shows what would change.
- **Install edited files**, and **Install edited files and reboot**.
- **Restore original files**, and **Restore original files and reboot**.
- **Install startup screens**, **Install startup screens and reboot**, **Restore startup screens**.
- **Reboot unit.**
- **Update this menu from the card.**
- **Remove this menu from the unit.**

The "… and reboot" buttons restart the unit only when the run finished cleanly: files were copied, nothing failed
and the system partition is read only again. Otherwise they stop with the message and don't reboot.

> Community tool, not affiliated with Volkswagen. Use it at your own risk and keep your own dump of the unit.
> Only tested on a VW MIB2 STD2 PQ unit with firmware 0480T (QNX 6.5). Other units and firmware versions are untested.

## Download

Get `mib2c-toolbox-vX.Y.Z.zip` from the [latest release](https://github.com/TomasSlekys/mib2c-toolbox/releases/latest)
and unzip it to the **root** of an SD card or USB stick (FAT32).

If you take the files from the repository instead, copy the contents of the `card` folder. Keep Unix line endings
(LF) in the `.sh` and `.esd` files: don't open and save them in Notepad.

## What goes on the SD card or USB stick

```
toolbox.sh                  starts mib2cfg.sh from the toolbox's Tools menu (only for the first run)
mib2cfg/mib2cfg.sh          the installer
mib2cfg/mode                one word; "menu" for the first run
mib2cfg/greenmenu/          the green menu screen and its buttons
mib2cfg/skin0/              YOUR EDITED FILES, at their place in skin0, for example:
                              mib2cfg/skin0/images.mcf
                              mib2cfg/skin0/Data/0204080200/GenericCarAdjuster/AmbianceLight/0.gca
mib2cfg/skin1/ … skin6/     your edited files for the theme skins, at their place in that skin, for example:
                              mib2cfg/skin3/images.mcf
                              mib2cfg/skin1/images.res
mib2cfg/startanim/          YOUR EDITED STARTUP SCREENS: startup_N.boot files, for example
                              mib2cfg/startanim/startup_0.boot
```

The release zip has `mib2cfg/skin0` … `mib2cfg/skin6` and `mib2cfg/startanim` empty, ready for your files; when you copy from the
repository, create them yourself (only the ones you use are needed). Empty skin folders are skipped. The installer
writes these:

```
mib2cfg/backup/skin0/ …     the unit's own files, saved before they are first replaced, one folder per skin
  backup/skin6/               (skin0 … skin6). Keep them, and copy them to a PC after the first install!
mib2cfg/backup/startanim/   the unit's own startup screens, saved the same way
mib2cfg/backup/MANIFEST     size (and checksum) of every backup; restore checks each backup against it
mib2cfg/backup/card.id      this card's id; the unit remembers which card holds its original files
mib2cfg/backup/unit.txt     the unit's firmware fingerprint from when the first backup was made
mib2cfg/logs/0001-check.log one log per run, numbered, never overwritten (send these when something goes wrong)
mib2cfg/log.txt             a copy of the last run's log
```

### Theme skins

On the unit the skins are side by side in `/tsd/hmi/Resources`: `skin0` holds the car data (`Data/`) and its own
`images.mcf`, and `skin1` … `skin6` are the themes, each with its own `images.mcf` (and `images.res` on most of
them; a file the unit's skin doesn't have is skipped). A file in `mib2cfg/skinN` replaces only that
skin's file, so **an edit to a theme skin shows only while that theme is selected**. To change a picture in every
theme, edit it in each theme's `images.mcf`.

## First time: add the menu (once per unit)

1. You need the Green Engineering Menu and a way to run a script from the card, for example olli991's
   MIB STD2 PQ/ZR Toolbox. With the toolbox, put the files above on the root of the toolbox card.
2. Check that `mib2cfg/mode` says `menu`. In the green menu, open Toolbox › Tools › "Run toolbox.sh script from
   the root of the Toolbox drive". Wait for **MENU INSTALL FINISHED**.
3. Close and reopen the green menu. The main list now has a **MIB2 Configurator** screen.

The menu install adds only files named `mib2cfg*` to the unit's green menu folder (the screen and its eleven
button scripts, a few KB) and changes nothing else. From then on the screen works by itself from a card or stick
with the `mib2cfg` folder: for install and restore, always the same card (the one holding the backups, see "One
card per unit" below), and only one such card in the unit at a time.

**After a menu install or update, press Check once** before the first install. Every self-test line says `ok`
or `BAD:`; a needed command that is missing says `BAD: … missing`. If any line says **BAD** or **WARNING**, don't
install: send the newest check log (`mib2cfg/logs/NNNN-check.log` with the highest number). The installer is
tested off the unit with the unit's own shell (PD KSH 5.2.14), mksh and busybox sh, and Check confirms the unit's
commands behave the same.

## Updating the menu

When a newer release adds or changes buttons, put the new files on the card and press **Update this menu from
the card**, then close and reopen the green menu. It checks the menu files first (Unix line endings, the
`#!/bin/ksh` line, the screen line), installs the button scripts before the screen, removes our button scripts the
card no longer has, and refuses to put an older menu over a newer one. Check shows both versions.

A unit with a menu older than 0.4.0 doesn't have this button yet: install the menu once more the first-time way
(`mib2cfg/mode` = `menu`, Toolbox › Tools › Run toolbox.sh). From then on the button does it.

## Installing edited files

1. Save your edits in the MIB2 Configurator. Copy only the files you changed into `mib2cfg/skin0` (or
   `mib2cfg/skin1` … `skin6` for a theme skin), at the same path as in the skin folder.
2. Optional: Green menu › MIB2 Configurator › **Check (read only)** shows what would change.
3. Press **Install edited files**. It shows a progress bar; wait for **INSTALL FINISHED**.
4. Press **Reboot unit**, and look at the screens only after the reboot.

Or press **Install edited files and reboot**: the same install, then the unit restarts by itself about 10 seconds
after **INSTALL FINISHED**, but only after a clean run.

Don't switch off or reboot while it copies. Even if that happens, the unit's file stays whole: every file is
copied next to the original, checked, and only then swapped in.

If your unit already runs an edited file, put the factory original from a dump into `mib2cfg/backup/skin0` (or
`backup/skinN` for a theme skin) before the first install. Otherwise Restore would bring back the edited file.
A backup placed by hand is checked before it is trusted (not empty, the same kind of file as the unit's, half to
double its size); if it fails, that file is not installed.

## Going back

Press **Restore original files**, wait for **RESTORE FINISHED**, then press **Reboot unit**. It copies the files
from `mib2cfg/backup/skin0` … `skin6` back, so use the card that holds the backup folder from your first install.

**Remove this menu from the unit** deletes the screen and its button scripts again.

## Startup screens

The unit plays its startup animation from `/tsd/etc/startanim/startup_N.boot`. Edit them in the MIB2 Configurator
(open a folder that holds `skins` and `startanim`), then:

1. Copy the `startup_N.boot` files you changed into `mib2cfg/startanim/` on the card (directly in that folder).
2. Optional: **Check** lists them under "files startup would replace".
3. Press **Install startup screens** (or **Install startup screens and reboot**). Only files that already exist on
   the unit are replaced; other names are skipped. Each new file must start with `SCRT` and be between half and
   double the size of the unit's file.
4. Reboot to see them. **Restore startup screens** puts the unit's own files back from `mib2cfg/backup/startanim`.

Skin and startup backups are separate: Restore original files never touches the startup screens, and Restore
startup screens never touches the skins.

**If the unit's startup screens were changed before** (for example with the MIB STD2 Toolbox's own startup
animations), the backup would save those, not the factory files. Then put the factory `startup_N.boot` files from
a dump into `mib2cfg/backup/startanim/` before the first install.

The startup folder has to be on the system partition the installer makes writable. Check shows it ("startanim's
file system"); if it isn't, the startup buttons stop with "OTHER PARTITION" before anything is written.

A broken startup file could stop the unit before the HMI starts, so the green menu couldn't be reached to restore
it. Read the next section before the first startup install.

## If the unit doesn't start after a startup screen change

The startup screens play before the HMI starts. If a `startup_N.boot` file stops the unit at that point, the
screen stays dark: the green menu, and with it **Restore startup screens**, can't be reached. The only way back
then is a shell on the unit from outside. Prepare it **before** the first startup install.

Items marked **(verify)** are not covered by this toolbox's scripts and haven't been tested here. Check them in
the olli991 MIB STD2 PQ/ZR Toolbox documentation or with the community before you rely on them.

### Before you test

1. **Turn on remote access in the olli991 toolbox:** its telnet service and/or its serial console service.
   (verify: the exact menu path in the toolbox's green menu screens.)
   - **Telnet** needs a USB-to-Ethernet adapter the unit supports, a network cable to a PC, and the unit's IP
     address and login. (verify: which adapters work, the IP, user and password, from the olli991 toolbox docs.)
   - **Serial** needs the unit's debug serial connection and a matching USB-to-serial adapter. (verify: the
     connector and pinout, the voltage level, and the baud rate. Don't guess them: a wrong connection can damage
     the unit.)
2. **Test that you can log in while everything still works.** You should get a shell prompt and be able to run,
   for example, `ls /tsd/etc/startanim` and `ls -d /media/mp00*`. If you can't log in now, you won't be able to
   when the screen is dark.
3. **Keep the card with `mib2cfg/backup/`.** After the first startup install, `mib2cfg/backup/startanim/` holds
   the unit's own `startup_N.boot` files, and `mib2cfg/backup/MANIFEST` their sizes and checksums. Copy the
   `backup` folder to a PC too. Without that card, the recovery below has nothing to copy back.
4. **Do the first test with an unchanged repack.** Open the startup screens in the MIB2 Configurator, save one
   without changing it, and install that. If the unit starts normally, the save-and-install path works on your
   unit before any real edit goes in.
5. **Change one file at a time.** Install one `startup_N.boot`, reboot, check it. Then you know which file to
   put back if something goes wrong.

### Recovery with telnet or serial access

Log in while the unit is (re)starting with the card that holds `mib2cfg/backup/startanim` in the unit. Then run
these commands. They are the same steps `mib2cfg.sh startuprestore` takes: it remounts the system partition
`/dev/hd0t177` read-write, copies the backup over the unit's file, checks it, flushes, and remounts read-only.
Replace `startup_0.boot` with the file you changed (or run the `cp` and `cmp` lines for each one).

```sh
# 1. Find the card. mib2cfg.sh looks at /media/mp00* and uses the one with mib2cfg/mib2cfg.sh.
ls -d /media/mp00*/mib2cfg/backup/startanim
CARD=/media/mp000          # set to the folder the line above printed, without /mib2cfg/...
ls -l $CARD/mib2cfg/backup/startanim/
grep startanim $CARD/mib2cfg/backup/MANIFEST   # name, size in bytes, cksum: the sizes must match ls -l

# 2. Check that / is the system partition the installer uses, and that startanim is on it.
mount | grep ' on / '      # must show /dev/hd0t177
df -k /tsd/etc/startanim   # must show the same file system as: df -k /

# 3. Make it writable, put the original back, check it.
mount -t qnx6 -o remount,rw /dev/hd0t177 /
cp $CARD/mib2cfg/backup/startanim/startup_0.boot /tsd/etc/startanim/startup_0.boot
cmp $CARD/mib2cfg/backup/startanim/startup_0.boot /tsd/etc/startanim/startup_0.boot && echo SAME

# 4. Flush, read only again, restart.
sync
mount -t qnx6 -o remount,ro /dev/hd0t177 /
sync
slay tsd.mibstd2.system.swdownload
/bin/shutdown
```

- Run `cmp` until it prints `SAME` before going on. If `cp` or `cmp` fails, don't reboot. Try again, or send the
  output to the community first.
- `mib2cfg.sh` copies to a temporary name and renames it over the target, so a power cut never leaves half a file.
  A plain `cp` over the file doesn't have that protection: keep the ignition on until `sync` has finished.
- The last two lines are what the **Reboot unit** button runs (`/bin/shutdown` restarts the unit).
- (verify) Whether the card is mounted under `/media/mp00*` while the HMI hasn't started. If `ls -d` finds
  nothing, ask the community how to mount the SD card or USB stick from the shell on your firmware.
- (verify) How long after power-on the telnet or serial login is available, and whether a unit stuck at startup
  restarts in a loop.
- Once the unit starts again, press **Check** in the MIB2 Configurator screen. The startup screens should show as
  `backup = the unit's file`.

### Recovery without remote access

If telnet or serial access wasn't set up and tested beforehand, there is no known way back through this toolbox.
The unit may need a workshop (dealer or a specialist with tools for MIB2 units) or a firmware re-flash. Whether a
re-flash from SD card is possible on a unit that doesn't start, and which package it would need, is not known
here (verify with the community). Keep the card with `mib2cfg/backup/` and the logs (`mib2cfg/logs/`): whoever
repairs the unit will need the original `startup_N.boot` files.

## How it works

- **Install** (and **startup**, for `mib2cfg/startanim`) goes through `mib2cfg/skin0` … `skin6` in turn and replaces only files that already exist in the
  unit's matching skin (nothing is added or deleted), and only when they differ.
- **Every new file is checked first** and refused (the unit's file stays) when it is empty, when an `images.mcf`,
  `images.res` or `.boot` file doesn't start like the unit's file (a `.boot` must start with `SCRT`), when an
  `images.mcf` or `.boot` file is less than half or more than double the unit's size, or when it is byte for byte
  another skin's file on the unit (dropped into the wrong `skinN` folder). That last check is skipped when both
  skins had the same original file, so the same edit can go into several themes.
- **Backups:** before a file is first replaced, its original is copied to `mib2cfg/backup/skinN` as a `.part`
  file, compared, renamed, flushed to the card, made read only and recorded in `MANIFEST`. A power cut leaves at
  most a `.part`, which is ignored and redone. A backup is never overwritten, so it stays the unit's own file
  however often you install.
- **One card per unit:** the unit keeps a small marker, `mib2cfg.state` next to the green menu files, with the id
  of the card that holds its originals and the files backed up. A different card is refused ("WRONG CARD"), and so
  is a file whose original the marker says was backed up but this card doesn't have: otherwise an edited file
  could become the "original". With more than one card or stick holding `mib2cfg` in the unit, nothing is
  written. The marker also records the firmware: after a firmware update an old marker is set aside
  (`mib2cfg.state.old`) and the run starts fresh. Backups made on other firmware are refused ("OTHER FIRMWARE")
  because they aren't this firmware's originals: move `mib2cfg/backup` to a PC (keep it) and run again; a new
  backup is made. If the card with the backups is lost, set `mib2cfg/mode` to `forgetcard` and run toolbox.sh
  once: the marker is set aside and the next install backs up the unit's current files as its originals.
- **Restore** copies every backed-up file back, after checking it against `MANIFEST` and checking that it looks
  like the unit's kind of file, and only over files that exist on the unit (it never adds files). The backup stays
  on the card. Restore never waits for a reboot, so a failed install can always be undone at once.
- Each file is copied next to its target as `<name>.mib2cfg-new.<run>`, compared, renamed over the target and
  compared again. The system partition is remounted read-write only for the copy, after checking that `/` is
  `/dev/hd0t177` and that it really became writable, and read-only again afterwards (also when the run stops
  early); a partition that stays writable is reported as an error.
- **Space:** before copying anything, install and restore work out what they need and stop with "NOT ENOUGH
  SPACE" (nothing copied) when the unit or, for the backups, the card is short. The HMI keeps a replaced
  `images.mcf` open until the reboot, so the unit needs room for every new file plus the largest once more, plus
  16 MB.
- **One run at a time, then reboot:** a second button press while a run is busy is refused, and so is Reboot
  unit, also during the 10 seconds before an "… and reboot" restart. The lock (in `/tmp`, cleared by a reboot)
  holds the run's process id, so a lock left by a run that was killed doesn't block anything. After an install
  that replaced files, the next install waits for a reboot; restore doesn't.
- **Logs:** every run writes `mib2cfg/logs/NNNN-<mode>.log` (the next free number; nothing is overwritten) and a
  copy in `log.txt`. A card that can't be written stops the run before the unit is touched.
- **Menu:** the menu install checks the menu files first (Unix line endings, `#!/bin/ksh`, the screen line),
  installs the button scripts and then the screen, removes our button scripts the card no longer has, and refuses
  to put an older menu over a newer one (mode `menu force` does it anyway). Check shows both menu versions.
- **Nothing left behind:** the only files that stay on the unit are the replaced files themselves (same names,
  same places), the menu's own files (`mib2cfg.esd` and `scripts/mib2cfg_*.sh`, a few KB; Remove menu deletes them)
  and the marker `mib2cfg.state` (kept on purpose). Backups and logs go to the card, never the unit. A copy left by a
  power cut mid-copy is listed by Check and removed by the next install, restore or menu run.
- `toolbox.sh` runs the installer with the mode in `mib2cfg/mode`: `check` (the default, also for an empty file),
  `install`, `restore`, `startup`, `startuprestore`, `menu`, `removemenu` or `forgetcard`. When started this way, the installer
  sets the next mode itself: after an install the next run restores (after `startup`: `startuprestore`), and after
  a clean restore or menu change it only checks. The menu
  buttons always do what they say and leave `mib2cfg/mode` alone.
- **Reboot when finished:** `mib2cfg.sh install reboot` (or `restore reboot`, `startup reboot`,
  `startuprestore reboot`; the "… and reboot" buttons) restarts the unit at the end, but only
  when files were copied, nothing failed and the partition is read only again. Exit codes: 0 changed cleanly,
  1 stopped before copying, 2 some files failed, 3 nothing needed changing.

## If the unit doesn't start properly after an install

The checks above catch the usual mistakes, but a file the HMI can't read can still stop it from starting, and then
the green menu (and with it Restore) can't be reached either. Before your first install:

- keep a full dump of the unit, and copy `mib2cfg/backup` to a PC after the first install;
- know your way back without the HMI (the unit's serial console, or a firmware update from SD), or have someone
  who does.

For the startup screens, see "If the unit doesn't start after a startup screen change" above.

## Testing off the unit

`tests/run.sh [mksh|pdksh|busybox]` runs the installer against a fake unit and card in Docker: `pdksh` is the
unit's own shell, PD KSH v5.2.14 (Debian's `pdksh_5.2.14-25`, pinned by URL and sha256 in `tests/Dockerfile`),
`mksh` (the default) its closest maintained relative, `busybox` busybox sh. Every case passes on all three. The cases cover install, restore, reboot rules, the file
checks, names with spaces, mode files with CR/BOM, two cards, a read-only card, mount failures, low space, the
lock, leftovers, partial / damaged backups, another card or firmware, the menu install and update (older menu
updated, downgrade and CRLF refused, every button script present), every "… and reboot" path (reboots only after a
clean, changed run), the startup screens (install, restore, skipped names, wrong header and size refused, leftovers,
another partition, separate backups), restore right after a partly failed install, hand-placed backups (junk
refused, a good one recorded), a firmware update past the stop, forgetcard, the lock held through the reboot wait,
stale and live locks (also for the Reboot unit button), two writing runs at once, a file over 8 MB (the copy with
a progress bar), Check's self-tests and the log numbering.

The x86 pdksh build is the same version as the unit's (QNX, ARM), not the same binary, and the unit's commands
(`cmp`, `df`, `mount`, `head`) are stubs here, so Check on the car still confirms the command details (`awk -v`,
cmp's output format, `head -c`) before the first install.

## License

[MIT](LICENSE) © 2026 Tomas Slekys
