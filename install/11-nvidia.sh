#!/bin/bash

step "Detecting NVIDIA hardware"

# Detect NVIDIA GPU with error handling
NVIDIA="$(lspci | grep -i 'nvidia' || true)"

if [[ -z "$NVIDIA" ]]; then
  section_note "No NVIDIA GPU detected; skipped"
  return 0
fi

log "NVIDIA GPU detected: $NVIDIA"

# Detect kernel type and set appropriate headers package
KERNEL_HEADERS=""
if pacman -Qqs '^linux-zen$' &>/dev/null; then
  KERNEL_HEADERS="linux-zen-headers"
elif pacman -Qqs '^linux-lts$' &>/dev/null; then
  KERNEL_HEADERS="linux-lts-headers"
elif pacman -Qqs '^linux-hardened$' &>/dev/null; then
  KERNEL_HEADERS="linux-hardened-headers"
elif pacman -Qqs '^linux$' &>/dev/null; then
  KERNEL_HEADERS="linux-headers"
else
  error "No supported kernel detected"
  return 1
fi

log "Detected kernel headers package: $KERNEL_HEADERS"

# Determine driver packages based on GPU model
PACKAGES=()

if echo "$NVIDIA" | grep -qE "RTX [2-9][0-9]|GTX 16"; then
  # Turing (16xx, 20xx), Ampere (30xx), Ada (40xx), and newer recommend the open-source kernel modules
  step "Selecting open NVIDIA drivers"
  PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
elif echo "$NVIDIA" | grep -qE "GTX 9|GTX 10|Quadro P|MX1|MX2|MX3"; then
  # Pascal (10xx, Quadro Pxxx, MX150, MX2xx, MX3xx) and Maxwell (9xx, MX110, MX130) use legacy drivers
  step "Selecting legacy NVIDIA drivers"
  PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
else
  warn "NVIDIA GPU detected but no compatible driver found."
  warn "For more information, see: https://wiki.archlinux.org/title/NVIDIA"
  return 0
fi

log "Packages to be installed: ${PACKAGES[*]}"

# Install packages without generating boot artifacts before the final
# mkinitcpio, Plymouth, and Limine configuration has been written.
step "Installing NVIDIA drivers and dependencies"
INSTALL_PACKAGES=("$KERNEL_HEADERS" "${PACKAGES[@]}")
install_packages_without_generation "${INSTALL_PACKAGES[@]}"
success "Package installation completed successfully"

# Configure modprobe for early KMS
step "Configuring NVIDIA early KMS"
if ! sudo mkdir -p /etc/modprobe.d; then
  error "Failed to create modprobe.d directory"
  return 1
fi

if ! sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
options nvidia_drm modeset=1
EOF
then
  error "Failed to write modprobe configuration"
  return 1
fi

# Configure mkinitcpio for early module loading
step "Configuring NVIDIA initramfs modules"
if ! sudo mkdir -p /etc/mkinitcpio.conf.d; then
  error "Failed to create mkinitcpio.conf.d directory"
  return 1
fi

if ! sudo tee /etc/mkinitcpio.conf.d/nvidia.conf >/dev/null <<'EOF'
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
then
  error "Failed to write mkinitcpio configuration"
  return 1
fi

# Set NVIDIA environment variables for Wayland/Niri
step "Configuring NVIDIA environment variables"
if ! mkdir -p ~/.config/environment.d; then
  error "Failed to create environment.d directory"
  return 1
fi

if ! cat > ~/.config/environment.d/nvidia.conf <<'EOF'
# NVIDIA drivers for Wayland/Niri
NVD_BACKEND=direct
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
then
  error "Failed to write environment configuration"
  return 1
fi

log "NVIDIA drivers configured successfully"
log "A system reboot is required to load the NVIDIA changes"
