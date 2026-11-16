# mib2c-toolbox

Installs skin files edited with the [MIB2 Configurator](https://mib2c.pqisa.eu) on a **VW MIB2 Standard (PQ/ZR)**
head unit, and puts the unit's original files back.

Unlike the toolbox's Customization › Skins, it also installs the car data files under `Data/` (ambient light points,
touch areas), so moved zones and points arrive too. Besides `skin0` it installs the theme skins `skin1` … `skin6`
(mainly `images.mcf`, sometimes `images.res`). It keeps a backup of every file it replaces.

It adds its own screen to the Green Engineering Menu, **Main › MIB2 Configurator**:

- **Check (read only):** shows what would change.
- **Install edited files.**
- **Restore original files.**
- **Reboot unit.**
- **Remove this menu from the unit.**

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
```

The release zip has `mib2cfg/skin0` … `mib2cfg/skin6` empty, ready for your files; when you copy from the
repository, create them yourself (only the ones you use are needed). Empty skin folders are skipped. The installer
writes these:

```
mib2cfg/backup/skin0/ …     the unit's own files, saved before they are first replaced, one folder per skin
  backup/skin6/               (skin0 … skin6). Keep them, and copy them to a PC after the first install!
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

The menu install adds only six files named `mib2cfg*` to the unit's green menu folder and changes nothing else.
From then on the screen works by itself, from any card or stick that has the `mib2cfg` folder.

## Installing edited files

1. Save your edits in the MIB2 Configurator. Copy only the files you changed into `mib2cfg/skin0` (or
   `mib2cfg/skin1` … `skin6` for a theme skin), at the same path as in the skin folder.
2. Optional: Green menu › MIB2 Configurator › **Check (read only)** shows what would change.
3. Press **Install edited files**. It shows a progress bar; wait for **INSTALL FINISHED**.
4. Press **Reboot unit**, and look at the screens only after the reboot.

Don't switch off or reboot while it copies. Even if that happens, the unit's file stays whole: every file is
copied next to the original, checked, and only then swapped in.

If your unit already runs an edited file, put the factory original from a dump into `mib2cfg/backup/skin0` (or
`backup/skinN` for a theme skin) before the first install. Otherwise Restore would bring back the edited file.

## Going back

Press **Restore original files**, wait for **RESTORE FINISHED**, then press **Reboot unit**. It copies the files
from `mib2cfg/backup/skin0` … `skin6` back, so use the card that holds the backup folder from your first install.

**Remove this menu from the unit** deletes the screen's six files again.

## How it works

- **Install** goes through `mib2cfg/skin0` … `skin6` in turn and replaces only files that already exist in the
  unit's matching skin (nothing is added or deleted), and only when they differ.
- **Every new file is checked first** and refused (the unit's file stays) when it is empty, when an `images.mcf`,
  `images.res` or `.boot` file doesn't start like the unit's file, when an `images.mcf` or `.boot` file is less
  than half or more than double the unit's size, or when it is byte for byte another skin's file on the unit
  (dropped into the wrong `skinN` folder).
- **Backups:** before a file is first replaced, its original is copied to `mib2cfg/backup/skinN` as a `.part`
  file, compared, renamed, flushed to the card, made read only and recorded in `MANIFEST`. A power cut leaves at
  most a `.part`, which is ignored and redone. A backup is never overwritten, so it stays the unit's own file
  however often you install.
- **One card per unit:** the unit keeps a small marker, `mib2cfg.state` next to the green menu files, with the id
  of the card that holds its originals and the files backed up. A different card is refused ("WRONG CARD"), and so
  is a file whose original the marker says was backed up but this card doesn't have: otherwise an edited file
  could become the "original". With more than one card or stick holding `mib2cfg` in the unit, nothing is
  written. Backups made on other firmware are refused too ("OTHER FIRMWARE"): keep that backup folder on a PC and
  start with an empty one.
- **Restore** copies every backed-up file back, after checking it against `MANIFEST`, and only over files that
  exist on the unit (it never adds files). The backup stays on the card.
- Each file is copied next to its target as `<name>.mib2cfg-new.<run>`, compared, renamed over the target and
  compared again. The system partition is remounted read-write only for the copy, after checking that `/` is
  `/dev/hd0t177` and that it really became writable, and read-only again afterwards (also when the run stops
  early); a partition that stays writable is reported as an error.
- **Space:** before copying anything, install and restore work out what they need and stop with "NOT ENOUGH
  SPACE" (nothing copied) when the unit or, for the backups, the card is short. The HMI keeps a replaced
  `images.mcf` open until the reboot, so the unit needs room for every new file plus the largest once more, plus
  16 MB.
- **One run at a time, then reboot:** a second button press while a run is busy is refused, and so is Reboot
  unit. After an install or restore that replaced files, the next install or restore waits for a reboot.
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
  `install`, `restore`, `menu` or `removemenu`. When started this way, the installer sets the next mode itself:
  after an install the next run restores, and after a clean restore or menu change it only checks. The menu
  buttons always do what they say and leave `mib2cfg/mode` alone.
- **Reboot when finished:** `mib2cfg.sh install reboot` (or `restore reboot`) restarts the unit at the end, but only
  when files were copied, nothing failed and the partition is read only again. Exit codes: 0 changed cleanly,
  1 stopped before copying, 2 some files failed, 3 nothing needed changing.

## If the unit doesn't start properly after an install

The checks above catch the usual mistakes, but a file the HMI can't read can still stop it from starting, and then
the green menu (and with it Restore) can't be reached either. Before your first install:

- keep a full dump of the unit, and copy `mib2cfg/backup` to a PC after the first install;
- know your way back without the HMI (the unit's serial console, or a firmware update from SD), or have someone
  who does.

## Testing off the unit

`tests/run.sh` runs the installer against a fake unit and card in Docker (mksh, the closest relative of the
unit's PD KSH; `tests/run.sh busybox` uses busybox sh). The cases cover install, restore, reboot rules, the file
checks, names with spaces, mode files with CR/BOM, two cards, a read-only card, mount failures, low space, the
lock, leftovers, partial / damaged backups, another card or firmware, the menu install and the log numbering.
Check on the unit then confirms the pdksh details (`print`, `typeset -Z`, `trap EXIT`, `awk -v`, cmp's format).

## License

[MIT](LICENSE) © 2026 Tomas Slekys
