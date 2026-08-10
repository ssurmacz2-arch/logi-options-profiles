# Where Logi Options+ keeps everything (Windows)

Observed on Windows 11 with Logi Options+ and Logi Plugin Service installed, August 2026. Paths use the standard environment variables; expand them in Explorer or PowerShell.

---

## Profiles

```
%LOCALAPPDATA%\Logi\LogiPluginService\Applications\<DeviceType>\<application>\Profiles\<GUID>\
```

- `<DeviceType>` — `Loupedeck70`, `Loupedeck71`, `Loupedeck72`. See [device-types.md](device-types.md)
- `<application>` — lowercase application key, prefixed with `@_` for built-in entries (`@_photoshop`, `@_excel`, `@_defaultwin`). User-created application entries appear without the prefix
- `<GUID>` — profile identifier, matching the `name` field inside `ProfileInfo.json`

`@_defaultwin` is the fallback profile used when no application-specific profile matches.

## Automatic backups

```
%LOCALAPPDATA%\Logi\LogiPluginService\Applications.Backups\backup_YYYY-MM-DD_HH-MM-SS.zip
```

Periodic ZIP snapshots of the entire `Applications` tree. See [backups.md](backups.md).

## Plugins

```
%LOCALAPPDATA%\Logi\LogiPluginService\Plugins\<PluginName>\
├── bin\                      # the plugin assembly
├── events\                   # event source and haptic mapping YAML
└── metadata\                 # LoupedeckPackage.yaml, icon
```

Supporting directories alongside it:

| Path | Contents |
|---|---|
| `…\LogiPluginService\PluginData\` | Per-plugin runtime data |
| `…\LogiPluginService\PluginSettings\` | Per-plugin settings blobs |
| `…\LogiPluginService\PluginHosts\` | Runtime hosts for non-.NET plugins (e.g. Node) |

Plugin packages install from `.lplug4` / `.lplug5` archives, which are registered with the OS and open by double-click. Installed plugins are unpacked, so the folder above *is* the package contents.

Do not confuse these with `.lp4` / `.lp5`, which carry **profiles** rather than plugins — see [package-formats.md](package-formats.md).

## Logs

```
%LOCALAPPDATA%\Logi\LogiPluginService\Logs\plugin_logs\<PluginName>.log
```

Plain text, one line per event, with timestamp and level. Useful for confirming a plugin is alive and what it is being asked to do.

## Options+ application data

```
%LOCALAPPDATA%\LogiOptionsPlus\
├── macros.db                 # SQLite
├── privacy_settings.db
├── logi_voice_settings.db
├── cc_config.json
├── icon_cache\
└── devio_cache\
```

Note that `macros.db` did **not** contain the macro GUIDs referenced by an observed profile — profiles carry their macros inline. See [profile-format.md](profile-format.md).

## Program files

```
C:\Program Files\LogiOptionsPlus\        # the Options+ application and agent
C:\Program Files\Logi\LogiPluginService\ # the plugin service
C:\ProgramData\Logishrd\LogiOptionsPlus\Plugins\  # host-app integrations (Adobe CEP, Lightroom .lrplugin)
```

## Processes worth knowing

| Process | Role |
|---|---|
| `logioptionsplus.exe` | The UI |
| `logioptionsplus_agent.exe` | Device communication, including haptics over HID++ |
| `LogiPluginService.exe` | Loads plugins, owns profiles |
| `LogiPluginServiceExt.exe` | Plugin host process |

Stop `LogiPluginService` before hand-editing any profile, or the running service may overwrite your changes from memory.
