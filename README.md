# :rabbit: arch-bunny :rabbit:

### Huge thanks to viacoffee, whose [dotfiles repo](https://github.com/viacoffee/dotfiles) is borrowed extensively for the install plumbing.

## Installation

This is an Arch Linux setup. Start with [archinstall](https://wiki.archlinux.org/title/Archinstall), then run the bootstrap command below after the first reboot. The command installs curl, and the bootstrap script installs Git when needed, clones this repository, and starts `install.sh` after confirmation.

### Initial setup (archinstall)

1. **Mirror select** — choose `us`
2. **Disk** → Partitioning → manual btrfs subvolume layout. `best_effort` is close but
   not right — it gives you `@pkg` at `/var/cache/pacman/pkg`, where this setup wants the
   whole of `/var/cache`. Create these five, and `install/00-preflight.sh` will refuse to
   run until they are all mounted:

   | Subvolume | Mountpoint |
   |---|---|
   | `@` | `/` |
   | `@home` | `/home` |
   | `@log` | `/var/log` |
   | `@cache` | `/var/cache` |
   | `@tmp` | `/var/tmp` |

   `@snapshots`, `@dockervol`, and `@containerd` are added later by the installer — it only
   ever adds, never repartitions. See [Filesystem layout](#filesystem-layout) for why each
   one is carved out.
3. **Encryption** → LUKS → set a password → select your drive/partition
4. **Bootloader** → `limine`
5. **UKI** → confirm (ok)
6. **NetworkManager** → iwd Backend — pick this to get a working network for the
   install. `install/30-system-services.sh` later disables NetworkManager and moves the
   system to systemd-networkd (ethernet) plus iwd (Wi-Fi); the archinstall choice only
   has to survive the first boot.
7. **Additional packages** → add `pipewire` and `git`
8. **Timezone** → select your preferred region

After archinstall finishes and the system reboots, log in and continue below.

### Filesystem layout

LUKS on the root partition, `@` mounted at `/`, and the subvolumes you created during
archinstall. Beyond a btrfs root the installer adds only its own three subvolumes; it
never repartitions or relocates one.

Every subvolume is top-level and mounted from `/etc/fstab`. The finished layout:

| Subvolume | Mountpoint | Created by | In root snapshots? |
|---|---|---|---|
| `@` | `/` | you, in archinstall | **yes** — this is what a snapshot *is* |
| `@home` | `/home` | you, in archinstall | no — its own Snapper config, so a root rollback keeps your files |
| `@log` | `/var/log` | you, in archinstall | no — rewinding logs would erase the record of whatever you rolled back from |
| `@cache` | `/var/cache` | you, in archinstall | no — re-downloadable caches, and the largest thing that would otherwise be copied. The whole directory rather than just `pacman/pkg`, so any cache a future daemon invents is excluded without another migration |
| `@tmp` | `/var/tmp` | you, in archinstall | no — per-boot scratch; must be mode `1777`, which a freshly created subvolume is not |
| `@snapshots` | `/.snapshots` | `install/13-bootloader.sh` | no — **must** be outside `@`, or a rollback that swaps `@` takes the snapshots with it |
| `@dockervol` | `/var/lib/docker` | `install/60-docker.sh` | no — image layers and volumes, rebuildable and huge |
| `@containerd` | `/var/lib/containerd` | `install/60-docker.sh` | no — same |

Snapper puts `/.snapshots` inside `@` by default. `13-bootloader.sh` creates `@snapshots`
at the top level and remounts it there, which is the single thing that makes the factory
reset below survivable: the snapshots are not stored inside the subvolume being replaced.

`60-docker.sh` refuses to run if `/var/lib/docker` or `/var/lib/containerd` already holds
data outside its subvolume, rather than mounting over it and hiding those bytes.

Two Snapper configs run independently: `root` covers `/` — packages, `/etc`, everything in
`@` — and `home` covers `/home`, its snapshots nested inside `@home`. Rolling back `root`
rewinds the system and leaves your files alone; restoring from `home` recovers files
without reverting the system.

Neither takes snapshots on a timer — `13-bootloader.sh` sets `TIMELINE_CREATE="no"` and
keeps the last 5 per config. They happen when you run `bunny-snapshot create`, which
snapshots both, plus the one-off factory snapshot below.

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

This rolls back `/` only — `home` is a separate config, so a reset keeps your files.

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
| `Mod+Shift+S` | System menu (sound, Wi-Fi, Bluetooth) |
| `Mod+Shift+Space` | Hivemind prompt — a text prompt that runs your query in a floating terminal |
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
| `XF86AudioRaiseVolume` | Volume +10%, capped at 100%, with an on-screen level popup |
| `XF86AudioLowerVolume` | Volume −10%, with an on-screen level popup |
| `XF86AudioMute` | Mute/unmute output, with an on-screen popup |
| `XF86AudioMicMute` | Mute/unmute microphone, with an on-screen popup |
| `XF86AudioPlay` | Play/pause |
| `XF86AudioStop` | Stop |
| `XF86AudioPrev` / `XF86AudioNext` | Previous/next track |

All of these keep working while the session is locked. The volume and mute keys go through
[swayosd](https://github.com/ErikReider/SwayOSD), which applies the change and draws the
overlay; the step size and the 100% cap live in `config/niri/bindings.kdl` and
`config/swayosd/config.toml` respectively.

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
(gpu-screen-recorder, toggles), the volume module to mute/unmute, the network
module for `bunny-launch-wifi`, and the battery module for `bunny-menu power`.

The bar also carries read-only indicators for webcam and screen-share activity, a
workspace-position dot strip (`niri-window-position`), and a weather module — see
[Weather](#weather) below, which needs one command to set up.

## Commands

Scripts with no keyboard shortcut or menu entry — invoke these manually from a terminal.

| Command | Description |
|---|---|
| `bunny-theme-background` | Set desktop wallpaper from a file path or URL |
| `bunny-dev` | Install, inspect, or remove optional development environments |
| `bunny-update` | Update system packages and optionally reboot |
| `bunny-migrate` | Re-link arch-bunny's dotfiles and remove orphaned symlinks |
| `bunny-snapshot <create\|restore\|delete>` | Snapper snapshots across every configured config |
| `bunny-snapshot-list` | Snapshot disk usage, human-readable |
| `bunny-update-location [--add <location>]` | Map the current Wi-Fi SSID to a weather location |
| `bunny-clear-workspace [--unfocused]` | Close every window on the current workspace, or all but the focused one |
| `bunny-notify` | `notify-send` wrapper that picks a bunny icon by urgency; used by the other scripts |

## Notifications

Two things generate desktop notifications on their own, both through `bunny-notify`
into mako:

**Battery.** A udev rule on the kernel `power_supply` uevent (`install/default/udev/`)
runs `bunny-battery-notify` — a warning at 20% and a critical one at 5%, while
discharging only. No polling timer and no resident watcher; the event already fires.

**Calendar.** `bunny-calendar-notify.timer` polls every 60s for upcoming Google Calendar
events and notifies at each event's own reminder time (10 minutes when the event sets
none). It needs no API credentials or extra packages — it reads private iCal URLs.
To set it up, put one "secret address in iCal format" URL per line in
`~/.config/bunny/calendar-ics-url` (Google Calendar → Settings → pick a calendar →
Integrate calendar), then:

```bash
systemctl --user enable --now bunny-calendar-notify.timer
```

Recurring events are handled for `FREQ=DAILY` and `FREQ=WEEKLY;BYDAY=…` only.

**Dismissal** is `Mod+Comma` (top notification) and `Mod+Shift+Comma` (all), with
`bunny-toggle-dnd` on the bar's notification indicator.

### Weather

The bar's weather module reads `~/.config/bunny/weather-location`, and
`bunny-update-location.timer` keeps that in step with wherever you are: it looks the
connected SSID up in `~/.config/bunny/wifi-locations.json` and writes the mapped
location. Register the network you are on with:

```bash
bunny-update-location --add "Portland, OR"
```

On an unmapped SSID the module shows a hint to run that; with no network at all it
shows nothing.

## Shell

Bash, with `nvim` as `EDITOR`, starship for the prompt, and direnv hooked in.

| Alias / function | Does |
|---|---|
| `vi` | `nvim` |
| `clear` | Clears the screen *and* the scrollback buffer (`\e[3J`), which plain `clear` leaves behind |
| `conda` | Lazy stub — sources miniforge's `conda.sh` on first call, so shell startup pays nothing |
| `gu` | Stash, check out the repo's default branch (`main` or `master`), pull, return to your branch, pop |
| `gur` | `gu`, then rebase onto the default branch |
| `guri` | `gu`, then interactive rebase onto the default branch |

`~/.personal.bashrc` is sourced last if it exists, and is never tracked by git.

Up and Down filter history to lines starting with what you have already typed
(`~/.inputrc`); an empty line behaves like ordinary previous/next history.

Git ships a few aliases of its own — `co`, `br`, `ci`, `st` — plus rebase-on-pull,
`autoSetupRemote` on push, and `gh` as the credential helper. Set your identity the
ordinary way:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

That deliberately does *not* write into this repo. Git's global config is
`~/.gitconfig` when that file exists and `~/.config/git/config` only when it does
not — and the latter is a symlink to the tracked file, so on a bare setup a plain
`--global` write would commit your name and email into arch-bunny. `install/20-dotfiles.sh`
creates `~/.gitconfig` for exactly that reason. Git reads both files, and anything in
`~/.gitconfig` wins, so it is also where any other machine-local override belongs.

## tmux

| Binding | Action |
|---|---|
| `prefix+f` | `tmux-sessionizer` — fzf a project directory, then create or attach a session named for it |

Sessions are named `<dir>-<hash>`, so same-named directories in different trees stay
distinct.

## Stack

| Category | Tools |
|---|---|
| **Compositor** | [niri](https://github.com/YaLTeR/niri) — scrollable-tiling Wayland compositor |
| **Session manager** | [uwsm](https://github.com/Vladimir-csp/uwsm) — Universal Wayland Session Manager |
| **Login manager** | [greetd](https://sr.ht/~kennylevinsen/greetd/) |
| **Terminal** | [kitty](https://sw.kovidgoyal.net/kitty/) |
| **Bar** | [Waybar](https://github.com/Alexays/Waybar) |
| **Launcher** | [fuzzel](https://codeberg.org/dnkl/fuzzel) for apps and clipboard history · [bemenu](https://github.com/Cloudef/bemenu) for the power and system menus |
| **Notifications** | [mako](https://github.com/emersion/mako) |
| **Lock screen** | [hyprlock](https://github.com/hyprwm/hyprlock) |
| **Wallpaper** | [swaybg](https://github.com/swaywm/swaybg) |
| **Idle management** | [swayidle](https://github.com/swaywm/swayidle) |
| **OSD overlays** | [swayosd](https://github.com/ErikReider/SwayOSD) |
| **Boot splash** | [plymouth](https://gitlab.freedesktop.org/plymouth/plymouth), with the `bunny` theme from `install/default/plymouth/` |
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
| **Networking** | systemd-networkd (ethernet) + [iwd](https://iwd.wiki.kernel.org/) (Wi-Fi), systemd-resolved for DNS |
| **Power** | power-profiles-daemon |
| **Shell** | bash + [starship](https://starship.rs/) prompt + [direnv](https://direnv.net/) |
| **Multiplexer** | [tmux](https://github.com/tmux/tmux) |
| **CLI tools** | [bat](https://github.com/sharkdp/bat) · [fd](https://github.com/sharkdp/fd) · [fzf](https://github.com/junegunn/fzf) · [ripgrep](https://github.com/BurntSushi/ripgrep) · [jq](https://jqlang.github.io/jq/) · [gh](https://cli.github.com/) · [fastfetch](https://github.com/fastfetch-cli/fastfetch) |
| **Dotfiles management** | [GNU stow](https://www.gnu.org/software/stow/), with `--no-folding` for `config`/`local` so only leaf files are symlinked |
