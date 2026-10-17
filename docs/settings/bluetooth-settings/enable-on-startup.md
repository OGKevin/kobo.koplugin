# Enable on Startup

## Overview

"Auto-resume after wake" only covers waking from sleep. After a reboot, or when KOReader is started
from Kobo's own software, Bluetooth stays off until you enable it. "Enable on startup" turns
Bluetooth on once when KOReader starts, so a page-turner remote is ready without a trip through the
menus.

## Enabling the Setting

1. Go to Settings → Network → Bluetooth → Settings
2. Toggle "Enable on startup"

## How It Works

- Bluetooth is turned on once per KOReader run, when the plugin starts. Opening another book later
  does not turn it on again.
- Nothing happens if Bluetooth is already on, for example because it was left on in Kobo's own
  software.
- Once Bluetooth is up, the plugin behaves as after any other enable: auto-connect and
  auto-detection start according to their settings, and connected devices are opened.
- WiFi is handled as after a wake-up; see the WiFi notes under
  [Auto-resume After Wake](./auto-resume.md).

## Battery Considerations

The setting is off by default. While Bluetooth is on, the Kobo does not enter standby and uses more
battery, whether or not a remote is connected. Enable the setting if you use a remote every time you
read.
