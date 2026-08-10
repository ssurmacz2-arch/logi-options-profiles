# Scripts

PowerShell helpers for getting profiles in and out of a machine. Empty for now — the scripts are blocked on one unanswered question.

## Why nothing here yet

`install.ps1` only makes sense if Options+ actually loads a profile folder placed on disk by something other than itself. That is [untested](../README.md#verification-status): the plugin service runs continuously and holds profile state in memory, so it may simply overwrite whatever is put there.

Shipping an installer before confirming that would mean shipping something that silently does nothing. The test comes first.

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
