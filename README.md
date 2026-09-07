# SpotX-Linux (universal)

Adblock patcher for the Spotify desktop client on **any Linux distro**:
Arch/CachyOS, Debian/Ubuntu, Fedora, openSUSE, Gentoo, etc.

* Patches `Apps/xpui.spa` (`xpui.js`/`xpui.css`) with perl regexes (version-gated,
  same idea as `SpotX-Windows` `patches/patches.json` and `SpotX-Bash`).
* Byte-patches the native `spotify` ELF for ad/logic slots (subset of `SpotX-Bash` `freeEx`).
* Handles root-owned installs (`/opt/spotify`, `/usr/share/spotify`) via sudo
  staging, and user-owned installs (`spotify-launcher`, Flatpak) without sudo.
* Deps: `bash`, `perl`, `curl` + (`unzip`+`zip` **or** `python3`).
* Snap installs are rejected (read-only squashfs) — migrate to Flatpak/native.

## Installation (simple, no one-liner)

```bash
git clone https://github.com/<YOU>/<REPO>.git
cd <REPO>/linux
./spotx.sh --help     # run directly, no install needed
```

Optional: install the `spotx` command system-wide:

```bash
./install.sh                  # -> /usr/local/bin/spotx (sudo if needed)
./install.sh --prefix ~/.local # user install, no sudo (-> ~/.local/bin/spotx)
./install.sh --uninstall       # remove it again
```

Arch/CachyOS (AUR):

```bash
cd linux
makepkg -si                   # builds + installs spotx-linux from ./PKGBUILD
# or with an AUR helper once published: yay -S spotx-linux
```

## Install Spotify first (per distro)

| Distro | Command |
|---|---|
| Arch/CachyOS | `yay -S spotify-launcher` (or `spotify`, or flatpak) |
| Debian/Ubuntu | Spotify apt repo (`spotify-client`) or `flatpak install flathub com.spotify.Client` |
| Fedora | `flatpak install flathub com.spotify.Client` (or RPM Fusion) |
| openSUSE | `flatpak install flathub com.spotify.Client` (or `opi spotify`) |
| Any | `flatpak install flathub com.spotify.Client` |
| Custom | `./spotx.sh -P /path/to/spotify` (dir containing `Apps/xpui.spa`) |

Auto-detected paths: `/opt/spotify`, `/usr/share/spotify`,
`~/.local/share/spotify-launcher/install/usr/share/spotify`,
Flatpak system+user locations, `spotify` on `PATH`, bounded `find` fallback.

## Options

```
-h, --hide             hide podcasts/audiobooks/episodes on home
-p, --premium          premium account (skip free-tier ad patches)
-e, --noexp            skip experimental features
-d, --devmode          enable developer mode
-o, --oldui            old home UI (only <= 1.2.13.661)
-l, --lyricsbg         black background for lyrics
-c, --clearcache       clear app cache
-f, --force            force re-patch even if backup exists
-P <path>              custom Spotify install dir
-i, --interactive      interactive mode
--noninteractive       no prompts
--installflatpak       install Spotify via flatpak, then re-run
--installdeb           info for apt-based install (Debian/Ubuntu only)
--uninstall            restore .bak backups
-v, --version          print version
```

## Uninstall

```bash
./spotx.sh --uninstall [-P /path/to/spotify]
```

Restores `spotify.bak` + `Apps/xpui.bak`.

## Status / roadmap to full parity

MVP (`0.1.0`, verified with fake `xpui.spa`: patch + repack + uninstall round-trip
works, `bash -n` clean):
core adblock (`adsEnabled`, `allSponsorships`, product-state override,
download-quality hide), logging block (`sentry.io`, `sp://logging/v3`),
`bSlot`/`bLogic` ELF stubs, devmode, hide-non-music, equalizer/viewmode/
sidebar/fullscreen/sleep-timer exp subset, lyrics-bg.

Next for full `SpotX-Windows` parity: sync the full `patches/patches.json`
(`DisableExp`/`EnableExp`/`CustomExp` ~150 flags, `new_theme`, `cache_limit`,
`goofyHistory`, `sectionBlock.js` injection, `lyrics_stat` colors) into the
`aoEx/expEx` arrays, and validate ELF binary patches against real Linux
`spotify` builds per version.

## Credits / license

MIT. Based on `SpotX-Windows` (MIT © 2021-2026 amd64fox) and ideas from
`SpotX-Bash`. Keep the copyright notices above when redistributing.
