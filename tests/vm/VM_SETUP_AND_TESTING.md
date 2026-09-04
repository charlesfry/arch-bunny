# Building the baseline VM

`tests/vm/README.md` describes the harness once a baseline exists. This is how to build the
powered-off `arch-bunny-arch-base` domain that `tests/vm/run prepare` clones.

## Host prerequisites

```bash
sudo pacman -S --needed libvirt qemu-desktop virt-install virt-manager dnsmasq
sudo systemctl enable --now libvirtd.socket
sudo virsh net-start default && sudo virsh net-autostart default
```

`virt-clone` comes from `virt-install`; `virt-manager` is what `tests/vm/run view` opens to
unlock LUKS. None of this belongs in `install/packages` — it is host-side test tooling, and it
is expected to be uninstalled when the rehearsal is done, along with the daemons and the
`default` network it leaves enabled at boot.

## Baseline domain

```bash
virt-install --connect qemu:///system --name arch-bunny-arch-base \
  --memory 4096 --vcpus 2 \
  --disk path=/var/lib/libvirt/images/arch-bunny-arch-base.qcow2,size=60,format=qcow2 \
  --cdrom ~/Downloads/archlinux-x86_64.iso \
  --os-variant archlinux --graphics spice
```

There is no libvirt storage pool defined by default, hence the explicit `--disk path=`. 60 GiB
leaves room for container images plus snapshots.

## Install Arch in it

Follow the archinstall steps in the repo's [README](../../README.md#initial-setup-archinstall)
exactly as a real machine would: `best_effort` partitioning, LUKS, limine, UKI, `pipewire`.
Two additions for a test VM:

- **Kernel: plain `linux`.** `install/packages` ships no kernel, so the choice is permanent.
- **Additional packages: `git curl openssh`**, and create the user **`arch-bunny-user`** in the
  `wheel` group — that name is what `tests/vm/config.example:11` expects, and `wheel` needs
  sudo because every install phase uses it.

Do not add `limine-mkinitcpio-hook` or `limine-snapper-sync` here: they live in the `omarchy`
repository, which the ISO does not have. `install/10-packages.sh` configures that repo and
installs them.

Secure Boot must stay off and the guest must be x86_64 — both are preflight checks.

## Freeze it

Reboot once, confirm it boots and unlocks, then shut down and leave the domain powered off.
`tests/vm/run` refuses to clone a running baseline (`require_powered_off_base`).

If the first boot lands in an emergency shell with `device '/dev/mapper/root' not found`, the
initramfs was not told to unlock LUKS. Boot the ISO, `cryptsetup open`, mount the root
subvolume, `arch-chroot`, then make sure the kernel cmdline carries
`cryptdevice=UUID=<luks-uuid>:root root=/dev/mapper/root rootflags=subvol=@` and that `encrypt`
sits between `block` and `filesystems` in `/etc/mkinitcpio.conf`. `mkinitcpio -P` afterwards —
with a UKI the cmdline is baked into the `.efi`, so editing `limine.conf` alone changes nothing.
Use `cryptdevice=`, not `rd.luks.name=`: `install/13-bootloader.sh:23` pins the busybox hook
set, and `encrypt` ignores the systemd-style parameters.

## Then

Follow `tests/vm/README.md`: `prepare automation-base` → `keygen` → `ssh-setup` → `stop`, then
point `VM_BASE_NAME` at `arch-bunny-test-automation-base` in `tests/vm/config.local` so every
test clone inherits OpenSSH, the test key, and the `/etc/bunny-test-vm` marker that
`install/50-firewall.sh` looks for.
