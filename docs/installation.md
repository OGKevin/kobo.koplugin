# Installation

## Prerequisites

Before installing the Kobo Plugin, ensure you have:

1. **A Kobo eReader device** (Clara HD, Libra, Sage, etc.)
2. **KOReader installed** on your Kobo device
3. **Access to the Kobo filesystem** (usually via USB or file manager)

## Installation Method

1. **Download the latest release**

   - Go to the [latest release page](https://github.com/OGKevin/kobo.koplugin/releases/latest)
   - Download `kobo.koplugin.zip` and `kobo-patches.zip`

2. **Extract and install the plugin**

   - Extract `kobo.koplugin.zip` to obtain the `kobo.koplugin/` folder
   - Copy the entire `kobo.koplugin/` folder to your KOReader plugins directory on the Kobo device
   - The final path should be: `[KOReader]/plugins/kobo.koplugin/`

3. **Extract and install the patches**

   - Extract `kobo-patches.zip` to get the patch files (e.g., `2-*.lua`)
   - Copy these patch files directly into your KOReader patches folder on the Kobo device
   - Final location: `[KOReader]/patches/2-*.lua` (patch files directly in the patches folder)

4. **Restart KOReader**
   - Restart KOReader on your Kobo device for the plugin to load and become active

## Next Steps

After installation, see the [Getting Started](getting-started.md) guide to learn how to access your virtual Kobo library and configure sync settings.
