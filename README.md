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
> Tested so far: the Check mode on a MIB2 STD2 PQ unit (QNX 6.5).

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
  backup/skin6/               (skin0 … skin6). Keep them!
mib2cfg/log.txt             what the last run did
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
  unit's matching skin (nothing is added or deleted), and only when they differ. Before a file is first replaced,
  its original is copied to `mib2cfg/backup/skinN` (the same skin) and compared. That
  copy is never overwritten, so it stays the unit's own file however often you install.
- **Restore** copies every backed-up file back. The backup stays on the card.
- Each file is copied next to its target as `<name>.mib2cfg-new`, compared, renamed over the target and compared
  again. The system partition is remounted read-write only for the copy and read-only again afterwards.
- **Space:** before copying anything, install and restore work out what they need and stop with "NOT ENOUGH
  SPACE" (nothing copied) when the unit or, for the backups, the card is short. The unit needs the largest file
  once more (the copy next to its target) plus whatever the new files are bigger than the old ones, plus 4 MB.
  If the free space can't be read, it goes on with a warning: a copy that doesn't fit is removed and the unit's
  file kept.
- **Nothing left behind:** the only files that stay on the unit are the replaced files themselves (same names,
  same places) and the menu's own files (`mib2cfg.esd` and `scripts/mib2cfg_*.sh` in the green menu folder,
  a few KB; Remove menu deletes them). Backups go to the card, never the unit. A failed copy is deleted at once;
  a `<name>.mib2cfg-new` left by a power cut mid-copy is listed by Check and removed by the next install or
  restore. Check also shows the free space and what an install would need.
- `toolbox.sh` runs the installer with the mode in `mib2cfg/mode`: `check` (the default), `install`, `restore`,
  `menu` or `removemenu`. When started this way, the installer sets the next mode itself: after an install the
  next run restores, and after a clean restore or menu change it only checks. The menu buttons always do what
  they say and leave `mib2cfg/mode` alone.

## License

[MIT](LICENSE) © 2026 Tomas Slekys
