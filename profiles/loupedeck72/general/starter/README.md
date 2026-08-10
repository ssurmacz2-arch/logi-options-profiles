# General starter (Actions Ring)

A general-purpose Actions Ring profile, published as a scaffold rather than a finished setup: the folder structure is there, the personal contents are not.

Built for `@_defaultwin` — the profile Options+ falls back to when no application-specific one matches.

## What you get

Four folders on the ring, each a container you fill yourself:

| Folder | Intent |
|---|---|
| **Files** | Empty. Meant for shortcuts to the directories you open all day |
| **System Monitor** | FPS, CPU, GPU, and memory readouts |
| **Pomo** | Focus timer with dial control |
| **Audio** | Input and output device cycling, plus playback control |

The remaining slots hold a paste utility and are otherwise free.

**Files is deliberately empty.** Shortcuts store absolute paths, so anything in there would be a map of the author's drives and useless on yours. The container stays because it is the useful part — the structure — and you add the destinations.

## Requirements

The monitoring, timer, and audio folders come from Marketplace plugins. Without them the profile still installs, and those slots do nothing:

- `PCMonitor` — system readouts
- `PomoDeck` — focus timer
- `AudioSwitcher` — device cycling
- `Spotify` — playback control
- `WindowsPowerToys` — paste utility

Only the keyboard shortcuts and the folder structure work with no plugins at all. Run [`scripts/verify.ps1`](../../../../scripts/verify.ps1) against the profile to see what your machine is missing before installing.

## Installing

Copy the GUID-named directory into:

```
%LOCALAPPDATA%\Logi\LogiPluginService\Applications\Loupedeck72\@_defaultwin\Profiles\
```

Then restart the plugin service — both processes come back on their own:

```powershell
Stop-Process -Name LogiPluginServiceExt,LogiPluginService -Force
```

Keep the folder name as it is. Options+ matches it against the `name` field inside `ProfileInfo.json` and ignores the profile if they disagree. Full procedure and failure modes in [docs/installing-profiles.md](../../../../docs/installing-profiles.md).

## What was removed

Produced by [`scripts/anonymize.ps1`](../../../../scripts/anonymize.ps1). Ten path-bearing actions were stripped — five directory shortcuts, one file shortcut, and four application launchers — along with their icons. One slot referencing a plugin the author does not have was cleared. A fresh profile GUID was issued so this does not collide with the source installation.

Built against Logi Options+ 2.5.926888 / Logi Plugin Service 6.4.0.3079, Windows 11.
