#!/bin/bash
# CUDA 13.2 WSL Installation Script
# This script automates the NVIDIA CUDA 13.2 installation process for WSL 2 Ubuntu.
#
# Adapted from: https://developer.nvidia.com/cuda-toolkit-archive
# Target: CUDA 13.2 on WSL 2 with Ubuntu 22.04+
#
# Usage:
#   chmod +x install-cuda-13.2.sh
#   ./install-cuda-13.2.sh
#

set -e  # Exit on any error

echo "=========================================="
echo "CUDA 13.2 WSL Installation Script"
echo "=========================================="
echo ""

# Check if running on WSL
if ! grep -qi microsoft /proc/version; then
    echo "WARNING: This script is optimized for WSL 2. You appear to be on native Linux."
    echo "Installation may differ. Proceeding anyway..."
    echo ""
fi

# Step 1: Download and install the repository pin
echo "[1/6] Downloading NVIDIA repository pin..."
if [ -f "cuda-wsl-ubuntu.pin" ]; then
    echo "      ✓ Pin file already downloaded"
else
    wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin
fi

echo "      Moving to /etc/apt/preferences.d/..."
sudo mv cuda-wsl-ubuntu.pin /etc/apt/preferences.d/cuda-repository-pin-600
echo "      ✓ Done"
echo ""

# Step 2: Download CUDA 13.2 DEB (3.3 GB)
echo "[2/6] Downloading CUDA 13.2 repository package (3.3 GB)..."
DEB_FILE="cuda-repo-wsl-ubuntu-13-2-local_13.2.0-1_amd64.deb"
EXPECTED_SIZE=3491516434  # 3.3 GB in bytes

# Check if file exists and verify size
if [ -f "$DEB_FILE" ]; then
    ACTUAL_SIZE=$(stat -c%s "$DEB_FILE" 2>/dev/null || echo "0")
    if [ "$ACTUAL_SIZE" -ge "$EXPECTED_SIZE" ]; then
        SIZE_MB=$((ACTUAL_SIZE / 1024 / 1024))
        echo "      ✓ DEB file already downloaded ($SIZE_MB MB)"
    else
        echo "      ⚠ DEB file exists but incomplete: $ACTUAL_SIZE / $EXPECTED_SIZE bytes"
        echo "      Removing corrupted file and re-downloading..."
        rm -f "$DEB_FILE"
        echo "      Starting download (this may take 15-30 minutes)..."
        wget -c https://developer.download.nvidia.com/compute/cuda/13.2.0/local_installers/$DEB_FILE || {
            echo "      ✗ Download failed. Try manually:"
            echo "      wget https://developer.download.nvidia.com/compute/cuda/13.2.0/local_installers/$DEB_FILE"
            exit 1
        }
    fi
else
    echo "      Starting download (this may take 15-30 minutes)..."
    wget -c https://developer.download.nvidia.com/compute/cuda/13.2.0/local_installers/$DEB_FILE || {
        echo "      ✗ Download failed. Try manually:"
        echo "      wget https://developer.download.nvidia.com/compute/cuda/13.2.0/local_installers/$DEB_FILE"
        exit 1
    }
fi
echo ""

# Step 3: Install the DEB package
echo "[3/6] Installing CUDA repository DEB package..."
if ! sudo dpkg -i "$DEB_FILE" 2>&1; then
    echo "      ✗ DEB installation failed"
    echo ""
    echo "      This may indicate the DEB file is corrupted or incomplete."
    echo "      Try these troubleshooting steps:"
    echo ""
    echo "      1. Verify file size (should be ~3.3 GB):"
    echo "         ls -lh $DEB_FILE"
    echo ""
    echo "      2. Re-download if incomplete:"
    echo "         rm -f $DEB_FILE"
    echo "         wget https://developer.download.nvidia.com/compute/cuda/13.2.0/local_installers/$DEB_FILE"
    echo ""
    echo "      3. Try installation again:"
    echo "         sudo dpkg -i $DEB_FILE"
    echo ""
    exit 1
fi
echo "      ✓ Done"
echo ""

# Step 4: Copy JPEG keyring
echo "[4/6] Setting up package authentication..."
sudo cp /var/cuda-repo-wsl-ubuntu-13-2-local/cuda-*-keyring.gpg /usr/share/keyrings/
echo "      ✓ Done"
echo ""

# Step 5: Update and install CUDA toolkit
echo "[5/6] Updating package manager and installing CUDA toolkit..."
sudo apt-get update
sudo apt-get -y install cuda-toolkit-13-2
echo "      ✓ Done"
echo ""

# Step 6: Verify installation
echo "[6/6] Verifying CUDA installation..."
if command -v nvcc &> /dev/null; then
    CUDA_VERSION=$(nvcc --version | grep "release" | awk '{print $5}')
    echo "      ✓ CUDA version: $CUDA_VERSION"
    if [[ "$CUDA_VERSION" == "13.2"* ]]; then
        echo "      ✓ Correct version confirmed!"
    else
        echo "      ⚠ Unexpected CUDA version. Expected 13.2.x, got $CUDA_VERSION"
    fi
else
    echo "      ⚠ nvcc not found in PATH yet"
    echo ""
    echo "      This is normal - you may need to reload your shell."
    echo ""
    echo "      Add CUDA to your PATH by adding this to ~/.bashrc:"
    echo ""
    echo "      export PATH=/usr/local/cuda-13.2/bin:\$PATH"
    echo "      export LD_LIBRARY_PATH=/usr/local/cuda-13.2/lib64:\$LD_LIBRARY_PATH"
    echo ""
    echo "      Then reload:"
    echo "      source ~/.bashrc"
    echo ""
    echo "      Verify installation with:"
    echo "      nvcc --version"
fi
echo ""

# Post-installation message
echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. (Optional) Add CUDA to your PATH if not already done:"
echo "   export PATH=/usr/local/cuda-13.2/bin:\$PATH"
echo "   export LD_LIBRARY_PATH=/usr/local/cuda-13.2/lib64:\$LD_LIBRARY_PATH"
echo ""
echo "2. Verify CUDA by running:"
echo "   nvcc --version"
echo ""
echo "3. Build particle-sim:"
echo "   mkdir -p build && cd build"
echo "   cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .."
echo "   cmake --build ."
echo ""
