# Logi Options+ Profiles

Documentation of the **on-disk format** behind Logi Options+ profiles — the files that back Actions Ring and the MX Creative Console — plus notes on local snapshots and profile diagnostics.

Logitech supports importing and exporting profiles as `.lp4` / `.lp5` packages, and that is the right way to move a profile between machines. What is not documented anywhere is what those profiles actually *are* on disk: the JSON structure, where it lives, how actions reference each other, and what Options+ quietly keeps in the background. That is the gap this repository fills.

---

## Quick answers

**Where are Logi Options+ profiles stored on Windows?**

```
%LOCALAPPDATA%\Logi\LogiPluginService\Applications\<DeviceType>\<application>\Profiles\<GUID>\
```

Each profile is a self-contained folder of about 60 KB. Full breakdown in [docs/file-locations.md](docs/file-locations.md).

**What is the difference between `.lp4` and `.lplug4`?**

`.lp4` / `.lp5` carry a **profile**; `.lplug4` / `.lplug5` carry a **plugin**. The registry ProgIDs are literally `Profile` and `Plugin`, and they route to different handler verbs. Details and the one inconsistency worth knowing in [docs/package-formats.md](docs/package-formats.md).

**Does Logi Options+ back up my profiles?**

It writes periodic ZIP snapshots of the whole profile tree, without mentioning it in the UI:

```
%LOCALAPPDATA%\Logi\LogiPluginService\Applications.Backups\backup_YYYY-MM-DD_HH-MM-SS.zip
```

This is a convenience that happens to exist, not a documented feature with a support commitment — and it is a different thing from exporting a single profile. See [docs/backups.md](docs/backups.md).

**Can I install a profile by copying a folder?**

Yes, and it is tested — a folder placed into `Profiles\` is adopted by Options+ and appears in the UI, with no index to update. Treat it as the recovery path rather than the everyday one: for normal transfers use the supported `.lp4` / `.lp5` export. See [docs/installing-profiles.md](docs/installing-profiles.md).

---

## What is in here

| Path | Contents |
|---|---|
| [`docs/profile-format.md`](docs/profile-format.md) | Anatomy of `ProfileInfo.json` — layout model, control IDs, action references, macro storage |
| [`docs/file-locations.md`](docs/file-locations.md) | Every path Options+ and Logi Plugin Service use: profiles, plugins, logs, backups |
| [`docs/package-formats.md`](docs/package-formats.md) | `.lp4` / `.lp5` vs `.lplug4` / `.lplug5`, and which handler each one invokes |
| [`docs/installing-profiles.md`](docs/installing-profiles.md) | Installing a profile folder by hand, with the test results behind the procedure |
| [`docs/backups.md`](docs/backups.md) | The undocumented automatic snapshots, and how to read one |
| [`docs/device-types.md`](docs/device-types.md) | `Loupedeck70/71/72` → real device names, from the shipped SDK enum |
| [`profiles/`](profiles) | Shareable profiles, anonymised before publication |
| [`scripts/`](scripts) | Tested `verify.ps1` validation, staged full-tree `anonymize.ps1` publication prep, and integrity-checked `snapshot.ps1` backup |

---

## Why this exists

1. **Understanding the format.** Nobody had written it down. Everything here was reconstructed by reading the files and the shipped assemblies of a legitimately installed copy.
2. **Local snapshots and recovery.** Knowing where profiles live, and that Options+ keeps its own ZIP snapshots, turns "I lost my setup" into a solvable problem.
3. **Diagnostics.** A profile can install perfectly and still be half-dead if it references plugins the machine does not have. That failure mode is invisible in the UI.

---

## Verification status

This project separates what was observed directly from what is inference. Nothing below comes from model memory.

**Sample:** one Windows 11 machine, **Logi Options+ 2.5.926888**, **Logi Plugin Service 6.4.0.3079**, August 2026. **26 profiles** across three device types (`Loupedeck70` ×7, `Loupedeck71` ×7, `Loupedeck72` ×12), a mix of vendor defaults and user-created ones. Statements below describe that sample, not every profile that can exist.

**Verified by direct observation:**

- Profile folder layout and file inventory
- `ProfileInfo.json` structure: layout modes, workspaces, press/rotate pages, `controlId` 0–7
- Where macros live: in the 7 sampled profiles that contain `ApplicationProfileMacroCommand` entries, the definitions — including keyboard parameters — are stored **inline in the profile**, not in the separate `macros.db`
- No checksums, hashes, signatures, or device serial numbers were found **in any sampled profile**
- **Absolute paths do occur.** Any action that opens a file, folder, or application stores a full path — `C:\Program Files\...`, user directories, other drives. Profiles without such actions contain none, which is what made an earlier version of this document wrongly claim they never appear. This matters twice: for portability, and because those paths describe the author's machine
- `Applications.Backups` ZIP snapshots exist and contain every profile for every device type
- `DeviceType` enum values, read from the shipped `PluginApi.dll`
- Registry associations: `.lp4` / `.lp5` → ProgID `Profile` → `install-package`; `.lplug4` → ProgID `Plugin` → `install-plugin`; `.lplug5` → ProgID `Plugin` → `install-package`
- `LoupedeckService.dll` exposes `ApplicationProfileImporter.ImportProfile` and `TryParseLayoutFile` (which parses XML). **Which on-disk format those correspond to is not established** — do not assume they handle `.lp*`
- A profile folder copied into `Profiles\` is adopted by Options+ and shown in the UI; the running service neither deletes nor rewrites it, it survives a service restart, and every pre-existing profile was SHA256-identical before and after
- `ApplicationInfo.json` records only `defaultProfileName`, not a profile list — profiles are discovered by directory scan
- `LogiPluginService` and `LogiPluginServiceExt` restart themselves after being stopped

**Explicitly not established:**

- **Profiles are not universally self-contained.** 21 of the 26 sampled profiles reference actions outside `@Generic` — plugin-provided or native actions. Those are external dependencies: the profile will install and the slot will be dead if the dependency is missing
- Where the export command sits in the current Actions Ring UI, and what a `.lp4` / `.lp5` package contains internally
- Whether a profile or package moves cleanly to a **different** machine. Nothing here has crossed a machine boundary
- Whether Smart Actions are stored in this format at all. A profile may *reference* a Smart Action; that is not the same as the format holding one, and their storage has not been examined
- Whether `install-package` and `install-plugin` are interchangeable, given the `.lplug5` association
- Whether the format is stable across Options+ releases

Corrections and test reports are welcome — open an issue.

---

## Roadmap

- [x] Document the profile format, file locations, backup mechanism, and device types
- [x] Verify that a profile folder copied into place is adopted by Options+
- [x] Establish the `lp*` / `lplug*` split from registry associations
- [ ] Document the supported export/import path in the current UI, and what a `.lp*` package holds
- [x] `verify.ps1` — validate a profile folder and report missing plugin dependencies
- [x] `snapshot.ps1` — timestamped local copy of the profile tree, hash-verified
- [ ] Verify a profile transferred between two different machines
- [x] `anonymize.ps1` — strip machine-specific shortcuts, keep folder containers
- [x] First anonymised profile published

---

## Contributing

Useful contributions, roughly in order of value:

- **Test reports** on the open questions above, on other Options+ versions, or on other device types
- **Corrections** — an issue with the observed output beats a description
- **Profiles** — see [`profiles/README.md`](profiles/README.md). Profiles embed application names, paths, and account names; build a neutral one rather than scrubbing a personal one

---

## Scope and safety

Everything here was obtained by inspecting a legally installed copy of Logi Options+ on the author's own machine, for interoperability purposes. This repository contains **no vendor code, no decompiled binaries, and no circumvention of any licensing or protection mechanism** — only a description of an on-disk file format and paths.

Editing files under `%LOCALAPPDATA%` can break your Options+ configuration. Take a copy first — or use the built-in snapshots described in [docs/backups.md](docs/backups.md).

---

## Disclaimer

Not affiliated with, endorsed by, or supported by Logitech. Logitech, Logi Options+, MX Master, and MX Creative Console are trademarks of their respective owners.

Licensed under the [MIT License](LICENSE).
