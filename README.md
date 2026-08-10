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

**Can I install a profile by copying a folder?**

Yes. A profile folder placed into the `Profiles\` directory is picked up and appears in the Options+ UI — no index file to update, no import dialog needed. Tested; see [installing a profile by hand](docs/installing-profiles.md).

The format also contains no absolute paths and no per-device serial numbers, and macro definitions are stored inline, so a profile folder is structurally self-contained. Cross-machine transfer is therefore expected to work but has not been tested on a second machine — see [Verification status](#verification-status).

---

## What is in here

| Path | Contents |
|---|---|
| [`docs/profile-format.md`](docs/profile-format.md) | Anatomy of `ProfileInfo.json` — layout model, control IDs, action references, inline macro definitions |
| [`docs/file-locations.md`](docs/file-locations.md) | Every path Options+ and Logi Plugin Service use: profiles, plugins, logs, backups |
| [`docs/backups.md`](docs/backups.md) | The undocumented automatic backup mechanism, and how to read a snapshot |
| [`docs/installing-profiles.md`](docs/installing-profiles.md) | Installing a profile by hand, with the test results behind the procedure |
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
- **A profile folder copied into `Profiles\` is adopted by Options+ and shown in the UI.** The running service neither deletes nor rewrites it, it survives a service restart, and existing profiles are left untouched — confirmed by comparing SHA256 hashes of every `ProfileInfo.json` before and after
- **No index needs updating.** `ApplicationInfo.json` records only `defaultProfileName`, not a profile list; profiles are discovered by scanning the directory
- **`LogiPluginService` and `LogiPluginServiceExt` restart themselves** after being stopped, so an installer does not need to relaunch them

**Not yet verified — treat as open questions:**

- Whether a profile authored on one machine loads correctly on a **different** machine. The install test used a profile cloned locally; nothing has crossed a machine boundary yet
- Whether the Options+ UI exposes any user-facing profile import or export
- What `ApplicationProfileImporter.TryParseLayoutFile` accepts, and whether that XML path is reachable by users
- Whether the format is stable across Options+ releases

Corrections and test reports are welcome — open an issue.

---

## Roadmap

- [x] Document the profile format, file locations, backup mechanism, and device types
- [x] Verify that a profile folder copied into place is adopted by Options+
- [ ] `export.ps1` — collect local profiles into this repository
- [ ] `install.ps1` — place a profile from this repository onto a machine
- [ ] Verify a profile transferred between two different machines
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
