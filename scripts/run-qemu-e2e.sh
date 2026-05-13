#!/bin/bash
# run-qemu-e2e.sh — In-emulator e2e SWUpdate validator for the qemuarm64 ADU
# image. Validates two full update lifecycles end-to-end, with no ADU service:
#
#   Stage 0:  Sanity-boot the freshly built image, prove /etc/adu-version
#             equals the base ADU_SOFTWARE_VERSION (default 0.0.1.0).
#   Stage 1:  Push adu-update-image-v1*.swu (+ recompressed source) into the
#             guest, install it to the inactive slot, reboot, verify
#             /etc/adu-version == 1.0.0.1 and findmnt shows the flipped slot,
#             confirm boot.
#   Stage 2:  Push adu-delta-v1_v2.diff into the guest, reconstruct the v2 SWU
#             from the cached v1-recompressed source + diff, install, reboot,
#             verify /etc/adu-version == 1.0.0.2, confirm boot.
#
# Communication with the guest uses the SSH port forward set up by the QEMU
# launch (-netdev user,hostfwd=tcp::${SSH_PORT}-:22). The image enables
# debug-tweaks so the root account has no password.
#
# Usage:
#   ./scripts/run-qemu-e2e.sh [deploy-dir] [output-dir]
#
# Exits 0 only if all stages pass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DEFAULT="${SCRIPT_DIR}/../build/tmp/deploy/images/qemuarm64"
DEPLOY="${1:-$DEPLOY_DEFAULT}"
OUT_DIR="${2:-${TMPDIR:-/tmp}/qemu-e2e-$$}"

# Fall back to the alternate kas build dir if the default is missing.
if [[ ! -d "$DEPLOY" ]]; then
    ALT="${SCRIPT_DIR}/../build_qemu/tmp/deploy/images/qemuarm64"
    [[ -d "$ALT" ]] && DEPLOY="$ALT"
fi
if [[ ! -d "$DEPLOY" ]]; then
    echo "ERROR: deploy dir not found: $DEPLOY" >&2
    exit 2
fi

mkdir -p "$OUT_DIR"
echo "============================================"
echo "QEMU e2e SWUpdate validation"
echo "============================================"
echo "  Deploy dir: $DEPLOY"
echo "  Logs:       $OUT_DIR"
echo ""

UBOOT="$(ls "$DEPLOY"/u-boot-qemuarm64-*.bin 2>/dev/null | head -1)"
WIC_ORIG="$(ls "$DEPLOY"/adu-base-image-qemuarm64.rootfs-*.wic 2>/dev/null | head -1)"
SWU_V1="$(ls "$DEPLOY"/adu-update-image-v1-[0-9]*.swu 2>/dev/null | head -1)"
SWU_V1_RECOMP="$(ls "$DEPLOY"/adu-update-image-v1*-recompressed.swu 2>/dev/null | head -1)"
DELTA_V1_V2="$(ls "$DEPLOY"/adu-delta-v1-to-v2*.diff 2>/dev/null | head -1)"
SWU_V2="$(ls "$DEPLOY"/adu-update-image-v2-[0-9]*.swu 2>/dev/null | head -1)"
SWU_V2_RECOMP="$(ls "$DEPLOY"/adu-update-image-v2*-recompressed.swu 2>/dev/null | head -1)"
SWU_V3="$(ls "$DEPLOY"/adu-update-image-v3-[0-9]*.swu 2>/dev/null | head -1)"
DELTA_V2_V3="$(ls "$DEPLOY"/adu-delta-v2-to-v3*.diff 2>/dev/null | head -1)"
SWU_V2_RECOMP_SHA="$(ls "$DEPLOY"/adu-update-image-v2*-recompressed.swu.sha256 2>/dev/null | head -1)"
SWU_V3_RECOMP="$(ls "$DEPLOY"/adu-update-image-v3*-recompressed.swu 2>/dev/null | head -1)"
SWU_V3_RECOMP_SHA="$(ls "$DEPLOY"/adu-update-image-v3*-recompressed.swu.sha256 2>/dev/null | head -1)"

missing=()
[[ -n "$UBOOT"         ]] || missing+=("u-boot-qemuarm64-*.bin")
[[ -n "$WIC_ORIG"      ]] || missing+=("adu-base-image-qemuarm64.rootfs-*.wic")
[[ -n "$SWU_V1"        ]] || missing+=("adu-update-image-v1-[0-9]*.swu")
[[ -n "$SWU_V1_RECOMP" ]] || missing+=("adu-update-image-v1*-recompressed.swu (need kas/delta.yml + adu-delta-image)")
[[ -n "$DELTA_V1_V2"   ]] || missing+=("adu-delta-v1-to-v2*.diff (need adu-delta-image)")
[[ -n "$SWU_V2"        ]] || missing+=("adu-update-image-v2-[0-9]*.swu")
[[ -n "$SWU_V2_RECOMP" ]] || missing+=("adu-update-image-v2*-recompressed.swu (need adu-delta-image)")
[[ -n "$SWU_V3"        ]] || missing+=("adu-update-image-v3-[0-9]*.swu")
[[ -n "$DELTA_V2_V3"   ]] || missing+=("adu-delta-v2-to-v3*.diff (need adu-delta-image)")
[[ -n "$SWU_V3_RECOMP" ]] || missing+=("adu-update-image-v3*-recompressed.swu (need adu-delta-image)")
[[ -n "$SWU_V3_RECOMP_SHA" ]] || missing+=("adu-update-image-v3*-recompressed.swu.sha256 (need adu-delta-image)")
if (( ${#missing[@]} )); then
    echo "ERROR: missing artifacts in $DEPLOY:" >&2
    for m in "${missing[@]}"; do echo "  - $m" >&2; done
    exit 3
fi

echo "  U-Boot:           $(basename "$UBOOT")"
echo "  WIC:              $(basename "$WIC_ORIG")"
echo "  v1 .swu:          $(basename "$SWU_V1")"
echo "  v1 recompressed:  $(basename "$SWU_V1_RECOMP")"
echo "  v1->v2 diff:      $(basename "$DELTA_V1_V2")"
echo "  v2 .swu:          $(basename "$SWU_V2")"
echo "  v2 recompressed:  $(basename "$SWU_V2_RECOMP")"
echo "  v3 .swu:          $(basename "$SWU_V3")"
echo "  v2->v3 diff:      $(basename "$DELTA_V2_V3")"
echo ""

# Working copies — keep originals untouched.
WIC="$OUT_DIR/disk.wic"
F0="$OUT_DIR/flash0.img"
F1="$OUT_DIR/flash1.img"
SERIAL_LOG="$OUT_DIR/serial.log"
FLASH_SIZE=64
SSH_PORT=2222

QEMU_PID=""
QEMU_IN_FIFO="$OUT_DIR/qemu-stdin.fifo"

# A throwaway SSH keypair injected into the guest at first boot so subsequent
# commands authenticate via pubkey (debug-tweaks gives root an empty password,
# but OpenSSH client + BatchMode refuses empty-password auth).
SSH_KEY="$OUT_DIR/id_ed25519"
if [[ ! -f "$SSH_KEY" ]]; then
    ssh-keygen -q -t ed25519 -N "" -f "$SSH_KEY"
fi
SSH_PUB="$(cat "${SSH_KEY}.pub")"

cleanup() {
    if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$QEMU_PID" 2>/dev/null || true
    fi
    [[ -p "$QEMU_IN_FIFO" ]] && rm -f "$QEMU_IN_FIFO"
}
trap cleanup EXIT

reset_pflash() {
    dd if=/dev/zero of="$F0" bs=1M count=$FLASH_SIZE status=none
    dd if="$UBOOT" of="$F0" conv=notrunc status=none
    dd if=/dev/zero of="$F1" bs=1M count=$FLASH_SIZE status=none
}

# Boot QEMU in the background, return when SSH responds (or fail after timeout).
# Injects a pubkey into root's authorized_keys on every boot via the serial
# console (debug-tweaks empty-password login) because each post-install reboot
# lands on a fresh rootfs from the .swu without our key.
boot_guest() {
    local stage="$1"
    : > "$SERIAL_LOG"
    echo "[$stage] booting QEMU..."

    [[ -p "$QEMU_IN_FIFO" ]] || mkfifo "$QEMU_IN_FIFO"
    # Hold the FIFO open for writing through the QEMU lifetime.
    # Open read-write (<>) so it doesn't block waiting for the reader.
    exec 9<>"$QEMU_IN_FIFO"

    # shellcheck disable=SC2086
    setsid qemu-system-aarch64 \
        -machine virt -cpu cortex-a57 -m 2048 -nographic \
        -drive if=pflash,format=raw,file="$F0",unit=0 \
        -drive if=pflash,format=raw,file="$F1",unit=1 \
        -drive if=none,file="$WIC",format=raw,id=hd0 \
        -device virtio-blk-pci,drive=hd0 \
        -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
        -device virtio-net-pci,netdev=net0 \
        -rtc base=utc,clock=host \
        < "$QEMU_IN_FIFO" > "$SERIAL_LOG" 2>&1 &
    QEMU_PID=$!

    echo "[$stage] waiting for serial login prompt..."
    local waited=0
    while (( waited < 240 )); do
        if grep -q "login:" "$SERIAL_LOG" 2>/dev/null; then break; fi
        sleep 2; waited=$(( waited + 2 ))
    done
    if (( waited >= 240 )); then
        echo "[$stage] FAIL: no login prompt within 240s" >&2
        tail -80 "$SERIAL_LOG" >&2 || true
        return 1
    fi

    # Inject pubkey via serial.
    {
        sleep 1; printf 'root\n'
        sleep 2; printf 'mkdir -p /root/.ssh && chmod 700 /root/.ssh\n'
        sleep 1; printf 'printf "%%s\\n" "%s" > /root/.ssh/authorized_keys\n' "$SSH_PUB"
        sleep 1; printf 'chmod 600 /root/.ssh/authorized_keys\n'
        sleep 1; printf 'sync\n'
        sleep 1; printf 'echo E2E_KEY_INJECTED\n'
    } >&9
    local k=0
    while (( k < 30 )); do
        grep -q "E2E_KEY_INJECTED" "$SERIAL_LOG" 2>/dev/null && break
        sleep 1; k=$(( k + 1 ))
    done
    if ! grep -q "E2E_KEY_INJECTED" "$SERIAL_LOG"; then
        echo "[$stage] FAIL: key-injection marker not seen" >&2
        tail -40 "$SERIAL_LOG" >&2 || true
        return 1
    fi
    echo "[$stage] SSH key injected via serial"

    waited=0
    while (( waited < 120 )); do
        if ssh_run "true" >/dev/null 2>&1; then
            echo "[$stage] SSH up after ${waited}s post-inject"
            return 0
        fi
        sleep 3; waited=$(( waited + 3 ))
    done
    echo "[$stage] FAIL: guest SSH not reachable after key inject" >&2
    tail -60 "$SERIAL_LOG" >&2 || true
    return 1
}

shutdown_guest() {
    local stage="$1"
    echo "[$stage] shutting guest down (poweroff -f)..."
    ssh_run "sync; nohup sh -c 'sleep 1; poweroff -f' >/dev/null 2>&1 &" || true
    local waited=0
    while kill -0 "$QEMU_PID" 2>/dev/null; do
        sleep 1
        waited=$(( waited + 1 ))
        if (( waited > 30 )); then
            echo "[$stage] guest didn't power off in 30s; killing"
            kill "$QEMU_PID" 2>/dev/null || true
            break
        fi
    done
    wait "$QEMU_PID" 2>/dev/null || true
    QEMU_PID=""
    exec 9>&- 2>/dev/null || true
}

SSH_OPTS=(-p "$SSH_PORT"
          -i "$SSH_KEY"
          -o IdentitiesOnly=yes
          -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR
          -o ConnectTimeout=5
          -o BatchMode=yes
          -o PreferredAuthentications=publickey
          -o PasswordAuthentication=no)

ssh_run() {
    ssh "${SSH_OPTS[@]}" root@localhost "$@"
}
scp_to_guest() {
    scp -P "$SSH_PORT" \
        -i "$SSH_KEY" -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -o BatchMode=yes \
        -o PreferredAuthentications=publickey -o PasswordAuthentication=no \
        "$@"
}

# --------------------------------------------------------------------------
# Initial setup
# --------------------------------------------------------------------------
echo "[setup] copying fresh WIC + initializing pflash..."
cp "$WIC_ORIG" "$WIC"
reset_pflash

# --------------------------------------------------------------------------
# JUnit XML test result emitter
# --------------------------------------------------------------------------
# Records per-stage outcomes so the pipeline can publish a TestRun (which
# Azure DevOps subsequently exports to Kusto via the standard test result
# ingestion). The XML is written by the EXIT trap so it captures both
# successful runs and mid-stage failures (set -e + non-zero exit).
declare -a JUNIT_RESULTS=()   # entries: "name|status|duration_seconds|message"
declare -i JUNIT_STAGE_START=0
JUNIT_CURRENT_STAGE=""

junit_start() {
    JUNIT_CURRENT_STAGE="$1"
    JUNIT_STAGE_START=$SECONDS
}

junit_pass() {
    local s="${1:-$JUNIT_CURRENT_STAGE}"
    local dur=$(( SECONDS - JUNIT_STAGE_START ))
    JUNIT_RESULTS+=("${s}|pass|${dur}|")
    JUNIT_CURRENT_STAGE=""
}

emit_junit() {
    local rc=$?
    if [[ -n "$JUNIT_CURRENT_STAGE" ]]; then
        local dur=$(( SECONDS - JUNIT_STAGE_START ))
        local msg="Stage '${JUNIT_CURRENT_STAGE}' aborted with exit code ${rc}. See ${OUT_DIR} for per-stage logs."
        JUNIT_RESULTS+=("${JUNIT_CURRENT_STAGE}|fail|${dur}|${msg}")
    fi
    local out="$OUT_DIR/qemu-e2e-junit.xml"
    local total=${#JUNIT_RESULTS[@]}
    local fails=0
    local entry
    for entry in "${JUNIT_RESULTS[@]}"; do
        case "$entry" in *\|fail\|*) fails=$((fails+1));; esac
    done
    local xml_escape='s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo "<testsuites name=\"qemu-e2e\" tests=\"${total}\" failures=\"${fails}\" time=\"${SECONDS}\">"
        echo "  <testsuite name=\"qemu-e2e.swupdate\" tests=\"${total}\" failures=\"${fails}\" time=\"${SECONDS}\">"
        for entry in "${JUNIT_RESULTS[@]}"; do
            IFS='|' read -r name status dur msg <<<"$entry"
            local ename emsg
            ename=$(printf '%s' "$name" | sed "$xml_escape")
            emsg=$(printf '%s' "$msg" | sed "$xml_escape")
            echo "    <testcase classname=\"qemu-e2e.swupdate\" name=\"${ename}\" time=\"${dur}\">"
            if [[ "$status" == "fail" ]]; then
                echo "      <failure message=\"${emsg}\" type=\"AssertionError\">${emsg}</failure>"
            fi
            echo "    </testcase>"
        done
        echo "  </testsuite>"
        echo "</testsuites>"
    } > "$out"
    echo "[junit] wrote $out (${total} tests, ${fails} failures)"
}
trap emit_junit EXIT

# --------------------------------------------------------------------------
# Stage 0 — sanity boot
# --------------------------------------------------------------------------
STAGE="stage0-sanity"
junit_start "$STAGE"
echo ""
echo "=== $STAGE: first boot of base image ==="
boot_guest "$STAGE" || exit 10

BASE_VER="$(ssh_run 'cat /etc/adu-version 2>/dev/null || echo MISSING')"
BASE_ROOT="$(ssh_run 'findmnt -nro SOURCE /')"
echo "[$STAGE] /etc/adu-version = $BASE_VER"
echo "[$STAGE] root device       = $BASE_ROOT"

if [[ "$BASE_ROOT" != "/dev/vda2" ]]; then
    echo "[$STAGE] FAIL: expected initial root /dev/vda2 (rootA), got $BASE_ROOT" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}.log"
    exit 11
fi
if [[ "$BASE_VER" == "MISSING" ]]; then
    echo "[$STAGE] FAIL: /etc/adu-version missing in base image" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}.log"
    exit 12
fi
echo "[$STAGE] PASS"
junit_pass "$STAGE"

# --------------------------------------------------------------------------
# Stage 1 — full install v1
# --------------------------------------------------------------------------
STAGE="stage1-full-v1"
junit_start "$STAGE"
echo ""
echo "=== $STAGE: install adu-update-image-v1 to inactive slot ==="

echo "[$STAGE] uploading artifacts..."
ssh_run "mkdir -p /adu/staging"
scp_to_guest "$SWU_V1"        root@localhost:/adu/staging/v1.swu
scp_to_guest "$SWU_V1_RECOMP" root@localhost:/adu/staging/v1-recompressed.swu

# Place recompressed alongside the v1.swu so install-full picks it up via the
# convention <name>-recompressed.swu (the wrapper renames it).
ssh_run "mv /adu/staging/v1-recompressed.swu /adu/staging/v1-recompressed.swu.tmp && \
         ln -sf /adu/staging/v1-recompressed.swu.tmp /adu/staging/v1-recompressed.swu"

echo "[$STAGE] running adu-e2e-install-full..."
if ! ssh_run "adu-e2e-install-full /adu/staging/v1.swu 1.0.0.1" 2>&1 | tee "$OUT_DIR/${STAGE}-install.log"; then
    echo "[$STAGE] FAIL: install script returned non-zero" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-serial.log"
    exit 20
fi

shutdown_guest "$STAGE"
boot_guest "$STAGE-post" || exit 21

POST_VER="$(ssh_run 'cat /etc/adu-version')"
POST_ROOT="$(ssh_run 'findmnt -nro SOURCE /')"
echo "[$STAGE] post-reboot /etc/adu-version = $POST_VER"
echo "[$STAGE] post-reboot root device       = $POST_ROOT"

if [[ "$POST_ROOT" != "/dev/vda3" ]]; then
    echo "[$STAGE] FAIL: expected /dev/vda3 (rootB) after install, got $POST_ROOT" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-postboot.log"
    exit 22
fi
if [[ "$POST_VER" != "1.0.0.1" ]]; then
    echo "[$STAGE] FAIL: expected /etc/adu-version=1.0.0.1, got $POST_VER" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-postboot.log"
    exit 23
fi

echo "[$STAGE] running adu-e2e-confirm-boot..."
ssh_run "adu-e2e-confirm-boot" | tee "$OUT_DIR/${STAGE}-confirm.log"
echo "[$STAGE] PASS"
junit_pass "$STAGE"

# --------------------------------------------------------------------------
# Stage 2 — delta install v1 -> v2
# --------------------------------------------------------------------------
STAGE="stage2-delta-v1-v2"
junit_start "$STAGE"
echo ""
echo "=== $STAGE: reconstruct + install v2 from cached source + delta ==="

echo "[$STAGE] preparing guest dirs..."
ssh_run 'mkdir -p /adu/staging /adu/.delta-source-cache' || { echo "[$STAGE] FAIL: mkdir on guest"; exit 28; }

echo "[$STAGE] uploading v1-recompressed source SWU ($(stat -c %s "$SWU_V1_RECOMP" 2>/dev/null) bytes)..."
set +e
scp_to_guest "$SWU_V1_RECOMP" root@localhost:/adu/.delta-source-cache/v1-recompressed.swu > "$OUT_DIR/${STAGE}-scp.log" 2>&1
RC=$?
set -e
echo "[$STAGE] v1-recompressed scp rc=$RC"
if [[ $RC -ne 0 ]]; then
    echo "[$STAGE] FAIL: scp of v1-recompressed source failed (rc=$RC)" >&2
    cat "$OUT_DIR/${STAGE}-scp.log" >&2 || true
    exit 28
fi

echo "[$STAGE] uploading delta diff ($(stat -c %s "$DELTA_V1_V2" 2>/dev/null) bytes)..."
set +e
scp_to_guest "$DELTA_V1_V2" root@localhost:/adu/staging/v1_v2.diff >> "$OUT_DIR/${STAGE}-scp.log" 2>&1
RC=$?
set -e
echo "[$STAGE] delta diff scp rc=$RC"
if [[ $RC -ne 0 ]]; then
    echo "[$STAGE] FAIL: scp of delta diff failed (rc=$RC); ssh probe follows" >&2
    ssh_run 'echo ssh-ok; df -h /adu; ls -la /adu/' >&2 || true
    cat "$OUT_DIR/${STAGE}-scp.log" >&2 || true
    exit 29
fi

# We uploaded to a known filename, so resolve directly without relying on ls/head
SRC_REMOTE="/adu/.delta-source-cache/v1-recompressed.swu"
echo "[$STAGE] verifying cached source SWU on guest..."
set +e
ssh_run "test -s '$SRC_REMOTE'"
RC=$?
set -e
echo "[$STAGE] verify rc=$RC SRC_REMOTE='$SRC_REMOTE'"
if [[ $RC -ne 0 ]]; then
    echo "[$STAGE] FAIL: no cached source SWU in /adu/.delta-source-cache" >&2
    exit 30
fi
echo "[$STAGE] cached source: $SRC_REMOTE"

echo "[$STAGE] running adu-e2e-reconstruct-and-install-delta..."
if ! ssh_run "adu-e2e-reconstruct-and-install-delta '$SRC_REMOTE' /adu/staging/v1_v2.diff 1.0.0.2" 2>&1 \
        | tee "$OUT_DIR/${STAGE}-install.log"; then
    echo "[$STAGE] FAIL: delta install script returned non-zero" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-serial.log"
    exit 31
fi

shutdown_guest "$STAGE"
boot_guest "$STAGE-post" || exit 32

POST_VER="$(ssh_run 'cat /etc/adu-version')"
POST_ROOT="$(ssh_run 'findmnt -nro SOURCE /')"
echo "[$STAGE] post-reboot /etc/adu-version = $POST_VER"
echo "[$STAGE] post-reboot root device       = $POST_ROOT"

if [[ "$POST_ROOT" != "/dev/vda2" ]]; then
    echo "[$STAGE] FAIL: expected /dev/vda2 (rootA) after delta install, got $POST_ROOT" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-postboot.log"
    exit 33
fi
if [[ "$POST_VER" != "1.0.0.2" ]]; then
    echo "[$STAGE] FAIL: expected /etc/adu-version=1.0.0.2, got $POST_VER" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-postboot.log"
    exit 34
fi

echo "[$STAGE] running adu-e2e-confirm-boot..."
ssh_run "adu-e2e-confirm-boot" | tee "$OUT_DIR/${STAGE}-confirm.log"
echo "[$STAGE] PASS"

# --------------------------------------------------------------------------
# Stage 3 — handler-driven delta install v2 -> v3
#
# Same logical flow as Stage 2, but the source -> target reconstruction is
# performed by libmicrosoft_delta_download_handler.so (the actual on-device
# handler the ADU agent dlopen()'s in production), exercised by the
# adu-delta-handler-test binary. We then hand the produced v3 SWU to the
# normal install-full helper to land it in rootB and verify boot.
#
# Why also run this when Stage 2 already passed: Stage 2 only proves the
# applydiff CLI / libadudiffapi works. The handler .so is a separate binary
# layered on top of that library; it has its own packaging and loader-level
# concerns (symbol visibility, contract version, registration metadata) and
# is the binary that real devices execute. A regression in the .so would not
# show up in Stage 2.
# --------------------------------------------------------------------------
STAGE="stage3-handler-delta-v2-v3"
junit_start "$STAGE"
echo ""
echo "=== $STAGE: dlopen handler.so to reconstruct v3, then install ==="

# We need a v2-recompressed source on the guest for the handler to consume.
# Stage 2 installed a *reconstructed* v2 SWU (which the install-full helper
# caches under /adu/.delta-source-cache/), but those bytes are NOT identical
# to the build's recompressed v2 SWU — the diff was generated against the
# recompressed form, so the handler must operate on the recompressed form.
# Push it explicitly into the cache here.
echo "[$STAGE] uploading v2-recompressed source + v2->v3 diff + reference SHA..."
ssh_run "mkdir -p /adu/.delta-source-cache /adu/staging" >/dev/null
scp_to_guest "$SWU_V2_RECOMP"     root@localhost:/adu/.delta-source-cache/v2-recompressed.swu
scp_to_guest "$DELTA_V2_V3"       root@localhost:/adu/staging/v2_v3.diff
scp_to_guest "$SWU_V3_RECOMP_SHA" root@localhost:/adu/staging/v3-recompressed.swu.sha256

# Locate the handler .so on the guest. The agent installs it under
# ADUC_EXTENSIONS_INSTALL_DIR (/var/lib/adu/extensions/sources). Resolve at
# runtime so we tolerate path changes.
HANDLER_SO="$(ssh_run 'ls /var/lib/adu/extensions/sources/libmicrosoft_delta_download_handler.so 2>/dev/null | head -n 1')"
if [[ -z "$HANDLER_SO" ]]; then
    HANDLER_SO="$(ssh_run 'find /var/lib/adu /usr -name "libmicrosoft_delta_download_handler*.so" 2>/dev/null | head -n 1')"
fi
if [[ -z "$HANDLER_SO" ]]; then
    echo "[$STAGE] FAIL: libmicrosoft_delta_download_handler.so not found in guest" >&2
    ssh_run 'find / -name "libmicrosoft_delta_download_handler*" 2>/dev/null' \
        | tee "$OUT_DIR/${STAGE}-handler-find.log" >&2 || true
    exit 40
fi
echo "[$STAGE] handler .so on guest: $HANDLER_SO"

echo "[$STAGE] running adu-delta-handler-test (dlopen + ProcessDeltaUpdate)..."
if ! ssh_run "adu-delta-handler-test \
        '$HANDLER_SO' \
        /adu/.delta-source-cache/v2-recompressed.swu \
        /adu/staging/v2_v3.diff \
        /adu/staging/v3-reconstructed.swu \
        /adu/staging/v3-recompressed.swu.sha256" 2>&1 \
        | tee "$OUT_DIR/${STAGE}-handler-test.log"; then
    echo "[$STAGE] FAIL: adu-delta-handler-test returned non-zero" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-serial.log"
    exit 41
fi

echo "[$STAGE] handler reconstruction OK — installing reconstructed v3 SWU..."
if ! ssh_run "adu-e2e-install-full /adu/staging/v3-reconstructed.swu 1.0.0.3" 2>&1 \
        | tee "$OUT_DIR/${STAGE}-install.log"; then
    echo "[$STAGE] FAIL: install-full of handler-produced v3 SWU returned non-zero" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-serial.log"
    exit 42
fi

shutdown_guest "$STAGE"
boot_guest "$STAGE-post" || exit 43

POST_VER="$(ssh_run 'cat /etc/adu-version')"
POST_ROOT="$(ssh_run 'findmnt -nro SOURCE /')"
echo "[$STAGE] post-reboot /etc/adu-version = $POST_VER"
echo "[$STAGE] post-reboot root device       = $POST_ROOT"

# Stage 2 ended on /dev/vda2 (rootA); v3 install should flip back to rootB.
if [[ "$POST_ROOT" != "/dev/vda3" ]]; then
    echo "[$STAGE] FAIL: expected /dev/vda3 (rootB) after handler-delta install, got $POST_ROOT" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-postboot.log"
    exit 44
fi
if [[ "$POST_VER" != "1.0.0.3" ]]; then
    echo "[$STAGE] FAIL: expected /etc/adu-version=1.0.0.3, got $POST_VER" >&2
    cp "$SERIAL_LOG" "$OUT_DIR/${STAGE}-postboot.log"
    exit 45
fi

echo "[$STAGE] running adu-e2e-confirm-boot..."
ssh_run "adu-e2e-confirm-boot" | tee "$OUT_DIR/${STAGE}-confirm.log"

junit_pass "$STAGE"
shutdown_guest "$STAGE"

echo ""
echo "============================================"
echo "QEMU e2e: ALL STAGES PASSED"
echo "  base             -> $BASE_VER on /dev/vda2"
echo "  stage1 v1 full   -> 1.0.0.1 on /dev/vda3"
echo "  stage2 v2 delta  -> 1.0.0.2 on /dev/vda2  (applydiff CLI)"
echo "  stage3 v3 delta  -> 1.0.0.3 on /dev/vda3  (handler.so via dlopen)"
echo "  Logs:               $OUT_DIR"
echo "============================================"
exit 0
