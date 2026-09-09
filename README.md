# SpotX-Linux (universal)

Adblock patcher for the Spotify desktop client on **any Linux distro**:
Arch/CachyOS, Debian/Ubuntu, Fedora, openSUSE, Gentoo, etc.

* Patches `Apps/xpui.spa` (`xpui.js` / `xpui-snapshot.js` + CSS) with
  version-gated perl regexes (same idea as `SpotX-Windows`
  `patches/patches.json` and `SpotX-Bash`; newer snapshot-based clients
  are handled by extracting the webpack modules first).
* Byte-patches the native `spotify` ELF for ad/logic slots.
* Handles root-owned installs (`/opt/spotify`, `/usr/share/spotify`) via
  sudo staging, and user-owned installs (`spotify-launcher`, Flatpak)
  without sudo.
* Snap installs are rejected (read-only squashfs) — migrate to Flatpak/native.

## Requirements

```bash
# Tools needed: bash, perl, curl + (unzip+zip OR python3)
# Arch/CachyOS:
sudo pacman -S --needed bash perl curl unzip zip python git
# Debian/Ubuntu:
sudo apt install bash perl curl unzip zip python3 git
# Fedora:
sudo dnf install bash perl curl unzip zip python3 git
```

## Step 1 — Install Spotify (if you don't have it)

| Distro | Command |
|---|---|
| Arch/CachyOS | `yay -S spotify-launcher` (or the `spotify` package, or Flatpak) |
| Debian/Ubuntu | Spotify apt repo (`spotify-client`), or Flatpak below |
| Fedora / openSUSE / any | `flatpak install flathub com.spotify.Client` |

Flatpak (works everywhere; `--user` needs no sudo):

```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub com.spotify.Client
```

## Step 2 — Get spotx-linux

```bash
git clone https://github.com/Aryansjc/spotx-linux.git
cd spotx-linux
./spotx.sh --help
```

## Step 3 — Patch it

Make sure Spotify is **fully quit first** (tray icon → Quit), then:

```bash
./spotx.sh
```

That's it for most users — auto-detects `/opt/spotify`,
`/usr/share/spotify`, `spotify-launcher`, Flatpak (system + user),
`spotify` on `PATH`, with a bounded `find` fallback. Then open Spotify.

If auto-detect fails, point at the client dir (the one containing
`Apps/xpui.spa`):

```bash
./spotx.sh -P /path/to/spotify
./spotx.sh -P ~/.local/share/flatpak/app/com.spotify.Client/current/active/files/extra/share/spotify
```

Root-owned installs will ask for sudo once; user-owned ones won't.

## All commands

```bash
./spotx.sh --help            # show all options
./spotx.sh --version         # print version

./spotx.sh                   # default: adblock + exp features (free account)
./spotx.sh -p                # premium account (skip free-tier ad patches)
./spotx.sh --premium

./spotx.sh -h                # hide podcasts/audiobooks/episodes on home
./spotx.sh --hide

./spotx.sh -d                # enable developer mode
./spotx.sh --devmode

./spotx.sh -e                # skip experimental features (adblock still applies)
./spotx.sh --noexp

./spotx.sh -l                # black background for lyrics
./spotx.sh --lyricsbg

./spotx.sh -o                # old home UI (only client <= 1.2.13.661)
./spotx.sh --oldui

./spotx.sh -c                # clear app cache while patching
./spotx.sh --clearcache

./spotx.sh -i                # interactive mode (asks y/n per option)
./spotx.sh --interactive
./spotx.sh --noninteractive  # never prompt (fail instead of asking)

./spotx.sh -f                # force re-patch over an existing install
./spotx.sh --force

./spotx.sh -P /path/to/spotify   # custom client directory
./spotx.sh --path /path/to/spotify

./spotx.sh --installflatpak  # install Spotify via flatpak, then re-run
./spotx.sh --installdeb      # apt-based install info (Debian/Ubuntu only)

./spotx.sh --uninstall       # restore pristine .bak backups
```

Flags combine, e.g. premium + hide non-music + dark lyrics:

```bash
./spotx.sh -p -h -l
```

## Common recipes

```bash
# After a Spotify update (updates overwrite the patch):
./spotx.sh -f

# Change your options later (e.g. switch to premium flags):
./spotx.sh -f -p

# Non-interactive one-shot for scripts:
./spotx.sh --noninteractive -f
```

## Install the `spotx` command (optional)

```bash
./install.sh                    # -> /usr/local/bin/spotx (sudo if needed)
./install.sh --prefix ~/.local  # user install, no sudo (-> ~/.local/bin/spotx)
./install.sh --uninstall        # remove it again
```

Arch/CachyOS (AUR-style build from this repo):

```bash
makepkg -si                     # builds + installs spotx-linux from ./PKGBUILD
```

## Uninstall

Remove the patch (restores byte-identical `spotify.bak` + `Apps/xpui.bak`):

```bash
./spotx.sh --uninstall
```

Remove Spotify itself too (optional):

```bash
flatpak uninstall --user com.spotify.Client
```

## Troubleshooting

* **Spotify shows a black screen after patching** — you are running an old
  build; pull latest (`git pull`) and re-patch with `-f`. Always fully quit
  Spotify (tray → Quit) before patching so it reloads the files.
* **`SpotX already installed`** — re-run with `-f`, or `--uninstall` first.
* **`Client not found`** — install Spotify (Step 1) or pass `-P`.
* **`... not supported`** — your client is older than the minimum supported
  version; update Spotify, then re-patch with `-f`.
* **Snap detected** — Snap mounts are read-only and can't be patched; move
  to Flatpak or a native package.
* **Permission errors on `/opt`/`/usr/share`** — rerun with sudo access
  available; the script stages and commits files safely.

## Status / testing

**Real-client tested 17/17** (`tests/real_client_test.sh` on Spotify
1.2.95.453 Flatpak): snapshot extraction, 45 enabled + 26 disabled exp
flags, adblock markers, flag matrix, idempotency, binary runs pre/post
patch, byte-identical uninstall restore. Patched client launches with the
same process tree as pristine.

Patch coverage: core adblock, logging block, `bSlot`/`bLogic` ELF stubs,
devmode, hide-non-music, base exp subset, lyrics-bg — plus **246 synced
flags** (`tools/generated_exp.inc`, built from `vendor/patches.json` via
`tools/sync_from_patches.py`: 92 `DisableExp`→false + ad-suppress
`CustomExp` always-on, 131 `EnableExp`→true + feature `CustomExp`
with exp; all version-gated, `--noexp`-aware, crash-safe, verified).

Still open: `new_theme`/`cache_limit`/`goofyHistory`/`sectionBlock.js`
injection/`lyrics_stat` colors.

## Credits / license

MIT. Based on `SpotX-Windows` (MIT © 2021-2026 amd64fox) and ideas from
`SpotX-Bash`. Keep the copyright notices above when redistributing.
