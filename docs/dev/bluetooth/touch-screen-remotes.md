# Touch-screen Style Remotes

Cheap page-turner rings and remotes made for scrolling short videos on a phone ("TikTok rings") do
not send key presses. They present themselves as a touch screen and send every button as a simulated
finger gesture: `BTN_TOUCH` down, a few `ABS_X`/`ABS_Y` positions, `BTN_TOUCH` up. Two things are
needed before such a device can be used like a normal remote.

## Driver binding

The HID descriptor of such a device carries a digitizer contact ID, so the kernel files it under the
multitouch HID group (`hid:b0005g0002…` in its modalias) and leaves it to `hid-multitouch`. Kobo
kernels do not ship that driver (`CONFIG_HID_MULTITOUCH` is not set), so the device connects,
appears on the HID bus without a `driver` link, and never gets a `/dev/input/eventN` node.

`InputDeviceHandler:_bindUnclaimedHidDevices()` in `src/lib/bluetooth/input_device_handler.lua`
writes the device's `<bus> <vendor> <product>` ID to `/sys/bus/hid/drivers/hid-generic/new_id`.
Dynamic IDs match any HID group, so `hid-generic` claims the device and the input node appears. The
ID stays registered until reboot; reconnects of the same device are bound by the kernel on its own.

The binding is deliberately narrow. A device is only handed to `hid-generic` when all of these hold:

- it is on the Bluetooth bus (`0005`);
- it has no driver;
- it is in a multitouch HID group (`0002` or `0100`), the only case in which a HID device the user
  paired stays driverless on a Kobo;
- when the plugin is opening a specific paired device, the device's `HID_UNIQ` (its Bluetooth
  address, reported with reversed byte order on MTK devices) matches that device.

A list of approved vendor/product IDs was considered and rejected: the WX02 ring, for instance,
reports Apple's `05AC:0220`, an ID shared with unrelated products, so IDs identify neither the
product nor its behaviour.

## Gesture to key translation

`BluetoothInputReader` in `src/lib/bluetooth/bluetooth_input_reader.lua` folds a touch contact into
one synthetic key press and release, using key codes above the kernel's `KEY_MAX` (767) so they
never collide with a real key:

| Gesture     | Key name   |
| ----------- | ---------- |
| Tap         | `KEY_1000` |
| Swipe up    | `KEY_1001` |
| Swipe down  | `KEY_1002` |
| Swipe left  | `KEY_1003` |
| Swipe right | `KEY_1004` |

A swipe fires as soon as the movement exceeds 5% of the largest coordinate seen so far, not when the
finger lifts: the release only arrives several reports later, which would make page turns feel slow.
A tap is decided at release. One gesture is fired per contact. The digitizer tool and contact
buttons (`BTN_TOOL_*`, `BTN_TOUCH`) and any key sent in the same report as the touch button are
swallowed; plain key events from ordinary remotes pass through unchanged.

## Known device

The **WX02** ring ("wxlj-02", classic Bluetooth, three buttons) sends swipe down and swipe up for
its next/previous buttons and a tap for the middle button, which also sends `KEY_116` (power) on its
first press after power-on. Its touch reports are one byte shorter than its descriptor declares;
Linux pads short reports, so they work on the Kobo.
