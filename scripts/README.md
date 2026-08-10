# Scripts

PowerShell helpers for getting profiles in and out of a machine.

## Status

The question that blocked these — whether Options+ adopts a profile folder placed on disk by something other than itself — has been [answered: it does](../docs/installing-profiles.md). The manual procedure works, so the scripts are now just automation of known-good steps rather than a bet on untested behaviour.

## Planned

| Script | Purpose |
|---|---|
| `export.ps1` | Copy profiles from the live Options+ location into this repository, preserving structure |
| `install.ps1` | Place a profile from this repository onto a machine, stopping and restarting the plugin service around the copy |
| `verify.ps1` | Sanity-check a profile folder: GUID consistency between folder name, `name` field, and icon filenames; presence of referenced macros; no absolute paths |

`verify.ps1` is the one worth writing first regardless of the open question — it validates the format rules described in [profile-format.md](../docs/profile-format.md) and needs nothing from Options+ to be useful.

## Conventions

- Windows PowerShell 5.1 and PowerShell 7 both supported; no external modules
- Nothing runs destructively without an explicit switch
- Every script that touches the live Options+ location takes a copy first
