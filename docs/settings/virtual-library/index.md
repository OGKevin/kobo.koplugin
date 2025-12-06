# Virtual Library Overview

- **Enable virtual library** - Toggle the virtual library feature on or off. When enabled, you can
  access your Kobo library from within KOReader. When disabled, the virtual library and all
  sync-related menu items will be hidden. A restart is required for changes to take effect.
  (Default: enabled)

## Details

When the virtual library is enabled, the plugin exposes a virtual view of your Kobo device's library
inside KOReader. This virtual view is populated from Kobo's metadata and lets you browse, search,
and open titles backed by Kobo's database without switching to the native Kobo reader.

## Behavior

- Enabling the virtual library adds a virtual folder in KOReader that mirrors your Kobo library
  entries.
- Disabling the virtual library hides the virtual folder and removes sync-related menu items; it
  does not delete your actual book files.
- Changing this setting requires restarting KOReader for the virtual filesystem and related menu
  entries to be fully initialized or removed.
