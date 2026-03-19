# Troubleshooting Guide (TSG)

This guide documents known issues encountered while building the ADU Yocto reference
image and their resolutions. Issues are ordered by the build phase where they occur.

---

## Phase 1: Repository Setup (`setup.sh`)

### TSG-001: setup.sh uses HTTP URLs instead of HTTPS

**Symptom:** Git clone fails or corporate firewalls block connections.

**Root Cause:** Original script used `http://` URLs for GitHub repos.

**Fix Applied:** All URLs changed to `https://` in `scripts/setup.sh`.

**If you hit this on an older branch:**
```bash
# Replace http:// with https:// in setup.sh
sed -i 's|http://github.com|https://github.com|g' scripts/setup.sh
```

---

### TSG-002: setup.sh re-clones itself and fails

**Symptom:** `setup.sh` tries to clone the parent repo into itself, causing directory conflicts.

**Root Cause:** The script's self-clone logic used wrong SSH URL syntax (slash instead of colon)
and didn't check if the repo already existed.

**Fix Applied:** Added `clone_if_missing()` helper for idempotent cloning; fixed SSH URL syntax.

---

### TSG-003: meta-dotnet-core clone fails — repo not found

**Symptom:**
```
fatal: repository 'https://github.com/dotnet/meta-dotnet-core.git' not found
```

**Root Cause:** The correct repo is `RDunkley/meta-dotnet-core`, not `dotnet/meta-dotnet-core`.
Also, the `--branch` flag referenced a non-existent branch.

**Fix Applied:** Updated to correct repo URL; removed `--branch` flag (uses default branch).

---

## Phase 2: Dependency Installation (`install-deps.sh`)

### TSG-004: install-deps.sh fails on Ubuntu 24.04

**Symptom:** `apt-get install` fails with unresolvable packages:
```
E: Unable to locate package libegl1-mesa
E: Unable to locate package libsdl1.2-dev
```

**Root Cause:** Ubuntu 24.04 replaced several packages:
- `libegl1-mesa` → `libegl-dev`
- `libsdl1.2-dev` → `libsdl2-dev`
- `libncurses5-dev` → `libncurses-dev`

**Fix Applied:** Version-specific package selection in `install-deps.sh`:
```bash
case "$VERSION_ID" in
    24.04) EGL_PKG="libegl-dev"; SDL_PKG="libsdl2-dev" ;;
    *)     EGL_PKG="libegl1-mesa"; SDL_PKG="libsdl1.2-dev" ;;
esac
```

---

### TSG-005: BitBake fails with user namespace error on Ubuntu 24.04

**Symptom:**
```
ERROR: OE-core's config sanity checker detected a potential misconfiguration.
The kernel does not allow unprivileged user namespaces.
```

**Root Cause:** Ubuntu 24.04 ships with AppArmor restricting unprivileged user namespaces
(`kernel.apparmor_restrict_unprivileged_userns=1`), which BitBake requires for pseudo/fakeroot.

**Fix (persistent across reboots):**
```bash
echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee /etc/sysctl.d/99-bitbake-userns.conf
sudo sysctl --system
```

**Verify:**
```bash
sysctl kernel.apparmor_restrict_unprivileged_userns
# Expected output: kernel.apparmor_restrict_unprivileged_userns = 0
```

**Note:** `install-deps.sh` now detects this condition and prompts you to apply the fix.

---

## Phase 3: Signing Key Setup

### TSG-006: adu-pub-key fails — Can't open /keys/priv.pass

**Symptom:**
```
ERROR: adu-pub-key-1.0-r0 do_compile: ExecutionError(...)
Can't open file /keys/priv.pass
Error getting passwords
```

**Root Cause:** When using kas, the `ADUC_PRIVATE_KEY` and `ADUC_PRIVATE_KEY_PASSWORD`
environment variables were set using `${KAS_WORK_DIR}` in the kas `env:` section. However,
BitBake does not expand kas-specific variables — the literal string `${KAS_WORK_DIR}` was
passed as the path.

**Fix Applied:** Moved key path configuration from `env:` to `local_conf_header:` in
`kas-base.yml`, using BitBake's `${TOPDIR}` variable which expands correctly:
```yaml
local_conf_header:
  signing-keys: |
    ADUC_PRIVATE_KEY = "${TOPDIR}/../keys/priv.pem"
    ADUC_PRIVATE_KEY_PASSWORD = "${TOPDIR}/../keys/priv.pass"
```

**If you hit this with a custom kas config:**
Ensure key paths use `${TOPDIR}` (BitBake variable) rather than `${KAS_WORK_DIR}` (kas variable).

---

## Phase 4: Build

### TSG-007: diffgentool killed during v1→v3 delta generation (OOM)

**Symptom:**
```
ERROR: diffgentool failed
Killed
```
Build fails at `do_generate_delta_v1_v3` task. Sequential deltas (v1→v2, v2→v3) succeed.

**Root Cause:** The diffgentool (C# .NET) processes two ~218MB SWU files containing compressed
rootfs images. During decompression and diff computation, memory usage spikes above what is
available on machines with <8GB RAM. The Linux OOM killer terminates the process.

**Evidence:**
```bash
# Check for OOM events (may require sudo)
journalctl -k | grep -i "oom\|killed"
dmesg | grep -i "oom\|killed"
```

**Fix Applied:** Added `ADU_GENERATE_V1_V3_DELTA` variable to `adu-delta-image.bb`:
```bitbake
# In local.conf or kas config:
ADU_GENERATE_V1_V3_DELTA = "0"   # Skip v1→v3 on low-memory hosts
ADU_GENERATE_V1_V3_DELTA = "1"   # Enable on hosts with ≥8GB RAM (default)
```

The `kas-delta.yml` sets this to `"0"` by default. Sequential deltas (v1→v2, v2→v3) are
always generated — they cover the standard update path.

**Alternative fixes:**
- Add swap space (recommended: total RAM + swap ≥ 8GB):
  ```bash
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
  ```
- Use a build host with ≥8GB RAM

**Memory requirements:**
| Delta Pair | Minimum RAM+Swap |
|---|---|
| v1→v2 (sequential) | ~4GB |
| v2→v3 (sequential) | ~4GB |
| v1→v3 (skip delta) | ~8GB |

---

### TSG-008: kas warning — "Falling back to file-relative addressing"

**Symptom:**
```
WARNING - Falling back to file-relative addressing of local include "kas-debug.yml"
WARNING - Update your layer to repo-relative addressing to avoid this warning
```

**Root Cause:** kas 5.x prefers repo-relative include paths. Our `kas-base.yml` includes
`kas-debug.yml` using a file-relative path.

**Impact:** Warning only — build succeeds.

**Fix:** Change include paths in `kas-base.yml` from file-relative to repo-relative:
```yaml
# Before (file-relative):
includes:
  - kas-debug.yml

# After (repo-relative):
includes:
  - repo: iot-hub-device-update-yocto
    path: kas/kas-debug.yml
```

---

### TSG-009: "Multiple providers are available for runtime adu-log-dir"

**Symptom:**
```
NOTE: Multiple providers are available for runtime adu-log-dir
(adu-log-dir, adu-config-setup)
Consider defining a PREFERRED_RPROVIDER entry to match adu-log-dir
```

**Impact:** Warning only — BitBake picks one provider automatically.

**Fix:** Add to `local.conf` (or kas `local_conf_header`):
```bitbake
PREFERRED_RPROVIDER_adu-log-dir = "adu-log-dir"
```

---

## Quick Reference

| TSG | Phase | Symptom | Severity |
|-----|-------|---------|----------|
| 001 | Setup | HTTP URLs fail | Fixed in setup.sh |
| 002 | Setup | Self-clone conflict | Fixed in setup.sh |
| 003 | Setup | meta-dotnet-core not found | Fixed in setup.sh |
| 004 | Deps | Package not found (24.04) | Fixed in install-deps.sh |
| 005 | Deps | User namespace error (24.04) | Requires one-time sysctl fix |
| 006 | Build | /keys/priv.pass not found | Fixed in kas-base.yml |
| 007 | Build | diffgentool OOM killed | Config: `ADU_GENERATE_V1_V3_DELTA` |
| 008 | Build | kas include warning | Cosmetic — no action needed |
| 009 | Build | Multiple providers warning | Cosmetic — optional fix |
