# Bluetooth Control Investigations

This section documents the technical investigation for Bluetooth control on different Kobo device
types.

## Devices

### MTK Devices

- Uses MTK-specific Bluetooth implementation
- D-Bus service: `com.kobo.mtk.bluedroid`
- Custom command set and initialization sequence
- See [MTK Documentation](./mtk/00-overview.md)

### BlueZ Devices (Libra 2, Sage)

- Uses standard Linux BlueZ stack (`org.bluez`)
- Shared D-Bus operations in `bluez_adapter.lua`
- Chip-specific bring-up only in per-device adapters
- [Libra 2](./libra-2/00-overview.md) — Realtek on `ttymxc1` + `sdio_bt_pwr`
- [Sage](./sage/00-overview.md) — Realtek RTL8821C on `/dev/ttyS1` + platform rfkill
