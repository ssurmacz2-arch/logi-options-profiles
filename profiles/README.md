# Profiles

Shareable Logi Options+ profiles.

| Profile | Device | For |
|---|---|---|
| [`loupedeck72/general/starter`](loupedeck72/general/starter) | Actions Ring | General-purpose scaffold: four folders, personal contents stripped |

## Layout

One directory per profile:

```
profiles/<device-type>/<application>/<profile-name>/
├── ProfileInfo.json
├── ApplicationIcon.png
├── metadata/
├── ActionIcons/
└── ActionImages/
```

Mirroring the on-disk structure keeps installation a copy operation rather than a transformation.

## Removing a shortcut in the UI does not remove it from the profile

Verified on a real installation: after deleting file and folder shortcuts from the ring, **seven of eight path-bearing actions were still in `ProfileInfo.json`**, complete with absolute paths. They were no longer assigned to any slot, but the definitions — and the paths — remained in the profile's action library.

Unassigning is not deleting. Do not rely on tidying up in the UI before publishing; run the tooling below.

## Privacy checklist before submitting

A profile is a record of how someone works, and it embeds more than it looks like.

**Run [`scripts/anonymize.ps1`](../scripts/anonymize.ps1)**, which strips every path-bearing action while keeping folder containers intact, then **[`scripts/verify.ps1`](../scripts/verify.ps1)** to confirm nothing survived. A profile with "open file" or "launch application" actions carries full paths to your drives, project directories, and user folder. On a real machine that surfaced paths to personal projects and a home directory containing the user's name, in a profile that looked clean in the UI.

Then **read the JSON yourself.** Tooling catches paths; it cannot judge names. Check for:

- **`displayName` on macros** — action labels routinely name applications, services, brokers, clients, or projects
- **Application names and window titles** picked up from your machine
- **File paths and URLs** inside macro parameters, including anything opening a local document or an internal address
- **Account or profile names** embedded in shortcuts
- **`ApplicationIcon.png` and `ActionImages/`** — rendered button images can contain readable text from your setup

Rename anything specific to a generic equivalent. "Open broker platform" carries the same instructional value as the actual product name, without telling the internet what you use.

## Quality bar

A useful profile explains itself. Include a short `README.md` in the profile folder covering:

- Which application it is for, and which version it was built against
- What each of the eight ring slots does
- Any plugin the profile depends on — a profile referencing a plugin you do not have will have dead slots
- Which device type and Options+ version it was created on

Profiles that depend on plugins should say so in the first line. That is the single most common reason a shared configuration appears broken on someone else's machine.
