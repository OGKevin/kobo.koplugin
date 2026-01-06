# Investigations

This section contains technical investigations and research notes for experimental features and
system integrations that are being explored for the kobo.koplugin.

## Investigations

### [Bluetooth Integration](./bluetooth/00-overview.md)

Investigating methods to control Kobo device Bluetooth functionality from KOReader via Linux D-Bus
interfaces (BlueZ). The goal is to enable/disable Bluetooth, discover devices, and connect to paired
accessories (gamepads, audio devices) without relying on Nickel's UI.

**Key Areas:**

- D-Bus command reference for BlueZ adapter control
- Event sequence analysis from dbus-monitor captures
- Shell script implementation approach
- Lua integration strategies (os.execute vs FFI)
- Fallback option using libnickel direct calls

### [DRM Removal](./drm-removal.md)

Investigating how to remove DRM from legitimately purchased Kobo books to enable reading them in
KOReader via the virtual library feature. Analysis of existing tools (KOkobo plugin, kobodl, DeDRM)
and the native Kobo database structure.

**Key Areas:**

- Native Kobo database credential storage (UserID, DeviceID)
- Content encryption key storage and retrieval
- Kobo DRM (KDRM) decryption algorithm and key hierarchy
- AES-ECB encryption/decryption implementation

## Purpose of Investigations

Investigation documents serve to:

1. **Document Research:** Track findings, commands, and technical details during exploration
2. **Share Knowledge:** Provide context for future contributors working on these features
3. **Future Reference:** Preserve information that may be useful even if the feature isn't
   immediately implemented
