# Virtual Library Overview

- **Enable virtual library** - Toggle the virtual library feature on or off. When enabled, you can
  access your Kobo library from within KOReader. When disabled, the virtual library and all
  sync-related menu items will be hidden. A restart is required for changes to take effect.
  (Default: enabled)

- **Virtual library folder cover** - Select a custom cover image file for the virtual library
  folder. Only available when the virtual library is enabled. This is used by the
  [ProjectTitle](https://github.com/joshuacant/ProjectTitle) plugin to display a custom thumbnail
  for the virtual library folder instead of falling back to an auto-generated cover. (Default: none)

## Details

When the virtual library is enabled, the plugin exposes a virtual view of your Kobo device's library
inside KOReader. This virtual view is populated from Kobo's metadata and lets you browse, search,
and open titles backed by Kobo's database without switching to the native Kobo reader.

## ProjectTitle Integration

This plugin integrates with [ProjectTitle](https://github.com/joshuacant/ProjectTitle), a KOReader
plugin that enhances folder cover display. When a cover image is configured via the **Virtual
library folder cover** setting, the plugin passes the file path to ProjectTitle using the
`pt_cover_path` field on the virtual folder entry. ProjectTitle then uses this explicit path to
display the chosen image as the folder thumbnail instead of auto-detecting one.

To use this feature:

1. Install the [ProjectTitle](https://github.com/joshuacant/ProjectTitle) plugin in KOReader.
2. Enable the virtual library in Kobo Library settings.
3. Open **Kobo Library → Virtual library folder cover** and select an image file.
4. ProjectTitle will display the selected image as the virtual library folder cover.

## Behavior

- Enabling the virtual library adds a virtual folder in KOReader that mirrors your Kobo library
  entries.
- Disabling the virtual library hides the virtual folder and removes sync-related menu items; it
  does not delete your actual book files.
- Changing this setting requires restarting KOReader for the virtual filesystem and related menu
  entries to be fully initialized or removed.
