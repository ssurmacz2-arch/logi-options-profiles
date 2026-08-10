# Scripts

PowerShell helpers for inspecting and snapshotting profiles.

## Scope

These deliberately do **not** reimplement profile transfer. Logitech ships that: `.lp4` / `.lp5` packages install through `LogiPluginServiceTool.exe install-package` (see [package-formats.md](../docs/package-formats.md)). Writing a competing installer would add risk without adding capability.

What is genuinely missing is everything *around* a profile — validating one, understanding what it depends on, and keeping local history.

## `verify.ps1`

Validates profile folders and reports what they depend on. Read-only — it never writes, moves, or deletes anything, and never touches the Options+ services.

```powershell
.\verify.ps1                      # every profile installed locally
.\verify.ps1 -Path <folder>       # one profile, or a tree to search
.\verify.ps1 -Quiet               # only profiles with findings
.\verify.ps1 -Json                # machine-readable output
```

Exit code is 1 if any profile has an error, 0 otherwise.

**Errors** — the profile will not work:

- `ProfileInfo.json` missing or not valid JSON
- folder name does not match the `name` field, which stops Options+ adopting it
- a macro is referenced but not defined in the profile

**Warnings** — the profile loads but something is off:

- a referenced plugin is not installed, so those slots will silently do nothing
- an absolute path is embedded, which ties the profile to one machine and describes it to anyone reading
- an unrecognised `deviceType`

Run against a real installation of 26 profiles, it found one missing plugin dependency and three profiles carrying absolute paths — including paths to personal project directories that were invisible in the UI.

Tested on Windows PowerShell 5.1 and PowerShell 7.

## Planned

| Script | Purpose |
|---|---|
| `snapshot.ps1` | Timestamped copy of the profile tree, with a hash manifest so drift is visible |

## Conventions

- Windows PowerShell 5.1 and PowerShell 7 both supported; no external modules
- Read-only by default; anything that writes takes an explicit switch
- Nothing stops or restarts Options+ services unless asked to
