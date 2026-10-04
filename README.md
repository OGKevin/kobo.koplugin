<div align="center">

# kobo.koplugin

A KoReader plugin that extends Kobo device functionality.

</div>

## Features

- **Virtual Library** - Browse and open your Kobo kepub collection directly from KOReader
- **Reading State Sync** - Bidirectional synchronization of reading progress between KOReader and
  Kobo
- **Bluetooth Support** - Manage Bluetooth connections and pair devices from within KOReader

For detailed documentation of the original plugin, visit
[ogkevin.github.io/kobo.koplugin](https://ogkevin.github.io/kobo.koplugin).

## About this fork

This is a fork of [OGKevin/kobo.koplugin](https://github.com/OGKevin/kobo.koplugin). The plugin,
including all of its Bluetooth support, is the work of [OGKevin](https://github.com/OGKevin) and its
contributors. This fork only adds one feature on top of it: support for Bluetooth remotes that
emulate a touch screen.

The fork was modified on 2026-10-04, starting from upstream version 0.4.1. The changes are in
`src/lib/bluetooth/input_device_handler.lua` and `src/lib/bluetooth/bluetooth_input_reader.lua`. It
is distributed under the same licence as the original, the
[GNU General Public License v3.0](LICENSE). It has not been submitted upstream yet.

### Touch-screen style remotes ("TikTok rings")

Some cheap page-turner rings and remotes do not send key presses. They present themselves as a touch
screen and send every button as a simulated finger gesture (a swipe or a tap), because they are made
for scrolling short videos on a phone. With the original plugin such a remote connects, but "Register
button" never detects a press.

This fork does two things so these devices can be used like any other remote:

- **Driver binding.** The kernel classifies such a device as multitouch and leaves it to the
  `hid-multitouch` driver, which Kobo kernels do not include, so the device never gets an input
  node. When a connected Bluetooth HID device has no kernel driver, the plugin registers it with
  `hid-generic` so the input node is created. This lasts until the Kobo reboots and is repeated when
  needed.
- **Gesture to key translation.** A touch contact is turned into one synthetic key press, which can
  be bound like a normal button. A swipe fires as soon as its direction is clear.

  | Gesture     | Key name   |
  | ----------- | ---------- |
  | Tap         | `KEY_1000` |
  | Swipe up    | `KEY_1001` |
  | Swipe down  | `KEY_1002` |
  | Swipe left  | `KEY_1003` |
  | Swipe right | `KEY_1004` |

Buttons can only be told apart by the direction of their gesture. Two buttons that swipe in the same
direction, or tap at different positions, register as the same key. Remotes that emulate a mouse
(relative movement) instead of a touch screen are not covered.

### Tested device

Only one remote has been tested, on a Kobo Clara BW:

- **WX02** ring remote (sold as "wxlj-02", three buttons, classic Bluetooth, announces itself with
  Apple's vendor ID `05AC:0220`), for example [this listing](https://www.amazon.co.uk/dp/B0GTVH33JR).
  The next/previous buttons send swipe down/up (`KEY_1002` / `KEY_1001`). The middle button sends a
  tap (`KEY_1000`) and, on its first press after power-on, a power key (`KEY_116`).

To use it: pair and connect the ring from the plugin's Bluetooth menu, open its key bindings, choose
an action such as next page, select "Register button" and press the ring button.
