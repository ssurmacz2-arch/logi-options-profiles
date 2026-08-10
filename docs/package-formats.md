# Package formats: `.lp4` / `.lp5` vs `.lplug4` / `.lplug5`

Four similar-looking extensions, two different things. Confusing them leads to the wrong install path.

Read from the Windows registry on a machine with Logi Options+ and Logi Plugin Service 6.4 installed (August 2026).

---

## The associations

| Extension | ProgID | Handler command |
|---|---|---|
| `.lp4` | **`Profile`** | `LogiPluginServiceTool.exe install-package "%1"` |
| `.lp5` | **`Profile`** | `LogiPluginServiceTool.exe install-package "%1"` |
| `.lplug4` | **`Plugin`** | `LogiPluginServiceTool.exe install-plugin "%1"` |
| `.lplug5` | **`Plugin`** | `LogiPluginServiceTool.exe install-package "%1"` |

All four are registered under `HKCU\SOFTWARE\Classes`, each through an intermediate `<ext>_command` key.

**`lp*` carries a profile. `lplug*` carries a plugin.** The ProgID says so outright.

Note the inconsistency in the last row: `.lplug5` is a `Plugin` ProgID but is handed to `install-package`, not `install-plugin`. Whether `install-package` is a newer umbrella verb that handles both kinds, or this is a packaging slip, is **not established** — do not assume the two verbs are interchangeable.

## What this means in practice

A profile has a supported, vendor-provided distribution format. It is not necessary to copy folders around by hand to move a profile between machines, and a `.lp4` / `.lp5` file installs by double-click.

That makes the manual folder procedure in [installing-profiles.md](installing-profiles.md) a **fallback and recovery path**, not the primary one:

- use it when you have a profile folder but no package — for example recovering from an [`Applications.Backups` snapshot](backups.md), which stores folders and not `.lp*` files
- use it when you want to inspect or hand-edit a profile, which the package format does not expose

## Open questions

These need checking in the UI, and reports are welcome:

- Where the export command lives in the current Actions Ring UI, and what extension it produces
- Whether a `.lp4` / `.lp5` package is a container of the same profile folder, or a different representation
- Whether `install-package` accepts both profiles and plugins, given the `.lplug5` association
- What `LogiPluginServiceTool.exe` accepts as arguments — invoking it with `--help` produced no output on the tested build
- Whether a package exported on one machine installs cleanly on another with a different set of plugins

## Related

Logitech's own support documentation covers profile import and export for the MX Creative Console family, which includes Actions Ring. Start there for the supported workflow; this repository documents the on-disk side that the support pages do not.
