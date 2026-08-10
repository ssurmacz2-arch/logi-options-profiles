# Scripts

PowerShell helpers for inspecting and snapshotting profiles.

## Scope

These deliberately do **not** reimplement profile transfer. Logitech ships that: `.lp4` / `.lp5` packages install through `LogiPluginServiceTool.exe install-package` (see [package-formats.md](../docs/package-formats.md)). Writing a competing installer would add risk without adding capability.

What is genuinely missing is everything *around* a profile — validating one, understanding what it depends on, and keeping local history.

## Planned

| Script | Purpose |
|---|---|
| `verify.ps1` | Validate a profile folder: GUID consistency between folder name, the `name` field, and icon filenames; well-formed JSON; **report which actions come from plugins and whether those plugins are installed** |
| `snapshot.ps1` | Timestamped copy of the profile tree, with a hash manifest so drift is visible |

`verify.ps1` comes first. The failure mode it catches is real and invisible: a profile referencing a plugin the machine does not have installs cleanly and leaves dead slots. In a 26-profile sample, 21 referenced actions outside `@Generic`, so the dependency case is the common one, not the exception.

## Conventions

- Windows PowerShell 5.1 and PowerShell 7 both supported; no external modules
- Read-only by default; anything that writes takes an explicit switch
- Nothing stops or restarts Options+ services unless asked to
