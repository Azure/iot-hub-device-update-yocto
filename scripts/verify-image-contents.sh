#!/bin/bash
# verify-image-contents.sh — board-agnostic post-build asserter that walks the
# rootfs ext4 image and verifies critical ADU components are present.
#
# Unlike scripts/run-qemu-e2e.sh, this does NOT boot the image — it inspects
# the deployed ext4 (or .ext4.gz) artifact with debugfs, which works for ALL
# boards (QEMU, RPi4, i.MX8ULP) on any Linux CI runner.
#
# Emits a JUnit XML report at <output-dir>/verify-image-contents-junit.xml so
# the result flows through ADO PublishTestResults@2 -> Kusto.
#
# Usage:
#   ./scripts/verify-image-contents.sh <deploy-dir> <machine> [output-dir]
#
# Exits non-zero only if any expected file is missing.

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <deploy-dir> <machine> [output-dir]" >&2
    exit 2
fi

DEPLOY="$1"
MACHINE="$2"
OUT_DIR="${3:-$DEPLOY}"
mkdir -p "$OUT_DIR"

JUNIT="$OUT_DIR/verify-image-contents-junit.xml"
LOG="$OUT_DIR/verify-image-contents.log"
TS_START="$(date +%s)"

# Locate the rootfs artifact. Newest-mtime wins so re-runs pick up rebuilds.
#
# Image filename layout depends on IMAGE_NAME_SUFFIX, which differs per board:
#   default (QEMU, i.MX8ULP): adu-base-image-<machine>.rootfs-<datestamp>.ext4[.gz]
#   RPi4 (exports IMAGE_NAME_SUFFIX=""): adu-base-image-<machine>-<datestamp>.ext4[.gz]
# Use a broad glob that tolerates both forms.
shopt -s nullglob
candidates_gz=( "$DEPLOY"/adu-base-image-"$MACHINE"*.ext4.gz )
candidates_plain=( "$DEPLOY"/adu-base-image-"$MACHINE"*.ext4 )
shopt -u nullglob

ROOTFS_GZ=""
ROOTFS_PLAIN=""
if (( ${#candidates_gz[@]} > 0 )); then
    ROOTFS_GZ="$(ls -t "${candidates_gz[@]}" | head -n 1)"
fi
if (( ${#candidates_plain[@]} > 0 )); then
    ROOTFS_PLAIN="$(ls -t "${candidates_plain[@]}" | head -n 1)"
fi

if [[ -z "$ROOTFS_GZ" && -z "$ROOTFS_PLAIN" ]]; then
    echo "ERROR: no rootfs ext4(.gz) found under $DEPLOY for MACHINE=$MACHINE" >&2
    echo "Directory listing for debugging:" >&2
    ls -la "$DEPLOY" 2>&1 | head -n 100 >&2 || true
    exit 3
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -n "$ROOTFS_PLAIN" ]]; then
    ROOTFS="$ROOTFS_PLAIN"
else
    ROOTFS="$WORK/rootfs.ext4"
    gunzip -c "$ROOTFS_GZ" > "$ROOTFS"
fi

echo "[verify-image-contents] machine=$MACHINE rootfs=$ROOTFS" | tee "$LOG"

# Required files. classname is per-machine so ADO test runs separate boards.
# Format: "<test-name>|<path-in-rootfs>"
REQUIRED=(
    "AducIotAgent|/usr/bin/AducIotAgent"
    "delta-download-handler|/var/lib/adu/extensions/sources/libmicrosoft_delta_download_handler.so"
    "deviceupdate-agent.service|/lib/systemd/system/deviceupdate-agent.service"
    "adu-boot-validation.service|/lib/systemd/system/adu-boot-validation.service"
    "adu-agent-watchdog.service|/lib/systemd/system/adu-agent-watchdog.service"
    "adu-agent-watchdog.timer|/lib/systemd/system/adu-agent-watchdog.timer"
    "adu-swap.service|/lib/systemd/system/adu-swap.service"
    "adu-persistent-overlay.service|/lib/systemd/system/adu-persistent-overlay.service"
    "board.conf|/etc/adu/board.conf"
    "adu-swupdate-hw-compat|/etc/adu-swupdate-hw-compat"
    "yocto-a-b-update|/usr/lib/adu/yocto-a-b-update.sh"
    "adu-confirm-boot|/usr/bin/adu-confirm-boot"
    "fw_printenv|/usr/bin/fw_printenv"
    "swupdate|/usr/bin/swupdate"
)

# debugfs `stat` returns "File not found" for missing entries; on present
# entries it prints the inode header. Use that as the existence probe.
probe_path() {
    local p="$1"
    local out
    out="$(debugfs -R "stat $p" "$ROOTFS" 2>/dev/null || true)"
    if echo "$out" | grep -q "Inode:"; then
        # Pull size out of the stat block to also flag zero-byte ghosts.
        local size
        size="$(echo "$out" | grep -oE "Size: [0-9]+" | head -n1 | awk '{print $2}')"
        [[ -z "$size" ]] && size=0
        echo "$size"
        return 0
    fi
    return 1
}

# Some systemd units live under /usr/lib/systemd/system instead of /lib/...
# Try both.
probe_systemd() {
    local rel="$1"
    probe_path "/lib/systemd/system/$rel" || probe_path "/usr/lib/systemd/system/$rel"
}

declare -a TC_XML=()
fails=0
total=0

for entry in "${REQUIRED[@]}"; do
    name="${entry%%|*}"
    path="${entry#*|}"
    total=$((total+1))
    started="$(date +%s)"

    size=""
    if [[ "$path" == /lib/systemd/system/* ]]; then
        rel="${path#/lib/systemd/system/}"
        size="$(probe_systemd "$rel" || true)"
    else
        size="$(probe_path "$path" || true)"
    fi

    elapsed=$(( $(date +%s) - started ))

    if [[ -n "$size" && "$size" -gt 0 ]]; then
        echo "  PASS  $name  ($path, $size bytes)" | tee -a "$LOG"
        TC_XML+=("<testcase classname=\"image-contents.${MACHINE}\" name=\"${name}\" time=\"${elapsed}\"/>")
    else
        echo "  FAIL  $name  ($path: missing or empty)" | tee -a "$LOG"
        fails=$((fails+1))
        msg="Expected file ${path} not present (or zero-byte) in rootfs."
        TC_XML+=("<testcase classname=\"image-contents.${MACHINE}\" name=\"${name}\" time=\"${elapsed}\"><failure message=\"missing\">${msg}</failure></testcase>")
    fi
done

TS_END="$(date +%s)"
SUITE_TIME=$((TS_END - TS_START))

{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo "<testsuites name=\"verify-image-contents\" tests=\"${total}\" failures=\"${fails}\" time=\"${SUITE_TIME}\">"
    echo "  <testsuite name=\"image-contents.${MACHINE}\" tests=\"${total}\" failures=\"${fails}\" time=\"${SUITE_TIME}\">"
    for tc in "${TC_XML[@]}"; do
        echo "    $tc"
    done
    echo '  </testsuite>'
    echo '</testsuites>'
} > "$JUNIT"

echo "[verify-image-contents] JUnit -> $JUNIT  (failures=${fails}/${total})" | tee -a "$LOG"

[[ "$fails" -eq 0 ]]
