# ADU Delta Update Tools — Customer Distribution Guide

## Overview

Azure Device Update (ADU) supports **delta updates** — bandwidth-efficient OTA updates that transmit only the binary differences between firmware versions instead of full images. This document describes the tools used for delta generation and reconstitution, their dependencies, and how to package them for distribution.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  CLOUD / BUILD HOST                     │
│                                                         │
│   source.swu ──┐                                        │
│                ├──▶ DiffGenTool ──▶ delta.diff         │
│   target.swu ──┘       │                                │
│                        │ P/Invoke                       │
│                    libadudiffapi.so                     │
│                   ┌────┴────┐                           │
│                   │ Native  │                           │
│                   │ Helpers │                           │
│                   └─────────┘                           │
│                   bsdiff, zstd_compress_file,           │
│                   dumpextfs, recompress, ...            │
└─────────────────────────────────────────────────────────┘

                    ▼ delta.diff (small)
                    ▼ transmitted OTA

┌─────────────────────────────────────────────────────────┐
│                     DEVICE                              │
│                                                         │
│   source.swu ──┐                                        │
│                ├──▶ applydiff ──▶ target.swu           │
│   delta.diff ──┘       │                                │
│                        │                                │
│                   libadudiffapi.so                      │
└─────────────────────────────────────────────────────────┘
```

### Two Deliverables

| Package | Purpose | Runs On |
|---------|---------|---------|
| **adu-delta-gen-tools** | Generate delta diffs from source + target SWU files | x86_64 Linux build host |
| **adu-delta-apply-tools** | Reconstitute target from source + delta diff | Device (aarch64) or x86_64 host |

## Tool Inventory

### Delta Generation Tools (Build Host)

| Tool | Type | Description |
|------|------|-------------|
| `DiffGenTool` | .NET 8.0 (self-contained) | Main delta generation entry point. Analyzes source/target SWU archives and produces a binary diff file. |
| `libadudiffapi.so` | C++ shared library | Core diff/patch API. Called by DiffGenTool via P/Invoke and linked by native tools. |
| `bsdiff` | Native executable | Binary diff algorithm (produces patches) |
| `bspatch` | Native executable | Binary patch algorithm (applies patches) |
| `zstd_compress_file` | Native executable | Zstandard compression utility |
| `dumpextfs` | Native executable | Ext4 filesystem structure analysis |
| `recompress` | Native executable | SWU archive recompression (normalizes compression for deterministic diffs) |
| `makecpio` | Native executable | CPIO archive creation |
| `extract` | Native executable | Archive extraction utility |
| `dumpdiff` | Native executable | Diff file inspector (debugging) |

### Reconstitution Tools (Device or Host)

| Tool | Type | Description |
|------|------|-------------|
| `applydiff` | Native executable | Applies a delta diff to a source file to reconstruct the target |
| `libadudiffapi.so` | C++ shared library | Core diff/patch API |

## Runtime Dependencies

### Native Shared Libraries

All tools link against `libadudiffapi.so`, which transitively depends on:

| Library | Version (Yocto Scarthgap) | Purpose | License |
|---------|--------------------------|---------|---------|
| `libadudiffapi.so` | 3.0 | Core ADU diff/patch API | MIT |
| `libz.so.1` | 1.3.1 | Deflate compression (zlib) | zlib |
| `libzstd.so.1` | 1.5.5 | Zstandard compression | BSD-3-Clause |
| `libbz2.so.1` | 1.0.8 | Bzip2 compression (via bsdiff) | bzip2 |
| `libjsoncpp.so.25` | 1.9.5 | JSON serialization | MIT |
| `libgcrypt.so.20` | 1.10.3 | Cryptographic hashing | LGPL-2.1 |
| `libgpg-error.so` | (transitive) | Error handling for libgcrypt | LGPL-2.1 |
| `libfmt.so.10` | 10.2.1 | String formatting | MIT |
| `libconfig.so.11` | 1.7.3 | Configuration file parsing | LGPL-2.1 |
| `libcrypto.so.3` | 3.x (OpenSSL) | Cryptographic operations | Apache-2.0 |
| `libssl.so.3` | 3.x (OpenSSL) | TLS/SSL (transitive) | Apache-2.0 |

### DiffGenTool Additional Dependencies

| Dependency | Notes |
|------------|-------|
| .NET 8.0 Runtime | Embedded in self-contained single-file publish |
| Newtonsoft.Json 13.0.3 | JSON handling (NuGet, embedded) |
| Microsoft.Extensions.Logging 9.0.0 | Logging framework (NuGet, embedded) |
| System.Text.Json 9.0.0 | JSON serialization (NuGet, embedded) |

### Static Libraries (No Runtime Dependency)

| Library | Notes |
|---------|-------|
| `libbsdiff.a` | Statically linked into `libadudiffapi.so` — no separate .so needed |

## Packaging & Distribution

### Recommended: Docker/OCI Container (Primary)

For broadest compatibility, distribute the tools as a Docker image:

```bash
# Generate a delta
docker run --rm -v /path/to/swus:/data adu-delta-gen-tools \
    diffgentool /data/source.swu /data/target.swu /data/delta.diff /data/work

# Apply a delta (reconstitute target)
docker run --rm -v /path/to/files:/data adu-delta-apply-tools \
    applydiff /data/source.swu /data/delta.diff /data/target-reconstructed.swu
```

### Alternative: Self-Contained Tarball

For environments where Docker is not available, use the packaging script:

```bash
# Build the tools package from a completed Yocto build
./scripts/package-delta-tools.sh --build-dir ~/adu_yocto/out/build

# Output:
#   artifacts/adu-delta-gen-tools-x86_64-<version>.tar.gz
#   artifacts/adu-delta-apply-tools-x86_64-<version>.tar.gz
```

**Package layout:**
```
adu-delta-gen-tools-x86_64/
├── bin/
│   ├── diffgentool              # Wrapper script (sets LD_LIBRARY_PATH)
│   ├── diffgentool.bin          # .NET self-contained binary
│   ├── applydiff
│   ├── bsdiff
│   ├── bspatch
│   ├── dumpextfs
│   ├── recompress
│   ├── makecpio
│   ├── extract
│   ├── zstd_compress_file
│   └── dumpdiff
├── lib/
│   ├── libadudiffapi.so
│   ├── libz.so.1 → libz.so.1.3.1
│   ├── libzstd.so.1 → libzstd.so.1.5.5
│   ├── libbz2.so.1 → libbz2.so.1.0.8
│   ├── libjsoncpp.so.25 → libjsoncpp.so.1.9.5
│   ├── libgcrypt.so.20 → libgcrypt.so.20.4.3
│   ├── libfmt.so.10 → libfmt.so.10.2.1
│   ├── libconfig.so.11 → libconfig.so.11.1.0
│   ├── libcrypto.so.3
│   └── libssl.so.3
├── SBOM.json                    # Software Bill of Materials
├── VERSION                      # Version and build metadata
└── README.md                    # Usage instructions
```

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| Ubuntu 22.04+ (x86_64) | Supported | Primary development platform |
| Ubuntu 24.04+ (x86_64) | Supported | Tested |
| Debian 12+ (x86_64) | Best effort | Should work, limited testing |
| RHEL 9+ (x86_64) | Best effort | glibc ≥ 2.34 required |

> **Note:** The bundled binaries are built with Yocto Scarthgap toolchain (glibc 2.39). Hosts with older glibc versions may experience compatibility issues. Use the Docker distribution for maximum portability.

### Security Considerations

- **Crypto libraries**: The package bundles OpenSSL and libgcrypt. These are **not FIPS-validated**. Organizations requiring FIPS compliance should build from source with their certified crypto stack.
- **Update policy**: When security updates are released for bundled libraries (especially OpenSSL), rebuild and redistribute the package.
- **Signing**: Consider signing the tarball/container image for supply chain integrity.

## Usage Examples

### Generate a Delta Diff

```bash
# Unpack the tools
tar xzf adu-delta-gen-tools-x86_64-3.0.tar.gz
export PATH="$PWD/adu-delta-gen-tools-x86_64/bin:$PATH"

# Generate delta from v1 to v2
diffgentool \
    adu-update-image-v1.swu \
    adu-update-image-v2.swu \
    delta-v1-to-v2.diff \
    ./work-dir
```

### Reconstitute Target from Source + Delta

```bash
applydiff \
    adu-update-image-v1.swu \
    delta-v1-to-v2.diff \
    adu-update-image-v2-reconstructed.swu
```

### Verify Reconstitution

```bash
sha256sum adu-update-image-v2.swu adu-update-image-v2-reconstructed.swu
# Hashes should match
```

## Building from Source

The delta tools are built as part of the Yocto image build. The relevant recipes are:

| Recipe | Layer | Purpose |
|--------|-------|---------|
| `iot-hub-device-update-delta-diffgentool-native` | meta-iot-hub-device-update-delta | DiffGenTool (.NET + native) |
| `iot-hub-device-update-delta-processor-native` | meta-iot-hub-device-update-delta | Native tools + libadudiffapi.so |
| `bsdiff` | meta-iot-hub-device-update-delta | bsdiff/bspatch binaries |
| `adu-delta-image` | meta-azure-device-update-samples | Delta generation orchestration |

Source repository: [Azure/iot-hub-device-update-delta](https://github.com/Azure/iot-hub-device-update-delta)

## Related Documentation

- [Delta Update Samples README](yocto/meta-azure-device-update-samples/README.md) — Yocto integration and build flow
- [Delta Layer README](yocto/meta-iot-hub-device-update-delta/README.md) — Meta-layer documentation
- [ADU Agent Source](https://github.com/Azure/iot-hub-device-update/tree/feature/vnext-delta) — Device Update agent with delta support
