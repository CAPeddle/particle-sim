# CUDA 13.2 Installation - Progress Guide

## Current Status

**Download in Progress:**
- File: `cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb` (3.3 GB)
- Location: `/home/cpeddle/projects/personal/particle-sim/`
- Log file: `download.log`
- Estimated time: ~20-30 minutes

## Monitor Download Progress

Check progress in real-time:

```bash
cd ~/projects/personal/particle-sim
tail -f download.log
```

Quick status check:

```bash
ls -lh cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb
```

Expected final size: **3.3 GB (3,491,516,434 bytes)**

## When Download Completes

### Option 1: Run the Automated Script (Recommended)

```bash
cd ~/projects/personal/particle-sim
chmod +x scripts/install-cuda-13.2.sh
./scripts/install-cuda-13.2.sh
```

The script will:
1. ✓ Verify the DEB file is complete
2. ✓ Install the repository package
3. ✓ Set up NVIDIA GPG keyring
4. ✓ Update package manager
5. ✓ Install CUDA Toolkit 13.2
6. ✓ Verify installation

### Option 2: Manual Installation Steps

```bash
cd ~/projects/personal/particle-sim

# 1. Install DEB repository
sudo dpkg -i cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb

# 2. Set up GPG keyring
sudo cp /var/cuda-repo-wsl-ubuntu-13-2-local/cuda-*-keyring.gpg /usr/share/keyrings/

# 3. Update and install
sudo apt-get update
sudo apt-get -y install cuda-toolkit-13-2

# 4. Verify
nvcc --version
```

## Troubleshooting

### Download Corrupted or Incomplete

If you see an error like "unexpected end of file", the download may have been interrupted.

**Fix:**
```bash
cd ~/projects/personal/particle-sim
rm -f cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb
wget https://developer.download.nvidia.com/compute/cuda/13.2.0/local_installers/cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb
```

### DEB Installation Fails

Make sure the file is complete:

```bash
ls -lh cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb
stat -c%s cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb
# Should show: 3491516434 bytes
```

### CUDA Not in PATH After Installation

Add to `~/.bashrc`:

```bash
cat >> ~/.bashrc << 'EOF'
# CUDA 13.2
export PATH=/usr/local/cuda-13.2/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-13.2/lib64:$LD_LIBRARY_PATH
EOF

source ~/.bashrc
```

Verify:
```bash
nvcc --version
```

## Next Steps After Installation

Once CUDA 13.2 is installed:

```bash
cd ~/projects/personal/particle-sim/build

# If build directory exists, reconfigure
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release ..

# Build
cmake --build .

# Run tests
ctest --output-on-failure

# Run the application
./particle_sim
```

## Reference

- Full setup guide: [DEVELOPMENT.md](../DEVELOPMENT.md)
- Installation script: [scripts/install-cuda-13.2.sh](../scripts/install-cuda-13.2.sh)
- NVIDIA CUDA WSL docs: https://docs.nvidia.com/cuda/wsl-user-guide/
- CUDA Toolkit Archive: https://developer.nvidia.com/cuda-toolkit-archive

---

**Questions?** Check [DEVELOPMENT.md](../DEVELOPMENT.md) for comprehensive troubleshooting.
