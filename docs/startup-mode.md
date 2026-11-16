# Design note: the startup screens mode (built in 0.4.0)

The planned `startup` / `startuprestore` modes install and restore the unit's startup animations,
`/tsd/etc/startanim/startup_N.boot`, from `mib2cfg/startanim/` on the card. Points from the 2026-11 reviews to
build in:

- **Modes are letters only** (`lower()` drops everything else): `startup`, `startuprestore`, and the Tools route's
  next mode after `startup` is `startuprestore`. Add both to the mode check and to the `WHAT` names.
- **Backups in `backup/startanim/`**, made like the skin backups (`.part`, compare, rename, sync, read only,
  MANIFEST entry `startanim/<name>`). Skin restore and startup restore never cross.
- **The "original" may already be custom:** olli991's toolbox can install startup screens too, so the unit's file
  may not be the factory one. Check shows each file's size; if the toolbox's own startanim backup is on the card,
  compare with it; let the user put a factory file in `backup/startanim/` before the first install.
- **A bad `.boot` may stop the unit before the HMI starts** (the boot animation runs first). `invalid()` already
  refuses an empty file, a different header (`SCRT`) and a size outside half to double; consider exact picture
  counts read from the header once the format is confirmed on the unit.
- **Partition:** confirm with Check (`df -k /tsd/etc/startanim`, `mount`) that `/tsd/etc/startanim` is on
  `/dev/hd0t177` before relying on the same remount; use `freekb "$STARTANIM"` for its space check.
- **Plumbing:** a `usestart()` beside `useskin()` (ROOT=$STARTANIM, SRC=$CFG/startanim, BAK=$BAKROOT/startanim);
  `leftovers()` already searches `$STARTANIM`; the marker records `file startanim/<name>`.
- **Reboot:** `startup reboot` reboots only after a clean run, like install.

## Status in 0.4.0

Built as described: modes `startup` / `startuprestore` (plus `reboot`), `usestart()` / `useset()`, backups in
`backup/startanim/` with MANIFEST entries and marker lines `file startanim/<name>`, only existing `startup_*.boot`
files directly in the folder, the `SCRT` header check (when `head -c` works on the unit; Check says) and the
half-to-double size check, leftovers in `/tsd/etc/startanim`, `freekb "$STARTANIM"`, and a stop ("OTHER
PARTITION") when df shows the folder on another file system than `/`. Still open:

- **Picture counts:** a stricter check against the unit file's picture count, once the format is confirmed on the
  unit.
- **The toolbox's own backup:** the installer doesn't look for olli991's startanim backup on the card; the README
  tells the user to supply factory files instead.
- **The `.expect` sidecar** (expected sizes written by the web app) isn't read yet.
