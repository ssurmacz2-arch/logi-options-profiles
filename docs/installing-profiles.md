# Installing a profile by hand

Logi Options+ has no import button. It does, however, adopt a profile folder that simply appears in the right place — verified on Windows 11, August 2026.

Read [the test results](#what-was-actually-tested) before trusting this, and take a copy of your profiles first.

---

## Procedure

**1. Back up first.**

Options+ keeps its own snapshots (see [backups.md](backups.md)), but make your own copy of the tree you are about to touch:

```powershell
$src = "$env:LOCALAPPDATA\Logi\LogiPluginService\Applications"
Copy-Item $src "$env:USERPROFILE\Desktop\logi-profiles-backup" -Recurse
```

**2. Pick the destination.**

```
%LOCALAPPDATA%\Logi\LogiPluginService\Applications\<DeviceType>\<application>\Profiles\
```

`<DeviceType>` must match the `deviceType` field inside the profile — `Loupedeck72` for Actions Ring. See [device-types.md](device-types.md).

Multiple profiles per application are normal; adding one does not disturb the others.

**3. Copy the profile folder in, then make the GUID consistent.**

The folder name must equal the `name` field inside `ProfileInfo.json`. If you are cloning an existing profile rather than installing a fresh one, generate a new GUID for both, or the two profiles will collide:

```powershell
$guid = [guid]::NewGuid().ToString("N").ToUpper()
```

Give it a distinct `displayName` too — that is what you will look for in the UI.

**4. Restart the plugin service.**

```powershell
Stop-Process -Name LogiPluginServiceExt,LogiPluginService -Force
```

Both processes come back on their own within a few seconds. You do not need to start them, and you do not need to restart Options+ itself.

**5. Check the Options+ UI.** The profile appears in the list for that application.

---

## What was actually tested

A profile folder was cloned locally, given a fresh GUID and a new display name, and placed in `Loupedeck72\@_defaultwin\Profiles\`. Observed:

| Step | Result |
|---|---|
| Left in place, service running, 20 s | File untouched — not deleted, not rewritten |
| `LogiPluginService` + `…Ext` force-stopped | Both restarted automatically with new PIDs |
| After restart | Profile still present, `displayName` intact |
| Options+ UI | Profile listed and selectable |
| Every pre-existing profile | SHA256 unchanged — 26 of 26 identical to the pre-test backup |
| After removing the test profile | Tree byte-identical to the pre-test state |

**What this does not establish:** the profile came from the same machine. A profile authored elsewhere has not yet been tested, so anything that varies per installation — plugin availability above all — remains an open risk. A profile referencing a plugin you do not have will install fine and leave dead slots.

---

## If the profile does not show up

- **GUID mismatch** between the folder name and the `name` field — the most likely cause
- **Wrong `<DeviceType>` directory** for the profile's `deviceType` value
- **Malformed JSON.** The `$type` discriminators must be byte-identical; a broken file is more likely to be ignored than to raise a visible error
- **Service not actually restarted.** Confirm the PIDs changed:
  ```powershell
  Get-Process LogiPluginService,LogiPluginServiceExt | Select-Object ProcessName,Id
  ```

---

## Uninstalling

Delete the profile folder and restart the service the same way. Confirm you are deleting the right one by reading its `displayName` first — folder names are opaque GUIDs:

```powershell
Get-ChildItem "<...>\Profiles" -Directory | ForEach-Object {
    $j = Get-Content "$($_.FullName)\ProfileInfo.json" -Raw | ConvertFrom-Json
    "$($_.Name) -> $($j.displayName)"
}
```

Do not delete the profile named in `ApplicationInfo.json` under `defaultProfileName` unless you intend to.
