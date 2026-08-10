# The Logi Options+ profile format

Reconstructed by inspecting profiles on disk and the assemblies shipped with Logi Options+ and Logi Plugin Service. Observed on Windows 11, August 2026. See [verification status](../README.md#verification-status) before relying on any of this.

---

## A profile is a folder

A single profile is a directory of roughly 60 KB:

```
Profiles/<PROFILE_GUID>/
├── ProfileInfo.json          # everything functional lives here
├── ApplicationIcon.png
├── metadata/
│   └── ProfilePreview.json
├── ActionIcons/
│   └── $@Generic___@Macro___<GUID>.ict
└── ActionImages/
    └── $@Generic___@Macro___<GUID>.png
```

`ProfileInfo.json` is the profile. The other files are presentation: icons and rendered button images, named after the action they belong to.

There are **no checksums, hashes, or signatures** anywhere in the profile. Nothing cryptographically binds the JSON to its icons or to the machine.

---

## Top-level structure

```jsonc
{
  "$type": "Loupedeck.Service.ApplicationProfile, LoupedeckService",
  "name": "A1B2C3D4E5F6...",         // GUID, matches the folder name
  "profileFlags": "None",
  "displayName": "My Profile",       // shown in the Options+ UI
  "description": null,
  "deviceType": "Loupedeck72",       // see docs/device-types.md
  "applicationName": "tradingview",  // lowercase process/application key
  "nativePluginName": null,
  "hasNativePlugin": false,
  "additionalNativePluginNames": ["DefaultWin"],
  "lastModifiedTimeUtc": "2026-07-01T09:54:24.0916483Z",
  "profileSettings": { "$type": "Loupedeck.DictionaryNoCase`1[[System.String, ...]], PluginApi" },
  "layout": { /* see below */ }
}
```

The `$type` fields are .NET type discriminators — the file is serialized object graph, not a hand-designed schema. Preserve them exactly when editing; the deserializer uses them to pick a class.

Note the naming heritage: Logitech acquired Loupedeck, and the whole plugin and profile stack still carries `Loupedeck` type names.

---

## The layout model

Four nested levels, from outside in:

```
layout
└── layoutModes[]          — named modes, e.g. "main"
    └── workspaces[]       — "Workspace 1", ...
        ├── pressPages[]   — pages of press actions
        └── rotatePages[]  — pages of rotate/scroll actions
            └── controls[] — the individual buttons
```

A control:

```jsonc
{
  "$type": "Loupedeck.Service.Devices.Loupedeck7Devices.ProfileLayoutControl7, LoupedeckService",
  "controlId": 0,
  "pressAction": "$@Generic___@Macro___52307D44BC1548C59BE28C8197C79915",
  "rotateAction": null
}
```

**`controlId` runs 0–7.** That is the eight Actions Ring slots. Press and rotate are separate pages over the same control IDs, which is why a ring button can carry both a click action and a scroll action.

An empty slot has `pressAction` set to an empty string or `null`.

---

## Action references

Actions are referenced by string ID, not inlined at the point of use. The shape is:

```
$@Generic___@Macro___<GUID>
$@Generic___@ProfileAction___<GUID>
$@Generic___@FollowActiveApplicationMode___2
$DefaultWin___Brightness
```

Read it as `$<plugin>___<group>___<identifier>`, separated by triple underscores. `@Generic` covers user-created actions; named plugins (`DefaultWin`, and any installed plugin) expose their own built-in actions under their own prefix.

The same string is used as the filename for the action's icon and image in `ActionIcons/` and `ActionImages/`.

---

## Macros are stored inline

This is the important part for portability: **a profile does not point at an external macro database.** The macros it uses are defined in the same `ProfileInfo.json`:

```jsonc
{
  "$type": "Loupedeck.Service.ApplicationProfileMacroCommand, LoupedeckService",
  "isCommand": true,
  "name": "52307D44BC1548C59BE28C8197C79915",   // matches the GUID in pressAction
  "displayName": "Open workspace",
  "description": "",
  "groupName": "",
  "superGroupName": "@macro",
  "isMultiState": false,
  "actions": ["bm-maya9fvszsbyyqt7ik"]
}
```

with the keystroke carried in `actionParameters`:

```jsonc
"actionParameters": {
  "$type": "System.Collections.Generic.Dictionary`2[[System.String, ...],[System.String, ...]], System.Private.CoreLib",
  "keyboardKey": "AltOrOption+KeyF___68486165___Alt+F___win-70#¤%&+?2#¤%&+?68486165#¤%&+?33"
}
```

The `keyboardKey` value packs several encodings of the same shortcut into one string: a platform-neutral name (`AltOrOption+KeyF`), a numeric key code, a display form (`Alt+F`), and a platform-specific tail. The `#¤%&+?` sequence is a field separator. This part is only partially decoded — contributions welcome.

Options+ also keeps a `macros.db` SQLite file under `%LOCALAPPDATA%\LogiOptionsPlus\`, but the macro GUIDs referenced by a profile were **not** found in it. The profile appears to be the authoritative copy.

---

## What makes a profile portable

Three properties, all verified by inspection:

1. **No absolute paths.** A regex sweep for `X:\...` patterns over the whole file returns nothing.
2. **No device serial numbers or per-installation IDs.** Binding is to `deviceType` — a device *class*, not a physical unit.
3. **Macros are inline**, so there is no external state to carry alongside.

What this does **not** prove: that Options+ will accept a profile folder dropped in from elsewhere. The service holds state in memory and may rewrite files on shutdown. Treat portability as structurally plausible and empirically untested — see the open questions in the README.

---

## Editing notes

If you experiment, assume you will break something at least once.

- Stop `LogiPluginService` before editing, or expect your changes to be overwritten from memory
- Keep `$type` strings byte-identical — they select the deserializer target
- Keep the GUID in `pressAction` consistent with the macro `name` and with the icon filenames
- The folder name must match the `name` field
- Take a snapshot first; Options+ already made you one, see [backups.md](backups.md)

---

## Open questions

- Full decoding of the `keyboardKey` packed format, including the numeric codes
- Meaning of the `actions` array entries (`bm-…` identifiers)
- What `profileFlags` accepts beyond `None`
- Whether `layoutModes` supports more than `main`, and what `parentModeName` enables
- Purpose of `dynamicButtonPages` / `dynamicEncoderPages` (present, empty in observed profiles)
- Whether `ApplicationProfileImporter.TryParseLayoutFile` (which parses XML) accepts a user-supplied file, and what that XML looks like

If you can answer any of these from observation, please open an issue.
