# Profiles

Shareable Logi Options+ profiles. Empty for now — profiles land here once the loading behaviour in the [open questions](../README.md#verification-status) is confirmed, so that nothing gets published before it is known to work.

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

## Privacy checklist before submitting

A profile is a record of how someone works, and it embeds more than it looks like. **Read your own `ProfileInfo.json` before publishing it.** Check for:

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
