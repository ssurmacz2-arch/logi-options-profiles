# Logi Options+ Profiles

Documentation and tooling for **Logi Options+ profiles** — the configuration files behind Actions Ring, MX Creative Console, and Smart Actions on Logitech MX devices.

Logi Options+ has no "export profile" button. Your profiles live in an undocumented JSON format buried in `%LOCALAPPDATA%`, and nobody has written down how it works. This repository does.

---

## Quick answers

**Where are Logi Options+ profiles stored on Windows?**

```
%LOCALAPPDATA%\Logi\LogiPluginService\Applications\<DeviceType>\<application>\Profiles\<GUID>\
```

Each profile is a self-contained folder of about 60 KB. Full breakdown in [docs/file-locations.md](docs/file-locations.md).

**Does Logi Options+ back up my profiles?**

Yes — and it never tells you. Options+ writes periodic ZIP snapshots of every profile for every device to:

```
%LOCALAPPDATA%\Logi\LogiPluginService\Applications.Backups\backup_YYYY-MM-DD_HH-MM-SS.zip
```

Details in [docs/backups.md](docs/backups.md).

**Can I move a profile to another PC?**

The format contains no absolute paths and no per-device serial numbers, and macro definitions are stored inline — so a profile folder is structurally self-contained. See [docs/profile-format.md](docs/profile-format.md) for the anatomy, and [Verification status](#verification-status) for what has and has not been tested.

---

## What is in here

| Path | Contents |
|---|---|
| [`docs/profile-format.md`](docs/profile-format.md) | Anatomy of `ProfileInfo.json` — layout model, control IDs, action references, inline macro definitions |
| [`docs/file-locations.md`](docs/file-locations.md) | Every path Options+ and Logi Plugin Service use: profiles, plugins, logs, backups |
| [`docs/backups.md`](docs/backups.md) | The undocumented automatic backup mechanism, and how to read a snapshot |
| [`docs/device-types.md`](docs/device-types.md) | `Loupedeck70/71/72` → real device names, taken from the official SDK enum |
| `profiles/` | Shareable example profiles (see the folder README) |
| `scripts/` | Export and install helpers |

`profiles/` and `scripts/` are intentionally sparse right now — see [Roadmap](#roadmap).

---

## Why this exists

Three reasons, in order of how much they mattered when starting:

1. **Backup.** Profiles represent real setup work and live in one folder on one machine.
2. **Portability.** Reproducing a setup on another computer currently means rebuilding it by hand, click by click.
3. **Nobody documented the format.** Everything here was reconstructed by reading the files and the shipped assemblies of a legitimately installed copy.

---

## Verification status

This project distinguishes between what was observed directly and what is inference. Nothing below is taken from model memory or vendor documentation unless stated.

**Verified by direct observation** (Windows 11, Options+ with Actions Ring, August 2026):

- Profile folder layout and file inventory
- `ProfileInfo.json` structure: layout modes, workspaces, press/rotate pages, `controlId` 0–7
- Macro definitions (`ApplicationProfileMacroCommand`) are stored **inline in the same file**, including keyboard parameters — a profile does not reference an external macro database
- No checksums, hashes, or signatures anywhere in the profile
- No absolute paths and no device serial numbers in the profile
- `Applications.Backups` ZIP snapshots exist and contain every profile for every device type
- `DeviceType` enum values, read from the shipped `PluginApi.dll`
- `LoupedeckService.dll` exposes `ApplicationProfileImporter.ImportProfile` and `TryParseLayoutFile`; the OS has `.lplug4` and `.lplug5` registered

**Not yet verified — treat as open questions:**

- Whether Options+ picks up a **hand-edited** `ProfileInfo.json`, or overwrites it from in-memory state. The service runs continuously; a safe test requires stopping it first
- Whether the Options+ UI exposes any user-facing profile import
- Whether a profile authored on one machine loads correctly on a different machine
- Whether the format is stable across Options+ releases

Corrections and test reports are welcome — open an issue.

---

## Roadmap

- [x] Document the profile format, file locations, backup mechanism, and device types
- [ ] Verify hand-edited profile loading (blocks everything below)
- [ ] `export.ps1` — collect local profiles into this repository
- [ ] `install.ps1` — place a profile from this repository onto a machine
- [ ] Example profiles, reviewed for privacy before publication
- [ ] Browser-based profile generator (static, no backend)

---

## Contributing

Useful contributions, roughly in order of value:

- **Test reports** — especially the open questions above, and results on other Options+ versions or device types
- **Corrections** — if something here is wrong, an issue with the observed output beats a description
- **Profiles** — see [`profiles/README.md`](profiles/README.md) for the privacy checklist. Profiles can embed application names, file paths, and account names; scrub before submitting

---

## Scope and safety

Everything documented here was obtained by inspecting a legally installed copy of Logi Options+ on the author's own machine, for interoperability purposes. This repository contains **no vendor code, no decompiled binaries, and no circumvention of any licensing or protection mechanism** — only a description of an on-disk file format and paths.

Editing files under `%LOCALAPPDATA%` can break your Options+ configuration. Take a copy of the folder — or use the built-in snapshots described in [docs/backups.md](docs/backups.md) — before changing anything.

---

## Disclaimer

Not affiliated with, endorsed by, or supported by Logitech. Logitech, Logi Options+, MX Master, and MX Creative Console are trademarks of their respective owners.

Licensed under the [MIT License](LICENSE).
