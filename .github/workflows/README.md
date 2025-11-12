# GitHub Workflows for Yocto Builds

This directory contains GitHub Actions workflows for automated Yocto builds.

## Available Workflows

### 1. `yocto-build.yml` - Standard Build
**Best for:** Release builds, manual testing

- Runs on GitHub-hosted Ubuntu 22.04 runners
- Full build with caching
- Triggers: Push to main/scarthgap, PRs, manual dispatch
- Timeout: 6 hours
- Artifacts retained: 7 days (images), 30 days (SBOM)

**Resource Requirements:**
- 2 CPU cores (GitHub free runners)
- 7GB RAM
- ~100GB disk space

**Features:**
- Downloads and sstate caching
- Parallel builds using all available cores
- SBOM artifact upload
- Build summary in workflow output

### 2. `yocto-build-incremental.yml` - Fast Incremental Build
**Best for:** PR validation, quick iteration

- Optimized for incremental builds (no clean)
- Aggressive caching strategy
- Triggers: Pull requests, manual dispatch
- Timeout: 4 hours
- Artifacts retained: 3 days

**Optimizations:**
- No clean flag (faster builds)
- Change detection
- Separate cache save/restore steps
- Minimal artifact retention

### 3. `yocto-build-self-hosted.yml` - Self-Hosted Runner
**Best for:** Production builds, nightly builds

- Designed for self-hosted runners with better resources
- Supports scheduled nightly builds
- Advanced build options (clean builds, custom commits)
- Long-term artifact archival

**Recommended Runner Specs:**
- 8+ CPU cores
- 16GB+ RAM
- 200GB+ disk space
- Ubuntu 22.04

**Features:**
- Build archival to persistent storage
- Automatic cleanup of old builds
- Configurable build options via workflow_dispatch
- Build reports and notifications

## Usage

### Triggering Workflows

#### Automatic Triggers
```bash
# Push to main or scarthgap branches
git push origin main

# Create a pull request (triggers incremental build)
gh pr create
```

#### Manual Triggers
```bash
# Trigger standard build
gh workflow run yocto-build.yml

# Trigger with custom ADU branch
gh workflow run yocto-build.yml \
  -f adu_branch=feature/v-next \
  -f build_type=Release

# Trigger self-hosted clean build
gh workflow run yocto-build-self-hosted.yml \
  -f clean_build=true \
  -f adu_branch=main \
  -f build_type=Release
```

### Downloading Artifacts

```bash
# List artifacts
gh run list --workflow=yocto-build.yml

# Download latest artifacts
gh run download --name yocto-images-<sha>

# Download SBOM
gh run download --name sbom-<sha>
```

## Setup Instructions

### For GitHub-Hosted Runners

No setup required! Just commit the workflow files and they'll run automatically.

**Considerations:**
- Builds may timeout on free GitHub runners (6-hour limit)
- Consider GitHub Enterprise for larger runners
- First build will be slow (~4-6 hours), subsequent builds faster with cache

### For Self-Hosted Runners

1. **Setup Runner Machine:**
   ```bash
   # Minimum specs: 8 cores, 16GB RAM, 200GB disk
   # Ubuntu 22.04 recommended
   
   # Create build directories
   sudo mkdir -p /data/yocto_builds
   sudo mkdir -p /data/archives
   sudo chown -R runner:runner /data
   ```

2. **Register Runner:**
   ```bash
   # Go to: Settings > Actions > Runners > New self-hosted runner
   # Follow the registration instructions
   
   # Add labels: self-hosted, linux, x64, yocto-builder
   ```

3. **Configure Runner:**
   ```bash
   # Install as service
   sudo ./svc.sh install
   sudo ./svc.sh start
   
   # Verify
   sudo ./svc.sh status
   ```

4. **Pre-install Dependencies:**
   ```bash
   # Clone repo
   git clone https://github.com/azure/iot-hub-device-update-yocto
   cd iot-hub-device-update-yocto
   
   # Install dependencies
   ./scripts/install-deps.sh
   ```

### Caching Strategy

The workflows use GitHub Actions cache to speed up builds:

1. **Downloads Cache** (`~20GB`)
   - Source tarballs, git repos
   - Rarely changes
   - Key: `yocto-downloads-scarthgap-<hash>`

2. **SState Cache** (`~40-60GB`)
   - Compiled artifacts
   - Changes frequently
   - Key: `yocto-sstate-scarthgap-<branch>-<sha>`

**Cache Limits:**
- GitHub free: 10GB per repository
- GitHub Pro/Enterprise: 10GB per repository
- Self-hosted: No limit (local disk)

**Optimization Tips:**
- Use self-hosted runners for better caching
- Consider external cache storage (S3, Azure Blob)
- Clean old cache entries regularly

## Troubleshooting

### Build Timeouts
```yaml
# Increase timeout in workflow file
timeout-minutes: 480  # 8 hours
```

### Disk Space Issues
```yaml
# Add disk cleanup step
- name: Free disk space
  run: |
    sudo rm -rf /usr/share/dotnet
    sudo rm -rf /opt/ghc
    df -h
```

### Cache Misses
```yaml
# Use more generic restore-keys
restore-keys: |
  yocto-sstate-scarthgap-
  yocto-sstate-
```

### Memory Issues
```yaml
# Reduce parallel tasks
-j 4 --parallel-make 4  # Instead of $(nproc)
```

## Advanced Configuration

### Using External Cache Storage

For better caching, consider using external storage:

```yaml
- name: Restore sstate from S3
  run: |
    aws s3 sync s3://my-bucket/yocto-cache/sstate \
      $BUILD_DIR/build/sstate-cache \
      --quiet

- name: Save sstate to S3
  run: |
    aws s3 sync $BUILD_DIR/build/sstate-cache \
      s3://my-bucket/yocto-cache/sstate \
      --quiet --exclude "*"  --include "sstate-*"
```

### Matrix Builds

Build for multiple targets:

```yaml
strategy:
  matrix:
    target: [raspberrypi3, raspberrypi4-64]
    build_type: [Debug, Release]
```

### Notifications

Add Slack/Teams notifications:

```yaml
- name: Notify Slack
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Yocto build failed: ${{ github.sha }}"
      }
```

## Cost Considerations

### GitHub-Hosted Runners
- Free tier: 2,000 minutes/month
- Typical full build: 4-6 hours = 240-360 minutes
- ~5-8 builds per month on free tier

### Self-Hosted Runners
- No GitHub minutes usage
- Infrastructure cost (compute, storage)
- Maintenance overhead

### Recommendations
1. Use self-hosted for regular/nightly builds
2. Use GitHub-hosted for PR validation (incremental builds)
3. Implement aggressive caching
4. Consider build-on-demand vs scheduled builds

## Security Considerations

1. **Secrets Management:**
   - Store signing keys in GitHub Secrets
   - Use environment-specific secrets
   - Rotate keys regularly

2. **Artifact Security:**
   - Enable artifact attestation
   - Sign release images
   - Generate checksums

3. **Runner Security:**
   - Keep self-hosted runners updated
   - Isolate build environment
   - Use ephemeral runners for untrusted PRs

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Yocto Build System](https://docs.yoctoproject.org/)
- [Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Actions Cache](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
