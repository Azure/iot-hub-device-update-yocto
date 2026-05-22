# Manual QEMU end-to-end guide for the ADU base image

This guide walks you through booting the qemuarm64 ADU base image on a Linux
host, connecting it to a real Azure Device Update (ADU) service instance, and
driving a full update lifecycle (deploy v1 → v2 delta → v3 delta) from the
Azure portal. It is intentionally written in plain ASCII so it reads cleanly
without a markdown viewer.

If you only want to validate that the image boots and the SWUpdate flow works
*without* the cloud service, use `scripts/run-qemu-e2e.sh` (published in the
same artifact directory) instead — it does everything below in batch mode and
exits 0/non-zero.

```
+--------------------------------------------------------------+
|                       Quick reference                        |
+--------------------------------------------------------------+
| Host SSH port forward .... 2222 -> guest 22                  |
| Guest login ............. root (no password; debug-tweaks)   |
| Config file ............. /adu/etc/du-config.json            |
| Agent service ........... deviceupdate-agent.service         |
| Agent binary ............ /usr/bin/AducIotAgent              |
| Agent logs .............. /adu/logs/                         |
| Staging dir (uploads) ... /adu/staging/                      |
| A/B update script ....... /usr/lib/adu/yocto-a-b-update.sh   |
| Active root ............. findmnt -nro SOURCE /              |
| Installed version ....... cat /etc/adu-version               |
+--------------------------------------------------------------+
```

---

## 1. Prerequisites

On your Linux host (Ubuntu 22.04 / WSL2 works; any distro with QEMU 6+ is
fine):

```
sudo apt-get install -y qemu-system-aarch64 openssh-client jq
```

You need the following files from this artifact bundle (all in
`<MACHINE>-base-image-artifacts/`):

```
  adu-base-image-qemuarm64.rootfs-<timestamp>.wic   (the disk image, ~4 GB)
  u-boot-qemuarm64-<timestamp>.bin                  (U-Boot firmware)
  run-qemu-e2e.sh                                   (optional, batch harness)
```

For the update lifecycle (Section 6+) you also need, from
`<MACHINE>-update-artifacts/`:

```
  adu-update-image-v1-<ts>.swu
  adu-update-image-v1-<ts>-recompressed.swu
  adu-update-image-v2-<ts>.swu
  adu-update-image-v2-<ts>-recompressed.swu
  adu-update-image-v2-<ts>-recompressed.swu.sha256
  adu-update-image-v3-<ts>-recompressed.swu
  adu-update-image-v3-<ts>-recompressed.swu.sha256
  adu-delta-v1-to-v2-<ts>.diff
  adu-delta-v2-to-v3-<ts>.diff
```

…and from `<MACHINE>-samples-artifacts/`:

```
  *.importmanifest.json                  (one per version — upload to ADU)
  adu-delta-test-package.tar.gz          (everything bundled, optional)
```

---

## 2. Boot the image

The wic image holds firmware (efi-partition) + rootfs A + rootfs B + /adu.
Pass the wic via `-drive virtio` and U-Boot via `-bios`:

```
WIC=adu-base-image-qemuarm64.rootfs-20260522030130.wic   # adjust timestamp
UBOOT=u-boot-qemuarm64-20260522030130.bin                # adjust timestamp

qemu-system-aarch64 \
    -machine virt -cpu cortex-a57 -m 2048 -nographic \
    -bios "$UBOOT" \
    -drive file="$WIC",format=raw,if=none,id=hd0 \
    -device virtio-blk-device,drive=hd0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0
```

Notes:

  * `-nographic` routes the serial console to your terminal. To exit the
    guest: `Ctrl-A`, then `x`. Useful if SSH is unavailable.
  * The image uses U-Boot's `bootcount`/`upgrade_available` for A/B; on first
    boot it lands on rootfs A. The active slot is visible at any time with
    `findmnt -nro SOURCE /`.
  * Memory at 2048 MB is the floor — ADU agent + SWUpdate + bspatch can
    spike north of 1.5 GB on a v2/v3 delta install.

Boot takes ~30-60 s on a fast host. You should see the login prompt on the
serial console:

```
   Poky (Yocto Project Reference Distro) <version> adu-qemuarm64 ttyAMA0
   adu-qemuarm64 login:
```

---

## 3. Log in over SSH

`debug-tweaks` is enabled, so root has no password. Use this SSH options
bundle for all interaction — it skips known-hosts pollution and host-key
prompts that block the first connection:

```
SSH="ssh -p 2222 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    root@localhost"

SCP="scp -P 2222 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR"

$SSH 'uname -a; cat /etc/adu-version; findmnt -nro SOURCE /'
```

Expected output on a fresh boot:

```
   Linux adu-qemuarm64 6.6.x ...
   0.0.1.0                              # base ADU_SOFTWARE_VERSION
   /dev/vda3                            # rootfs A (vda4 = rootfs B)
```

If SSH hangs at "banner exchange", the agent host keys may not have been
generated yet — wait ~30 s and retry, or check `journalctl -u sshd-keygen`
inside the guest via the serial console.

---

## 4. Transfer files to and from the guest

Anything you scp into `/adu/staging/` will survive A/B switches because
`/adu` is a separate, persistent partition.

```
# Push a file
$SCP myfile.bin root@localhost:/adu/staging/

# Pull a file
$SCP root@localhost:/adu/logs/aduc.log .

# Pull a directory (e.g. all agent logs)
$SCP -r root@localhost:/adu/logs/ ./guest-logs/
```

For larger transfers prefer tar over scp; it pipelines better and survives
the ~3 MB/s virtio-net ceiling more gracefully:

```
$SSH 'tar -czf - /adu/logs' > guest-logs.tar.gz
```

---

## 5. Configure the ADU agent (du-config.json)

The agent reads `/adu/etc/du-config.json` on startup. At first boot the
adu-oobe service copies a placeholder template (model = contoso /
raspberrypi-yocto-adu-poc-1, connectionData = HostName=placeholder). You
must replace the `connectionData` with a real device connection string from
your IoT Hub before the agent will talk to ADU.

### 5.1 Get a connection string

In the Azure portal:

  1. Open your IoT Hub.
  2. Devices → +Add — name the device anything (e.g. `qemu-adu-poc-01`).
  3. Click into the device → copy "Primary Connection String". It looks like:

```
HostName=<hub>.azure-devices.net;DeviceId=qemu-adu-poc-01;SharedAccessKey=<base64>
```

### 5.2 Push the config to the device

Edit `du-config.json` on the host with your connection string, then push:

```
cat > du-config.json <<'JSON'
{
  "schemaVersion": "1.2",
  "aduShellTrustedUsers": [ "adu", "do" ],
  "manufacturer": "contoso",
  "model": "qemuarm64-yocto-adu-poc-1",
  "agents": [
    {
      "name": "main",
      "runas": "adu",
      "connectionSource": {
        "connectionType": "string",
        "connectionData": "HostName=<hub>.azure-devices.net;DeviceId=qemu-adu-poc-01;SharedAccessKey=<base64>"
      },
      "manufacturer": "contoso",
      "model": "qemuarm64-yocto-adu-poc-1"
    }
  ]
}
JSON

$SCP du-config.json root@localhost:/adu/etc/du-config.json
$SSH 'chown adu:adu /adu/etc/du-config.json && chmod 600 /adu/etc/du-config.json'
$SSH 'systemctl restart deviceupdate-agent.service'
```

The `manufacturer` and `model` in this file are the deployment-group keys
used by ADU to match update payloads to devices. They must match the
`compatibility` block in the importmanifest.json files you upload to ADU
(see Section 6). The samples we ship use:

  * manufacturer: `contoso`
  * model:        `qemuarm64-yocto-adu-poc-1`

### 5.3 Verify the agent connected

```
$SSH 'systemctl status deviceupdate-agent.service --no-pager'
$SSH 'tail -n 50 /adu/logs/aduc.log'
```

You should see lines such as `IoTHub Device Twin: Status=200` and `DeviceUpdate:
Registered for service updates`. The device will then appear in your IoT Hub
device list with the ADU twin properties populated.

---

## 6. Upload updates to the ADU service

In the Azure portal, under your IoT Hub → Device Update → Updates:

  1. Click "+ Import a new update".
  2. Choose "Select from a storage container" or upload directly.
  3. Upload, *for each version*, the two files together:

```
   v1.0.0.1:  update-1.0.0.1.importmanifest.json
              adu-update-image-v1-<ts>.swu
   v1.0.0.2:  update-1.0.0.2.importmanifest.json
              adu-update-image-v2-<ts>.swu               (or .diff for delta)
              delta-manifest-v1-to-v2.importmanifest.json (for delta path)
   v1.0.0.3:  update-1.0.0.3.importmanifest.json
              adu-update-image-v3-<ts>.swu               (or .diff for delta)
              delta-manifest-v2-to-v3.importmanifest.json (for delta path)
```

The `adu-delta-test-package.tar.gz` bundle contains all of these in one
archive under `update-1.0.0/`, `update-2.0.0/`, `update-3.0.0/` — useful if
you'd rather extract once and drag-drop.

Wait a few minutes for ADU to validate the import (status flips from
"Importing" to "Ready to deploy").

---

## 7. Deploy v1 (full update)

In the portal:

  1. Device Update → Groups and Deployments → tag your device into a group
     (or use the default `Uncategorized` group).
  2. Find the group → "Deploy update" → pick the `1.0.0.1` update.
  3. Click "Create deployment".

On the device side, watch the agent pick it up:

```
$SSH 'journalctl -u deviceupdate-agent.service -f'
```

You'll see the download → install → reboot sequence (roughly: 1 GB SWU
download over hostfwd, ~2 min install via SWUpdate, then `reboot`).

After QEMU comes back up:

```
$SSH 'cat /etc/adu-version; findmnt -nro SOURCE /'
```

Should now report:

```
   1.0.0.1
   /dev/vda4                            # flipped from vda3 to vda4
```

---

## 8. Deploy v2 (delta update)

Same flow in the portal, deploy `1.0.0.2`. ADU will route the delta-manifest
payload to the delta download handler which:

  1. Downloads `adu-delta-v1-to-v2.diff` (kilobytes, not gigabytes).
  2. Reads the cached `v1-recompressed.swu` from `/adu/.delta-source-cache/`
     (auto-populated during v1 install).
  3. Reconstructs `v2.swu` via bspatch.
  4. Hands the synthesized SWU to SWUpdate for normal install.

Watch for these phases in `/adu/logs/aduc.log`:

```
   delta-download-handler: source SHA256 verified
   delta-download-handler: applying patch
   swupdate: Software updated successfully
```

After reboot:

```
$SSH 'cat /etc/adu-version'             # 1.0.0.2
```

## 9. Deploy v3 (second delta — confirms delta chain works)

Repeat for `1.0.0.3`. The same delta path applies, this time using the v2
recompressed SWU (cached during the v2 install) as the bspatch source.

```
$SSH 'cat /etc/adu-version'             # 1.0.0.3
```

If all three versions install cleanly with no slot bounce-back, your image,
your delta pipeline, and your ADU service config are all working end to end.

---

## 10. Where to find logs (and what they contain)

```
/adu/logs/                        Agent + extension logs. Survives A/B.
    aduc.log                      Main agent log. Service connection,
                                  workflow state, install results.
    diagnostics.log               Diagnostics agent log (heartbeat,
                                  telemetry uploads).
    do-agent.log                  Delivery Optimization download log.
    extensions/                   Per-extension logs (e.g. download
                                  handlers, content handlers).
    update.log                    SWUpdate native log when invoked
                                  via the swupdate content handler.

/var/log/                         Generic system / journal logs.
    journal/                      Persistent systemd journal (if enabled).

/boot/adu-diags/                  Fallback diagnostics written during
                                  early-boot OOBE before /adu is mounted.
    oobe-failure.log              Errors from setup-adu-dirs.sh.
    oobe-snapshot.txt             Mount table / partition layout snapshot.
```

### Common diagnostic one-liners

```
# Last 200 lines of agent activity
$SSH 'tail -n 200 /adu/logs/aduc.log'

# Agent service status (running, last exit, recent journal lines)
$SSH 'systemctl status deviceupdate-agent.service --no-pager -l'

# Live agent journal
$SSH 'journalctl -u deviceupdate-agent.service -f'

# Did SWUpdate succeed / fail in the last install?
$SSH 'journalctl -u swupdate.service -n 200 --no-pager'

# Which slot booted? Did fallback fire?
$SSH 'fw_printenv bootcount upgrade_available BOOT_ORDER mender_boot_part \
        2>/dev/null || true'

# Was there a watchdog reboot?
$SSH 'last reboot | head; journalctl -k -b -1 --no-pager | tail -n 50'

# Boot validation script log
$SSH 'journalctl -u adu-boot-validation.service --no-pager'

# Capture *everything* relevant into a tarball on the host
$SSH 'tar -czf - /adu/logs /boot/adu-diags /etc/adu-version \
        /etc/adu/board.conf 2>/dev/null' > device-diag-$(date +%s).tar.gz
```

---

## 11. Resetting and re-running

To wipe state and re-test from scratch, simply `Ctrl-A x` out of QEMU and
re-run the command from Section 2 against a *fresh copy* of the wic file —
QEMU mutates the wic in place, so always keep a pristine copy aside:

```
cp adu-base-image-qemuarm64.rootfs-<ts>.wic ./pristine.wic
# work against a throwaway clone:
cp ./pristine.wic ./session.wic
# (use session.wic in the qemu-system-aarch64 command)
```

To only reset `/adu` (preserve rootfs slots), boot the image, then:

```
$SSH 'systemctl stop deviceupdate-agent.service
      rm -rf /adu/logs/* /adu/staging/* /adu/.delta-source-cache/*
      rm -f /adu/.setup-version /adu/etc/du-config.json
      reboot'
```

`adu-oobe.service` will re-bootstrap `/adu/etc/du-config.json` from the
template at next boot.

---

## 12. Troubleshooting checklist

| Symptom                                   | First thing to check                                                  |
|-------------------------------------------|-----------------------------------------------------------------------|
| SSH refused on :2222                      | Boot still in progress — wait 60s. Then check serial console.         |
| SSH banner-exchange timeout               | Host keys still generating. `journalctl -u sshd-keygen` on serial.    |
| Agent shows "auth failed"                 | Bad connection string. Re-copy from portal verbatim, restart service. |
| Agent shows "Device not found"            | Device not registered in IoT Hub, or DeviceId mismatch.               |
| Deployment never reaches device           | Group tag missing. Check IoT Hub device twin for `tags.group`.        |
| Install fails: "no source SWU"            | Delta source cache missing v(n-1)-recompressed.swu. Re-deploy v1.     |
| Reboots back to old slot                  | Watchdog tripped boot validation. Inspect adu-boot-validation log.    |
| `/adu` shown missing                      | fstab misconfiguration; see /boot/adu-diags/oobe-failure.log.         |

---

## Appendix A. Useful guest commands

```
# Manually drive an A/B update without ADU service (sanity)
yocto-a-b-update.sh install-full /adu/staging/v1.swu

# Confirm boot success (resets bootcount; called by adu-boot-validation)
adu-confirm-boot

# Show A/B environment
fw_printenv

# Detail of every active update extension
ls -la /var/lib/adu/extensions/sources/
cat /var/lib/adu/extensions/manifests/*.json 2>/dev/null
```

## Appendix B. Useful host commands (against running guest)

```
# Health snapshot — single line, parseable
$SSH 'echo "version=$(cat /etc/adu-version) root=$(findmnt -nro SOURCE /) \
       agent=$(systemctl is-active deviceupdate-agent.service) \
       uptime=$(awk "{print \$1}" /proc/uptime)s"'

# Watch agent state machine in real time
$SSH 'journalctl -u deviceupdate-agent.service -f -o cat | \
        grep -E "Workflow|State|Result|Install|Download"'
```
