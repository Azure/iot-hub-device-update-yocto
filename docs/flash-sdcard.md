# SD Card Flash Tool

A command-line tool for flashing ADU Yocto images onto SD cards for Raspberry Pi 4, with built-in partition verification.

## Overview

The `flash-sdcard.sh` tool writes a WIC image to an SD card, setting up the full A/B partition layout required by Azure Device Update. It also provides a `--verify` mode to confirm the partition structure and rootfs content are correct before deploying to hardware.

### Partition Layout

The WIC image creates the following partition layout on the SD card:

```
SD Card (e.g., /dev/sdb)
┌──────────────────────────────────────────────────────────┐
│ p1: boot   │ p2: rootA  │ p3: rootB  │ p4: adu          │
│ 2 GB vfat  │ ext4       │ ext4       │ 8 GB ext4        │
│ U-Boot     │ Primary    │ Secondary  │ Persistent data  │
│ kernel     │ rootfs     │ rootfs     │ /adu             │
│ DTBs       │ (active)   │ (standby)  │                  │
└──────────────────────────────────────────────────────────┘
```

| Partition | Device | Label | Filesystem | Purpose |
|-----------|--------|-------|------------|---------|
| p1 | `/dev/mmcblk0p1` | boot | vfat (2 GB) | Bootloader, kernel, device tree |
| p2 | `/dev/mmcblk0p2` | rootA | ext4 | Primary rootfs — active by default |
| p3 | `/dev/mmcblk0p3` | rootB | ext4 | Secondary rootfs — used after A/B update |
| p4 | `/dev/mmcblk0p4` | adu | ext4 (8 GB) | Persistent storage: credentials, logs, delta staging, swap |

> **Note:** rootA and rootB contain identical rootfs images after flashing. The `/adu` partition starts empty and is initialized on first boot.

## Usage

### Basic Flash

```sh
./scripts/flash-sdcard.sh \
  --image build/tmp/deploy/images/raspberrypi4-64/adu-base-image-raspberrypi4-64.wic.gz \
  --device /dev/sdX
```

### Flash with Verification

```sh
./scripts/flash-sdcard.sh \
  --image build/tmp/deploy/images/raspberrypi4-64/adu-base-image-raspberrypi4-64.wic.gz \
  --device /dev/sdX \
  --verify
```

### Options

| Option | Description |
|--------|-------------|
| `-i`, `--image <path>` | Path to WIC image (`.wic`, `.wic.gz`, `.wic.bz2`, `.wic.xz`) |
| `-d`, `--device <device>` | Target SD card device (e.g., `/dev/sdb`, `/dev/mmcblk0`) |
| `--verify` | After flashing, verify partition layout and rootfs content |
| `--no-confirm` | Skip the confirmation prompt (for CI/CD use) |
| `-h`, `--help` | Show help message |

### Safety Features

- **Refuses to write to system disk** — detects and blocks writes to the mounted root device
- **Confirmation prompt** — shows device info and requires typing `yes` before writing
- **Auto-unmounts** — unmounts any mounted partitions on the target device before writing

## Identifying Your SD Card Device

Insert the SD card and identify the device:

```sh
# List block devices — look for the SD card by size
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# Or watch for the new device
dmesg | tail -20
```

> **⚠ Double-check the device path.** Writing to the wrong device will destroy data.

Common device names:
- USB SD card reader: `/dev/sdb`, `/dev/sdc`
- Built-in SD card slot: `/dev/mmcblk0`

## What `--verify` Checks

When `--verify` is specified, the tool performs these checks after flashing:

1. **Partition existence** — all 4 partitions present
2. **Filesystem types** — p1=vfat, p2=ext4, p3=ext4, p4=ext4
3. **Rootfs content** — key files exist on both rootA and rootB (`/etc/passwd`, `/etc/shadow`, `/etc/fstab`, `/usr/bin/adu-shell`)
4. **A/B consistency** — rootA and rootB `/etc` directories are identical
5. **ADU partition state** — confirms `/adu` is empty (will be initialized on first boot)

## Verification: Credential Persistence Across A/B Partitions

One of the key features of the ADU A/B update architecture is that **user credentials persist across rootfs updates**. This is achieved through the persistent `/adu` partition (p4) which stores `/etc/passwd`, `/etc/shadow`, and other critical files via bind mounts.

### How It Works

```
┌─────────────┐    bind mount    ┌──────────────────┐
│  /etc/shadow │ ◄──────────────── /adu/system/shadow │
│  (rootA)     │                 │  (persistent p4)  │
└─────────────┘                 └──────────────────┘
                                         ▲
┌─────────────┐    bind mount    ┌───────┘
│  /etc/shadow │ ◄────────────────
│  (rootB)     │
└─────────────┘
```

Both rootA and rootB read credentials from the same persistent location. The `adu-persistent-overlay` systemd service sets up these bind mounts at boot.

### Test Procedure

Use this procedure to verify that credential changes survive an A/B partition switch:

#### Prerequisites

- Raspberry Pi 4 with UART serial console or SSH access
- SD card flashed with `flash-sdcard.sh`
- The device has completed first boot (which initializes `/adu/system/`)

#### Step 1: Flash and Boot

```sh
# Flash the image
./scripts/flash-sdcard.sh \
  --image adu-base-image-raspberrypi4-64.wic.gz \
  --device /dev/sdX \
  --verify

# Insert SD card into Raspberry Pi 4 and power on
# Connect via serial console (115200 baud) or SSH
```

#### Step 2: Verify Initial State (rootA)

```sh
# Confirm we're on rootA
fw_printenv boot_partition
# Expected: boot_partition=rootA

# Confirm persistent overlay is active
systemctl status adu-persistent-overlay
# Expected: active (exited)

# Confirm shadow is bind-mounted from /adu
cat /proc/mounts | grep shadow
# Expected: /dev/mmcblk0p4 /etc/shadow ext4 ...

# Check persistent storage exists
ls -la /adu/system/shadow
# Expected: -rw-r----- 1 root shadow ... /adu/system/shadow
```

#### Step 3: Change Root Password

```sh
# Change the password
passwd root
# Enter new password (e.g., "testpass123")

# Verify the change is on the persistent partition
cat /adu/system/shadow | grep root
# The hash should be updated (not the original)
```

#### Step 4: Switch to rootB and Verify

```sh
# Switch U-Boot to boot rootB
fw_setenv boot_partition rootB
reboot
```

After reboot:

```sh
# Log in with the password you set in Step 3
# If login succeeds → credential persistence is WORKING ✅

# Confirm we're on rootB
fw_printenv boot_partition
# Expected: boot_partition=rootB

# Confirm same persistent shadow file
cat /proc/mounts | grep shadow
# Expected: /dev/mmcblk0p4 /etc/shadow ext4 ...

# The shadow hash should match what was set on rootA
cat /adu/system/shadow | grep root
```

#### Step 5: Switch Back to rootA

```sh
# Switch back
fw_setenv boot_partition rootA
reboot

# Log in with the same password again
# If login succeeds → full round-trip verified ✅
```

### Expected Results

| Test | Expected Result | Pass Criteria |
|------|-----------------|---------------|
| Password change on rootA | Password updated in `/adu/system/shadow` | Hash changes after `passwd` |
| Boot to rootB | Same password works | Login succeeds with new password |
| Boot back to rootA | Same password still works | Login succeeds with new password |
| Reboot rootA | Password survives reboot | Login succeeds with new password |
| Reboot rootB | Password survives reboot | Login succeeds with new password |

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Password reverts after reboot | `adu-persistent-overlay` service not running | Check `systemctl status adu-persistent-overlay` |
| Password works on rootA but not rootB | Bind mount not set up on rootB | Verify `/proc/mounts` shows shadow bind mount |
| `/adu/system/` is empty | First boot initialization failed | Check `journalctl -u adu-persistent-overlay` |
| Cannot `fw_setenv` | U-Boot tools not installed | Verify `fw_printenv` works; check `u-boot-fw-utils` package |

### Automated Verification (Future)

For CI/CD pipelines, this test can be automated using QEMU or a hardware test farm:

```sh
# Flash
./scripts/flash-sdcard.sh -i <image.wic.gz> -d /dev/sdX --no-confirm --verify

# Boot via serial, run test commands, validate output
# (Requires serial console automation — e.g., pexpect, labgrid, or LAVA)
```
