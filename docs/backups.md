# Options+ already backs up your profiles

Logi Options+ writes periodic ZIP snapshots of every profile, for every device, and does not mention it anywhere in the UI. If you have ever lost a setup, a copy may still be on disk.

```
%LOCALAPPDATA%\Logi\LogiPluginService\Applications.Backups\
```

Files are named `backup_YYYY-MM-DD_HH-MM-SS.zip`.

---

## What a snapshot contains

A snapshot is the entire `Applications` tree: every device type, every application entry, every profile, with icons and images included. One observed archive held 449 entries across three device types, at roughly 3.5 MB compressed.

Inside, paths mirror the live layout:

```
Loupedeck70/@_photoshop/Profiles/<GUID>/ProfileInfo.json
Loupedeck72/@_defaultwin/Profiles/<GUID>/ProfileInfo.json
...
```

## Listing your snapshots

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Logi\LogiPluginService\Applications.Backups" -Filter *.zip |
    Sort-Object LastWriteTime -Descending |
    Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB)}}, LastWriteTime
```

## Looking inside without extracting

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead("$env:LOCALAPPDATA\Logi\LogiPluginService\Applications.Backups\backup_YYYY-MM-DD_HH-MM-SS.zip")
$zip.Entries | Where-Object { $_.FullName -match 'ProfileInfo\.json$' } | Select-Object FullName
$zip.Dispose()
```

To recover a single profile, extract just that folder to a working directory and inspect it before putting anything back.

---

## Cadence and retention

Snapshots appeared irregularly in the observed installation — roughly weekly, with gaps, and an extra snapshot around configuration changes. The oldest retained archive was about two months old.

The exact trigger and retention policy are **not established**. Do not treat this as a guaranteed backup: it is a convenience that happens to exist, not a documented feature with a support commitment. Keep your own copy of anything you care about.

---

## Restoring

There is no documented restore path, and dropping files back into the live `Applications` tree while the service is running is untested — see the open questions in the [README](../README.md#verification-status).

Minimum sensible precautions:

1. Stop `LogiPluginService`
2. Copy the current live folder somewhere safe first
3. Put the recovered profile folder in place, keeping the GUID folder name consistent with the `name` field inside `ProfileInfo.json`
4. Start the service and check the Options+ UI before assuming success

If you try this, a report of what happened would be a genuinely useful issue.
