# :rocket: arch-bunny

## Huge thanks to viacoffee, whose [dotfiles repo](https://github.com/viacoffee/dotfiles) is borrowed extensively here.

## Installation

This is an Arch Linux setup. Start with [archinstall](https://wiki.archlinux.org/title/Archinstall), then run the bootstrap command below after the first reboot. The command installs curl, and the bootstrap script installs Git when needed, clones this repository, and starts `install.sh` after confirmation.

### Initial setup (archinstall)

1. **Mirror select** — choose `us`
2. **Disk** → Partitioning → `best_effort (or whatever your partition scheme should be)`
3. **Encryption** → LUKS → set a password → select your drive/partition
4. **Bootloader** → `limine`
5. **UKI** → confirm (ok)
6. **NetworkManager** → iwd Backend
7. **Additional packages** → add `pipewire` and `git`
8. **Timezone** → select your region

After archinstall finishes and the system reboots, log in and continue below.

### Filesystem layout

archinstall's `best_effort` btrfs layout is what this repo installs onto: LUKS on the root
partition, `@` mounted at `/`, and its default subvolumes. Nothing in the installer requires
more than a btrfs root.

The installer does add two subvolumes of its own:

| Subvolume | Mountpoint | Created by |
|---|---|---|
| `@dockervol` | `/var/lib/docker` | `install/60-docker.sh` |
| `@containerd` | `/var/lib/containerd` | `install/60-docker.sh` |

Both are top-level and mounted from `/etc/fstab`, which keeps container images, volumes and
overlay mounts out of every root snapshot. That phase refuses to run if either path already
holds data outside its subvolume, rather than mounting over it and hiding those bytes.

Pick the plain `linux` kernel in archinstall. `install/packages` ships no kernel, so that
choice is permanent, and `linux-hardened` adds a variable that is not worth debugging
alongside LUKS.

### Post-reboot

Run the bootstrap script:

```bash
sudo pacman -S --needed curl && bash <(curl -fsSL https://raw.githubusercontent.com/charlesfry/arch-bunny/master/bootstrap.sh)
```

The script clones the repository to `~/arch-bunny`, shows a warning before making system changes, and then runs the installer.

To install a specific branch:

```bash
sudo pacman -S --needed curl && bash <(curl -fsSL https://raw.githubusercontent.com/charlesfry/arch-bunny/master/bootstrap.sh) -b <branch>
```

### Factory reset

The last install phase takes a Snapper snapshot of the finished system, described
`arch-bunny factory state`. It carries no cleanup algorithm, so Snapper never prunes it,
and limine-snapper-sync lists it in the boot menu.

To return the system to that state, find its number and roll back:

```bash
sudo snapper -c root list | grep 'factory state'
sudo snapper -c root rollback <number>
sudo systemctl reboot
```

This rolls back `/` only. `/home` has its own Snapper config and is left alone, so a reset
keeps your files.

## Keyboard Shortcuts

`Mod` is the Super/Windows key. `Mod+I` shows niri's own hotkey overlay on the machine
itself; this table mirrors [`config/niri/bindings.kdl`](config/niri/bindings.kdl).

### Applications

| Shortcut | Action |
|---|---|
| `Mod+Return` | Terminal (kitty) |
| `Mod+Space` | Launcher (fuzzel) |
| `Mod+Shift+N` | Neovim in a kitty window |
| `Mod+Shift+B` | Brave |
| `Mod+Shift+Ctrl+B` | Brave, incognito window |
| `Mod+Shift+M` | Spotify |
| `Mod+Shift+T` | btop in a kitty window |
| `Mod+Shift+D` | lazydocker in a kitty window |
| `Mod+Shift+G` | Signal |
| `Mod+Shift+Slash` | Bitwarden |
| `Mod+Shift+F` | Nautilus, new window |
| `Mod+Shift+Space` | Hivemind prompt |
| `Mod+Ctrl+V` | Clipboard history (cliphist through fuzzel) |
| `Mod+Comma` | Dismiss the top notification |
| `Mod+Shift+Comma` | Dismiss all notifications |
| `Mod+Escape` | Lock the screen |
| `Mod+I` | Show the hotkey overlay |

### Focus

| Shortcut | Action |
|---|---|
| `Mod+H` / `Mod+L` | Focus column left/right, crossing to the next monitor at the edge |
| `Mod+Left` / `Mod+Right` | Focus column left/right |
| `Mod+Up` / `Mod+Down` | Focus window up/down within the column |
| `Mod+K` / `Mod+J` | Focus window up/down, crossing to the next workspace at the edge |
| `Alt+Tab` | Previously focused window |
| `Mod+Home` / `Mod+End` | First/last column |
| `Mod+Shift+H/J/K/L` | Focus monitor left/down/up/right |
| `Mod+Shift+Left/Down/Up/Right` | Focus monitor left/down/up/right |
| `Mod+Page_Up` / `Mod+Page_Down` | Focus workspace up/down |
| `Mod+1`–`Mod+9` | Focus workspace 1–9 |
| `Mod+O` | Toggle the overview |
| `Mod+WheelScrollUp/Down` | Focus workspace up/down |
| `Mod+WheelScrollLeft/Right` | Focus column left/right |
| `Mod+Shift+WheelScrollUp/Down` | Focus column left/right |

### Moving windows

| Shortcut | Action |
|---|---|
| `Mod+Ctrl+H` / `Mod+Ctrl+L` | Move column left/right, or to the next monitor |
| `Mod+Ctrl+Left/Right` | Move column left/right |
| `Mod+Ctrl+Up/Down` | Move window up/down within the column |
| `Mod+Ctrl+K` / `Mod+Ctrl+J` | Move window up/down, or to the next workspace |
| `Mod+Ctrl+Home` / `Mod+Ctrl+End` | Move column to first/last |
| `Mod+Ctrl+I` / `Mod+Ctrl+U` | Move column to the workspace above/below |
| `Mod+Ctrl+Page_Up/Page_Down` | Move column to the workspace above/below |
| `Mod+Shift+1`–`Mod+Shift+9` | Move column to workspace 1–9 |
| `Mod+Shift+I` / `Mod+Shift+U` | Move the whole workspace up/down |
| `Mod+Shift+Page_Up/Page_Down` | Move the whole workspace up/down |
| `Mod+Shift+Ctrl+H/J/K/L` | Move column to the monitor left/down/up/right |
| `Mod+Shift+Ctrl+Left/Right` | Move the whole workspace to the monitor left/right |
| `Mod+Shift+Ctrl+Up/Down` | Move column to the monitor above/below |
| `Mod+BracketLeft` / `Mod+BracketRight` | Consume or expel window left/right |
| `Mod+Ctrl+WheelScrollUp/Down` | Move column to the workspace above/below |
| `Mod+Ctrl+WheelScrollLeft/Right` | Move column left/right |
| `Mod+Ctrl+Shift+WheelScrollUp/Down` | Move column left/right |

### Size and layout

| Shortcut | Action |
|---|---|
| `Mod+W` | Close window |
| `Mod+F` | Maximize column |
| `Shift+F11` | Fullscreen window |
| `Mod+M` | Maximize window to the screen edges |
| `Mod+Ctrl+F` | Expand column into the free space |
| `Mod+C` | Center the column |
| `Mod+Ctrl+C` | Center all visible columns |
| `Mod+R` / `Mod+Shift+R` | Cycle preset column widths forward/back |
| `Mod+Ctrl+Shift+R` | Cycle preset window heights |
| `Mod+Ctrl+R` | Reset window height |
| `Mod+Minus` / `Mod+Equal` | Column width −10% / +10% |
| `Mod+Shift+Minus` / `Mod+Shift+Equal` | Window height −10% / +10% |
| `Mod+V` | Toggle window floating |
| `Mod+Shift+V` | Switch focus between floating and tiling |
| `Mod+Shift+W` | Toggle tabbed column display |

### Screenshots

| Shortcut | Action |
|---|---|
| `Print` | Screenshot, interactive selection |
| `Ctrl+Print` | Screenshot the whole screen |
| `Alt+Print` | Screenshot the focused window |
| `Mod+Print` | Screenshot a region and annotate it in satty |
| `Mod+Shift+Print` | Pick a colour off the screen, hex to the clipboard |

### Audio

| Shortcut | Action |
|---|---|
| `XF86AudioRaiseVolume` | Volume up (capped at 100%) |
| `XF86AudioLowerVolume` | Volume down |
| `XF86AudioMute` | Mute/unmute output |
| `XF86AudioMicMute` | Mute/unmute microphone |
| `XF86AudioPlay` | Play/pause |
| `XF86AudioStop` | Stop |
| `XF86AudioPrev` / `XF86AudioNext` | Previous/next track |

All of these keep working while the session is locked.

### Brightness

| Shortcut | Action |
|---|---|
| `XF86MonBrightnessUp` | Brightness +10% |
| `XF86MonBrightnessDown` | Brightness −10% |

### Session

| Shortcut | Action |
|---|---|
| `Mod+Shift+P` | Power off the monitors (any input wakes them) |
| `Mod+Shift+Escape` | Toggle keyboard-shortcut inhibiting — the one bind that always works |
| `Mod+Shift+E` | Quit niri, with a confirmation dialog |
| `Ctrl+Alt+Delete` | Quit niri, with a confirmation dialog |

### Waybar

Some actions have no keybinding and live in the bar instead: click the idle
indicator for `bunny-toggle-idle`, the notification indicator for
`bunny-toggle-dnd`, the recording indicator for `bunny-cmd-screenrecord`
(gpu-screen-recorder, toggles), and the power button for `bunny-menu power`.

## Commands

Scripts with no keyboard shortcut or menu entry — invoke these manually from a terminal.

| Command | Description |
|---|---|
| `bunny-theme-background` | Set desktop wallpaper from a file path or URL |
| `bunny-dev` | Install, inspect, or remove optional development environments |
| `bunny-update` | Update system packages and optionally reboot |
| `bunny-migrate` | Restow arch-bunny and remove orphaned symlinks |

## Aliases

| Alias | Expands to |
|---|---|
| `top`, `htop` | `btop` |
| `vim` | `nvim` |
| `l` | `lsd -a1` |
| `la` | `lsd -la` |
| `lr` | `lsd -R` |
| `lra` | `lsd -RA` |
| `lt` | `lsd --tree` |
| `gs` | `git status` |
| `gl` | `git log --oneline --graph --decorate` |
| `gp` | `git push` |
| `gd` | `git diff` |
| `gc` | `git commit` |
| `c` | `clear` |
| `...` | `cd ../..` |
| `....` | `cd ../../..` |

## Stack

| Category | Tools |
|---|---|
| **Compositor** | [niri](https://github.com/YaLTeR/niri) — scrollable-tiling Wayland compositor |
| **Session manager** | [uwsm](https://github.com/Vladimir-csp/uwsm) — Universal Wayland Session Manager |
| **Login manager** | [greetd](https://sr.ht/~kennylevinsen/greetd/) |
| **Terminal** | [kitty](https://sw.kovidgoyal.net/kitty/) |
| **Bar** | [Waybar](https://github.com/Alexays/Waybar) |
| **Launcher** | [bemenu](https://github.com/Cloudef/bemenu) |
| **Notifications** | [mako](https://github.com/emersion/mako) |
| **Lock screen** | [hyprlock](https://github.com/hyprwm/hyprlock) |
| **Wallpaper** | [swaybg](https://github.com/swaywm/swaybg) |
| **Idle management** | [swayidle](https://github.com/swaywm/swayidle) |
| **OSD overlays** | [swayosd](https://github.com/ErikReider/SwayOSD) |
| **Boot splash** | [plymouth](https://gitlab.freedesktop.org/plymouth/plymouth) |
| **Clipboard** | wl-clipboard |
| **Screenshots** | [grim](https://sr.ht/~emersion/grim/) + [slurp](https://github.com/emersion/slurp) |
| **Screen recording** | [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder/) |
| **File manager** | [Nautilus](https://apps.gnome.org/Nautilus/) |
| **Media** | [mpv](https://mpv.io/) · [imv](https://sr.ht/~exec64/imv/) · [playerctl](https://github.com/altdesktop/playerctl) |
| **Audio mixer** | [wiremix](https://github.com/nicholasgasior/wiremix) |
| **Bluetooth** | [bluetui](https://github.com/pythops/bluetui) |
| **Wi-Fi** | [impala](https://github.com/pythops/impala) + [iwd](https://iwd.wiki.kernel.org/) |
| **System monitor** | [btop](https://github.com/aristocratos/btop) |
| **File listing** | [lsd](https://github.com/lsd-rs/lsd) |
| **Snapshots** | [snapper](https://github.com/openSUSE/snapper) + limine-snapper-sync, on the subvolume layout above |
| **Containers** | [Docker](https://www.docker.com/) + docker-compose, on their own snapshot-excluded subvolumes, with [ufw-docker](https://github.com/chaifeng/ufw-docker) closing Docker's iptables bypass |
| **Browser** | [Brave](https://brave.com/) (`brave-bin`, built from the AUR by `install/14-aur.sh`) · Firefox |
| **Bootloader** | [limine](https://limine-bootloader.org/) |
| **Disk encryption** | LUKS via cryptsetup |
| **Firewall** | [ufw](https://wiki.archlinux.org/title/Uncomplicated_Firewall) |
| **AUR helper** | [yay](https://github.com/Jguer/yay) |
| **Dotfiles management** | [GNU stow](https://www.gnu.org/software/stow/) |
