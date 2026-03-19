#!/bin/bash
set -euo pipefail

#
# flash-sdcard.sh - Flash ADU Yocto image to SD card for Raspberry Pi 4
#
# Writes the WIC image to an SD card and optionally verifies the A/B partition
# layout. The WIC image already contains rootfs on both partitions A and B
# (as defined in adu-raspberrypi.wks).
#
# Usage:
#   ./scripts/flash-sdcard.sh --image <wic.gz> --device <sdcard>
#   ./scripts/flash-sdcard.sh --image <wic.gz> --device /dev/sdX --verify
#
# Examples:
#   ./scripts/flash-sdcard.sh -i build/tmp/deploy/images/raspberrypi4-64/adu-base-image-raspberrypi4-64.wic.gz -d /dev/sdb
#   ./scripts/flash-sdcard.sh -i ~/adu_yocto/out/build/tmp/deploy/images/raspberrypi4-64/adu-base-image-raspberrypi4-64.wic.gz -d /dev/sdb --verify
#
# Partition Layout (written by WIC image):
#   p1 (boot)   - 2GB vfat  - U-Boot, kernel, DTBs
#   p2 (rootA)  - ext4      - Primary rootfs
#   p3 (rootB)  - ext4      - Secondary rootfs (identical to rootA)
#   p4 (adu)    - 8GB ext4  - Persistent data (/adu)
#
# Credential Persistence Verification:
#   1. Boot from rootA (default), change root password
#   2. Set U-Boot to boot rootB: fw_setenv boot_partition rootB
#   3. Reboot — password should persist because /etc/shadow is bind-mounted
#      from /adu/system/shadow (persistent partition p4)
#

SCRIPT_NAME="$(basename "$0")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [options]

Required:
  -i, --image <path>      Path to WIC image (.wic, .wic.gz, .wic.bz2, .wic.xz)
  -d, --device <device>   Target SD card device (e.g., /dev/sdb, /dev/mmcblk0)

Options:
  --verify                After flashing, verify partition layout and contents
  --no-confirm            Skip confirmation prompt (use with caution)
  -h, --help              Show this help message

Examples:
  $SCRIPT_NAME -i adu-base-image-raspberrypi4-64.wic.gz -d /dev/sdb
  $SCRIPT_NAME -i adu-base-image-raspberrypi4-64.wic.gz -d /dev/sdb --verify
EOF
}

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

# --- Parse arguments ---
IMAGE_PATH=""
DEVICE=""
VERIFY=0
NO_CONFIRM=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--image)   IMAGE_PATH="$2"; shift 2 ;;
        -d|--device)  DEVICE="$2"; shift 2 ;;
        --verify)     VERIFY=1; shift ;;
        --no-confirm) NO_CONFIRM=1; shift ;;
        -h|--help)    print_usage; exit 0 ;;
        *)            log_error "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

if [[ -z "$IMAGE_PATH" ]] || [[ -z "$DEVICE" ]]; then
    log_error "Both --image and --device are required."
    print_usage
    exit 1
fi

# --- Validate inputs ---
if [[ ! -f "$IMAGE_PATH" ]]; then
    log_error "Image file not found: $IMAGE_PATH"
    exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
    log_error "Device not found or not a block device: $DEVICE"
    exit 1
fi

# Safety: refuse to write to system disk
ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null || echo "")
if [[ -n "$ROOT_DISK" ]] && [[ "$DEVICE" == "/dev/$ROOT_DISK" ]]; then
    log_error "Refusing to write to system disk: $DEVICE"
    exit 1
fi

# Check for root/sudo
if [[ "$(id -u)" -ne 0 ]]; then
    SUDO="sudo"
    log_info "Will use sudo for privileged operations."
else
    SUDO=""
fi

# --- Display device info and confirm ---
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│                  SD Card Flash Tool                     │"
echo "├─────────────────────────────────────────────────────────┤"
echo "│  Image:  $(basename "$IMAGE_PATH")"
echo "│  Size:   $(du -h "$IMAGE_PATH" | cut -f1)"
echo "│  Device: $DEVICE"
echo "│"

# Show current device info
if command -v lsblk &> /dev/null; then
    echo "│  Device details:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT "$DEVICE" 2>/dev/null | while IFS= read -r line; do
        echo "│    $line"
    done
fi

echo "│"
echo "│  Partition layout (after flash):"
echo "│    p1: boot   (2 GB, vfat)  - U-Boot, kernel"
echo "│    p2: rootA  (ext4)        - Primary rootfs"
echo "│    p3: rootB  (ext4)        - Secondary rootfs"
echo "│    p4: adu    (8 GB, ext4)  - Persistent data"
echo "└─────────────────────────────────────────────────────────┘"
echo ""

if [[ $NO_CONFIRM -eq 0 ]]; then
    echo -e "${RED}⚠  WARNING: ALL DATA ON $DEVICE WILL BE DESTROYED!${NC}"
    echo ""
    read -p "Type 'yes' to proceed: " -r
    if [[ "$REPLY" != "yes" ]]; then
        log_info "Cancelled."
        exit 0
    fi
fi

# --- Unmount any mounted partitions ---
log_step "Unmounting any mounted partitions on $DEVICE..."
for part in "${DEVICE}"?* "${DEVICE}p"?*; do
    if [[ -b "$part" ]] && findmnt -n "$part" &>/dev/null; then
        log_info "Unmounting $part"
        $SUDO umount "$part" || true
    fi
done

# --- Flash the image ---
log_step "Flashing image to $DEVICE..."
echo ""

case "$IMAGE_PATH" in
    *.wic.gz)
        log_info "Decompressing and writing (gzip)..."
        gunzip -c "$IMAGE_PATH" | $SUDO dd of="$DEVICE" bs=4M status=progress conv=fsync
        ;;
    *.wic.bz2)
        log_info "Decompressing and writing (bzip2)..."
        bunzip2 -c "$IMAGE_PATH" | $SUDO dd of="$DEVICE" bs=4M status=progress conv=fsync
        ;;
    *.wic.xz)
        log_info "Decompressing and writing (xz)..."
        xz -dc "$IMAGE_PATH" | $SUDO dd of="$DEVICE" bs=4M status=progress conv=fsync
        ;;
    *.wic)
        log_info "Writing raw image..."
        $SUDO dd if="$IMAGE_PATH" of="$DEVICE" bs=4M status=progress conv=fsync
        ;;
    *)
        log_error "Unsupported image format: $IMAGE_PATH"
        log_error "Supported: .wic, .wic.gz, .wic.bz2, .wic.xz"
        exit 1
        ;;
esac

# Sync and re-read partition table
$SUDO sync
$SUDO partprobe "$DEVICE" 2>/dev/null || true
sleep 2

echo ""
log_info "Flash complete!"

# --- Determine partition naming ---
# /dev/sdb -> /dev/sdb1, /dev/mmcblk0 -> /dev/mmcblk0p1
if [[ "$DEVICE" =~ [0-9]$ ]]; then
    PART_PREFIX="${DEVICE}p"
else
    PART_PREFIX="${DEVICE}"
fi

# --- Verify ---
if [[ $VERIFY -eq 1 ]]; then
    echo ""
    log_step "Verifying partition layout..."
    echo ""

    PASS=0
    FAIL=0

    verify_partition() {
        local part_num="$1"
        local expected_label="$2"
        local expected_fstype="$3"
        local part_dev="${PART_PREFIX}${part_num}"

        if [[ ! -b "$part_dev" ]]; then
            log_error "  p${part_num}: MISSING (expected $expected_label)"
            ((FAIL++))
            return
        fi

        local actual_fstype
        actual_fstype=$($SUDO blkid -o value -s TYPE "$part_dev" 2>/dev/null || echo "unknown")
        local actual_label
        actual_label=$($SUDO blkid -o value -s LABEL "$part_dev" 2>/dev/null || echo "unknown")
        local actual_size
        actual_size=$(lsblk -bno SIZE "$part_dev" 2>/dev/null || echo "0")
        local size_mb=$((actual_size / 1024 / 1024))

        if [[ "$actual_fstype" == "$expected_fstype" ]]; then
            log_info "  p${part_num}: ✓ $actual_label ($actual_fstype, ${size_mb}MB)"
            ((PASS++))
        else
            log_error "  p${part_num}: ✗ Expected $expected_fstype, got $actual_fstype"
            ((FAIL++))
        fi
    }

    verify_partition 1 "boot"  "vfat"
    verify_partition 2 "rootA" "ext4"
    verify_partition 3 "rootB" "ext4"
    verify_partition 4 "adu"   "ext4"

    # Verify rootA and rootB have content
    echo ""
    log_step "Verifying rootfs content..."

    TMPDIR_A=$(mktemp -d)
    TMPDIR_B=$(mktemp -d)
    trap "$SUDO umount '$TMPDIR_A' 2>/dev/null; $SUDO umount '$TMPDIR_B' 2>/dev/null; rmdir '$TMPDIR_A' '$TMPDIR_B' 2>/dev/null" EXIT

    $SUDO mount -o ro "${PART_PREFIX}2" "$TMPDIR_A" 2>/dev/null
    $SUDO mount -o ro "${PART_PREFIX}3" "$TMPDIR_B" 2>/dev/null

    # Check key files exist on both partitions
    for f in etc/passwd etc/shadow etc/fstab usr/bin/adu-shell; do
        if [[ -f "$TMPDIR_A/$f" ]] && [[ -f "$TMPDIR_B/$f" ]]; then
            log_info "  ✓ $f present on both rootA and rootB"
            ((PASS++))
        else
            log_error "  ✗ $f missing on one or both partitions"
            ((FAIL++))
        fi
    done

    # Compare rootA and rootB
    echo ""
    log_step "Comparing rootA vs rootB..."
    DIFF_COUNT=$($SUDO diff -rq "$TMPDIR_A/etc" "$TMPDIR_B/etc" 2>/dev/null | wc -l || echo "0")
    if [[ "$DIFF_COUNT" -eq 0 ]]; then
        log_info "  ✓ rootA/etc and rootB/etc are identical"
        ((PASS++))
    else
        log_warn "  ⚠ rootA/etc and rootB/etc differ in $DIFF_COUNT files"
        log_warn "    (This may be expected if WIC assigns different UUIDs)"
    fi

    # Check /adu partition is empty (fresh flash)
    $SUDO umount "$TMPDIR_A" 2>/dev/null
    $SUDO mount -o ro "${PART_PREFIX}4" "$TMPDIR_A" 2>/dev/null
    ADU_FILES=$($SUDO find "$TMPDIR_A" -maxdepth 1 -not -name 'lost+found' -not -path "$TMPDIR_A" | wc -l)
    if [[ "$ADU_FILES" -eq 0 ]]; then
        log_info "  ✓ /adu partition is empty (will be initialized on first boot)"
        ((PASS++))
    else
        log_info "  ℹ /adu partition has $ADU_FILES items (may have prior data)"
    fi

    $SUDO umount "$TMPDIR_A" 2>/dev/null
    $SUDO umount "$TMPDIR_B" 2>/dev/null

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Verification: ${PASS} passed, ${FAIL} failed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
fi

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│  ✓ SD card ready!                                          │"
echo "│                                                             │"
echo "│  To test credential persistence across A/B partitions:      │"
echo "│                                                             │"
echo "│  1. Insert SD card into Raspberry Pi 4 and boot             │"
echo "│  2. Log in (default: root with debug-tweaks blank password) │"
echo "│  3. Change root password:                                   │"
echo "│       passwd root                                           │"
echo "│  4. Verify password is on persistent partition:             │"
echo "│       ls -la /adu/system/shadow                             │"
echo "│       cat /proc/mounts | grep shadow                       │"
echo "│  5. Switch to rootB:                                        │"
echo "│       fw_setenv boot_partition rootB                        │"
echo "│       reboot                                                │"
echo "│  6. Log in with the SAME password you set in step 3         │"
echo "│     (proves /adu/system/shadow persists across A/B switch)  │"
echo "│                                                             │"
echo "│  To switch back to rootA:                                   │"
echo "│       fw_setenv boot_partition rootA                        │"
echo "│       reboot                                                │"
echo "└─────────────────────────────────────────────────────────────┘"
