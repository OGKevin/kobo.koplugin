# Known Issues

## Kernel Panic on Nickel Restart

**Severity:** Critical - Device reboots  
**Affects:** All Kobo devices with MTK Bluetooth chipset

### Problem Description

When exiting KOReader back to Nickel after using Bluetooth, the device experiences a kernel NULL
pointer dereference panic and reboots.

### Error Details

```
Unable to handle kernel NULL pointer dereference at virtual address 00000008
PC is at osal_fifo_init+0x18/0x6c [wlan_drv_gen4m]
LR is at kalIoctl+0x1c0/0x8d4 [wlan_drv_gen4m]
```

Full kernel panic logs and analysis:
[KOReader Issue #12739](https://github.com/koreader/koreader/issues/12739)

### Root Cause

The MediaTek WiFi driver (`wlan_drv_gen4m`) has **non-idempotent initialization**. The driver's
initialization code is not designed to be called multiple times in the same boot session.

When Nickel attempts to re-initialize the Bluetooth stack (even with modules already loaded and
processes terminated), the driver crashes in `osal_fifo_init` due to attempting to initialize
already-initialized structures.

### Attempted Solutions

#### ✅ Proper D-Bus Shutdown

```bash
# Gracefully shut down via D-Bus
dbus-send --system --dest=com.kobo.mtk.bluedroid \
    / com.kobo.bluetooth.BluedroidManager1.Off
```

**Result:** Off() method completes successfully, but doesn't prevent panic.

#### ✅ Process Termination

```bash
# Kill all Bluetooth processes
killall -KILL btservice mtkbtd
```

**Result:** Processes terminated successfully, but panic still occurs.

#### ✅ Keep Kernel Modules Loaded

```bash
# Verify modules remain loaded (do NOT unload)
lsmod | grep -E "(wmt|wlan|bt)"
```

**Result:** Modules stay loaded as required, but panic still occurs on Nickel restart.

#### ❌ Complete Cleanup

Even with all of the above:

- Devices disconnected
- Discovery stopped
- Adapter powered off
- Service Off() called
- Processes terminated
- Modules kept loaded

**The kernel panic still occurs when Nickel restarts.**

### Evidence from Investigation

Verified shutdown procedure execution:

```bash
[root@monza root]# BTSERVICE_PID=$(pgrep btservice)
[root@monza root]# MTKBTD_PID=$(pgrep mtkbtd)
[root@monza root]# kill -TERM $BTSERVICE_PID $MTKBTD_PID
[root@monza root]# sleep 2
[root@monza root]# ps aux | grep -E "(mtkbtd|btservice)" | grep -v grep
[root@monza root]# # No output - processes terminated
[root@monza root]# lsmod | grep wmt
wmt_drv 1059215 4 wlan_drv_gen4m,wmt_cdev_bt,wmt_chrdev_wifi, Live 0xbf000000 (O)
[root@monza root]# # Modules still loaded as required
```

Despite clean shutdown, testing confirmed device reboots when returning to Nickel.

### Hypothesis

Nickel's Bluetooth initialization expects a **pristine driver state**. Even though:

- Userspace processes are terminated
- Kernel modules remain loaded
- D-Bus services are stopped

Some **hardware state or driver-internal state persists** that conflicts with Nickel's
initialization expectations. The driver attempts to re-initialize structures that are already
initialized, causing the NULL pointer dereference.

### Potential Causes

1. **Hardware state not reset** - Bluetooth chip registers/state not cleared
2. **Driver global state** - Static/global variables in kernel module not reset
3. **Character device state** - `/dev/stpbt` or `/dev/wmt*` in unexpected state
4. **Resource conflict** - IRQ, DMA, or memory mappings not released properly

### Current Workaround

**None available.** Using Bluetooth in KOReader requires device reboot before returning to Nickel.

### References

- [KOReader Issue #12739](https://github.com/koreader/koreader/issues/12739) - Original bug report
  with kernel panic analysis
- [NickelMenu PR #152](https://github.com/pgaskin/NickelMenu/pull/152) - Discussion of libnickel
  Bluetooth integration
