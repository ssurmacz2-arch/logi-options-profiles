# Device types

Profiles are stored under a `DeviceType` folder and carry a matching `deviceType` field. The values look cryptic (`Loupedeck70`, `Loupedeck71`, `Loupedeck72`) because the stack came from Loupedeck, which Logitech acquired.

The mapping below is read directly from the `DeviceType` enum in `PluginApi.dll` as shipped with Logi Plugin Service, including the vendor's own display names.

## Logitech devices

| Value | Display name | Notes |
|---|---|---|
| `Loupedeck70` | MX Creative Keypad | Physical keypad |
| `Loupedeck71` | MX Creative Dialpad | Physical dialpad |
| `Loupedeck72` | **Actions Ring** | Not a physical device — see below |
| `LoupedeckExtendedFamily` | Logitech Creative Family | Family mask covering the above |

**`Loupedeck72` is the surprising one.** Actions Ring — the radial overlay that appears at your cursor — is modelled as a device in its own right, not as a property of whichever mouse triggers it. Ring profiles are therefore bound to the ring, not to a specific mouse model.

That matches the documented behaviour that Actions Ring works across MX devices generally, rather than being exclusive to one product.

## Loupedeck and Razer devices

Present in the same enum, for completeness:

| Value | Display name |
|---|---|
| `Loupedeck10` | Loupedeck Original |
| `Loupedeck15` | Loupedeck+ |
| `Loupedeck20` | Loupedeck CT |
| `Loupedeck30` | Loupedeck Live |
| `Loupedeck40` | Razer Stream Controller |
| `Loupedeck50` | Loupedeck Live S |
| `Loupedeck60` | Razer Stream Controller X |

Family masks: `LoupedeckOriginalFamily`, `LoupedeckCtFamily`, `LoupedeckExtendedFamily`, plus a reserved `LoupedeckBlockFamily` with four unnamed reserved entries.

## Why it matters for profiles

The `deviceType` in a profile identifies a device **class**, not an individual unit — there is no serial number involved. Copying a profile between machines with the same device class does not require rewriting this field.

Copying a profile *across* classes (say, a keypad profile onto the ring) is a different matter: the control count and capabilities differ, and this has not been tested. Actions Ring exposes `controlId` 0–7.
