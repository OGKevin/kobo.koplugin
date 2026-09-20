# Bluetooth Control on Kobo Sage

## Device Information

- **Model**: Kobo Sage (`Kobo_cadmus`)
- **Platform**: Allwinner sun8iw15 (B300/A50)
- **Bluetooth / Wi‑Fi**: Realtek RTL8821C combo (UART HCI)
- **Bluetooth Stack**: Standard Linux BlueZ (`org.bluez`)
- **HCI UART**: `/dev/ttyS1`
- **Attach**: `/sbin/rtk_hciattach -n -s 115200 /dev/ttyS1 rtk_h5`
- **Power**: `/sys/devices/platform/bt/rfkill/rfkill0/state` (`sunxi-bt`)

## Key Differences from Libra 2

Both devices use BlueZ after HCI is up. Chip bring-up differs:

|              | Libra 2              | Sage                               |
| ------------ | -------------------- | ---------------------------------- |
| Model        | `Kobo_io`            | `Kobo_cadmus`                      |
| UART         | `ttymxc1`            | `/dev/ttyS1`                       |
| Power        | `sdio_bt_pwr.ko`     | platform rfkill                    |
| Attach flags | `rtk_hciattach -s …` | `rtk_hciattach -n -s …` (resident) |

Shared `org.bluez` discovery/connect/trust ops live in `bluez_adapter.lua`. Chip sequences are in
`libra2_adapter.lua` / `sage_adapter.lua`.

## Sources

- Issue [#216](https://github.com/OGKevin/kobo.koplugin/issues/216) (Sage stack notes)
- [Tharavol bluetooth.koplugin](https://github.com/Tharavol/bluetooth.koplugin) `on.sh` / `off.sh`
- [MobileRead post](https://www.mobileread.com/forums/showpost.php?p=4600168&postcount=101)
