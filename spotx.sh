#!/usr/bin/env bash
#
# SpotX-Linux — universal adblock patcher for the Spotify desktop client on Linux.
#
# Based on ideas from SpotX-Windows (PowerShell, MIT (c) 2021-2026 amd64fox)
# and SpotX-Bash (bash, Linux/macOS). MIT licensed — keep copyright notices.
#
# One-liner:
#   bash <(curl -sSL https://raw.githubusercontent.com/<you>/spotx-linux/main/linux/spotx.sh)
#
# Distro-agnostic: works on Arch, Debian/Ubuntu, Fedora, openSUSE, etc.
# Supports: /opt/spotify, /usr/share/spotify, ~/.local/share/spotify-launcher,
#           Flatpak (system + user), custom path via -P. Snap is detected and
#           rejected with instructions (use spotx-snap.sh approach instead).
#
# Deps: bash, perl, curl, (unzip+zip OR python3)
#

set -u

SPOTX_LINUX_VER="0.1.0"
SUPPORTED_MIN="1.1.59.710"

clr='\033[0m'
green='\033[0;32m'
red='\033[0;31m'
yellow='\033[0;33m'

# ---------------- args ----------------
paidPremium=''
hideNonMusic=''
excludeExp=''
devMode=''
oldUi=''
lyricsBg=''
clearCache=''
forceSpotx=''
installPathSet=''
installPath=''
uninstallSpotx=''
nonInteractive=''
interactiveMode=''
installFlatpak=''
installDeb=''
verPrint=''

show_help() {
  cat <<'EOF'
Usage: spotx.sh [options]

Options:
  -h, --hide             hide podcasts/audiobooks/episodes on home
  -p, --premium          premium account (skip free-tier ad patches)
  -e, --noexp            skip experimental features
  -d, --devmode          enable developer mode
  -o, --oldui            use old home UI (only <= 1.2.13.661)
  -l, --lyricsbg         black background for lyrics
  -c, --clearcache       clear app cache
  -f, --force            force re-patch even if backup exists
  -P <path>, --path      custom Spotify install dir (contains Apps/xpui.spa)
  -i, --interactive      interactive mode
  --noninteractive       no prompts (fail instead of asking)
  --nocolor              no colors
  --installflatpak       install Spotify via flatpak (universal)
  --installdeb           install Spotify .deb via apt (Debian/Ubuntu only)
  --uninstall            restore backup (.bak) files
  -v, --version          print version
  --help                 this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--hide) hideNonMusic='true'; shift ;;
    -p|--premium) paidPremium='true'; shift ;;
    -e|--noexp) excludeExp='true'; shift ;;
    -d|--devmode) devMode='true'; shift ;;
    -o|--oldui) oldUi='true'; shift ;;
    -l|--lyricsbg) lyricsBg='true'; shift ;;
    -c|--clearcache) clearCache='true'; shift ;;
    -f|--force) forceSpotx='true'; shift ;;
    -P|--path) installPath="${2:-}"; installPathSet='true'; shift 2 ;;
    -i|--interactive) interactiveMode='true'; shift ;;
    --noninteractive) nonInteractive='true'; shift ;;
    --nocolor) clr=''; green=''; red=''; yellow=''; shift ;;
    --installflatpak) installFlatpak='true'; shift ;;
    --installdeb) installDeb='true'; shift ;;
    --uninstall) uninstallSpotx='true'; shift ;;
    -v|--version) verPrint='true'; shift ;;
    --help) show_help; exit 0 ;;
    *) echo -e "${red}Error:${clr} unknown option: $1\n" >&2; show_help >&2; exit 1 ;;
  esac
done

[[ -n "$verPrint" ]] && { echo "spotx-linux $SPOTX_LINUX_VER"; exit 0; }

# ---------------- deps ----------------
need() { command -v "$1" >/dev/null 2>&1 || { echo -e "${red}Error:${clr} '$1' not found. Install it and retry." >&2; exit 1; }; }
need bash; need perl; need curl
if command -v unzip >/dev/null 2>&1; then HAVE_UNZIP=1; else HAVE_UNZIP=''; fi
if command -v zip >/dev/null 2>&1; then HAVE_ZIP=1; else HAVE_ZIP=''; fi
if [[ -z "${HAVE_UNZIP:-}" || -z "${HAVE_ZIP:-}" ]]; then
  need python3
  HAVE_PYTHON=1
fi

# ---------------- helpers ----------------
ver() { echo "$@" | perl -lane 'printf "%d%03d%04d%05d\n", split(/\./, $_), (0)x4'; }

zip_extract() { # $1=spa $2=dest
  if [[ -n "${HAVE_UNZIP:-}" ]]; then unzip -qq "$1" -d "$2";
  else python3 -c 'import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$1" "$2"; fi
}
zip_repack() { # $1=srcdir $2=out_spa
  if [[ -n "${HAVE_ZIP:-}" ]]; then (cd "$1" && zip -qq -r "$2" .) ;
  else python3 -c 'import zipfile,os,sys; s=sys.argv[1]; o=sys.argv[2];
import pathlib
with zipfile.ZipFile(o,"w",zipfile.ZIP_DEFLATED) as z:
  for r,d,f in os.walk(s):
    for n in f:
      p=os.path.join(r,n); z.write(p, os.path.relpath(p,s))' "$1" "$2"; fi
}
zip_test() {
  if [[ -n "${HAVE_UNZIP:-}" ]]; then unzip -tqq "$1" >/dev/null 2>&1;
  else python3 -c 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); b=z.testzip(); raise SystemExit(1 if b else 0)' "$1"; fi
}

# sudo / staged install (root-owned /opt, /usr/share)
stagedInstall=''; protectedInstall=''
check_write_permission() {
  local p w
  for p in "$@"; do
    [[ -d "$p" ]] && w="$p" || w="${p%/*}"
    if [[ ! -w "$p" ]]; then stagedInstall='true'; fi
    if [[ ! -w "$w" || ( -f "$p" && ! -O "$p" ) ]]; then
      stagedInstall='true'; protectedInstall='true'
      if ((EUID != 0)); then
        command -v sudo >/dev/null || { echo -e "${red}Error:${clr} need write access to $w (run with sudo or install sudo)." >&2; exit 1; }
        sudo -n true 2>/dev/null || { echo -e "${yellow}Requesting sudo for:${clr} $w"; sudo -v || exit 1; }
      fi
    fi
  done
}
sudo_run() { if ((EUID == 0)) || [[ -z "$protectedInstall" ]]; then command "$@"; else sudo "$@"; fi; }

# ---------------- path detection (distro-agnostic) ----------------
linux_resolve_client_path() {
  local base="${1%/}" c
  [[ -n "$base" ]] || return 1
  for c in "$base" "$base/extra/share/spotify" "$base/share/spotify" \
           "$base/files/extra/share/spotify" "$base/files/share/spotify"; do
    [[ -f "$c/Apps/xpui.spa" ]] && { installPath="$c"; return 0; }
  done
  return 1
}

linux_search_path() {
  local xpuiFile bin floc
  linux_resolve_client_path "/opt/spotify" && return 0
  linux_resolve_client_path "/usr/share/spotify" && return 0
  linux_resolve_client_path "/usr/lib64/spotify-client" && return 0
  linux_resolve_client_path "$HOME/.local/share/spotify-launcher/install/usr/share/spotify" && return 0
  linux_resolve_client_path "$HOME/.local/share/spotify" && return 0
  bin="$(command -v spotify 2>/dev/null || true)"
  if [[ -n "$bin" ]]; then
    bin="$(readlink -f "$bin" 2>/dev/null || echo "$bin")"
    linux_resolve_client_path "${bin%/*}" && return 0
    linux_resolve_client_path "${bin%/*}/../share/spotify" && return 0
  fi
  if command -v flatpak >/dev/null 2>&1; then
    floc="$(flatpak info --show-location com.spotify.Client 2>/dev/null || true)"
    [[ -n "$floc" ]] && { linux_resolve_client_path "$floc" && { clientVariant='flatpak'; return 0; }; }
    for floc in "$HOME/.local/share/flatpak/app/com.spotify.Client" "/var/lib/flatpak/app/com.spotify.Client"; do
      linux_resolve_client_path "$floc/current/active/files/extra/share/spotify" && { clientVariant='flatpak'; return 0; }
    done
  fi
  # last resort: bounded find (no snap paths)
  for p in /opt /usr/share /usr/lib "$HOME/.local/share"; do
    [[ -d "$p" ]] || continue
    xpuiFile="$(timeout 8 find "$p" \( -path "*/snap*" -o -path "*flatpak/.removed*" \) -prune -o -type f -path "*/Apps/xpui.spa" -print -quit 2>/dev/null || true)"
    if [[ -n "$xpuiFile" ]]; then installPath="${xpuiFile%/Apps/xpui.spa}"; return 0; fi
  done
  return 1
}

if [[ -n "$installDeb" ]]; then
  command -v apt >/dev/null || { echo -e "${red}Error:${clr} --installdeb needs an APT distro (Debian/Ubuntu)." >&2; exit 1; }
  echo -e "${yellow}Note:${clr} --installdeb downloads the Spotify .deb via apt repo. Run 'sudo apt install spotify-client' equivalent, then re-run without the flag."
  exit 0
fi
if [[ -n "$installFlatpak" ]]; then
  command -v flatpak >/dev/null || { echo -e "${red}Error:${clr} flatpak not installed. See https://flatpak.org/setup/." >&2; exit 1; }
  flatpak install -y flathub com.spotify.Client
  echo "Installed. Re-run spotx.sh without flags."
  exit 0
fi

if [[ -n "$installPathSet" ]]; then
  req="${installPath%/}"
  if [[ "$req" == *snap* ]]; then echo -e "${red}Error:${clr} Snap is sandboxed (read-only squashfs). Use Flatpak or native package instead." >&2; exit 1; fi
  linux_resolve_client_path "$req" || { echo -e "${red}Error:${clr} no Apps/xpui.spa under: $req" >&2; exit 1; }
  echo -e "Using client dir: $installPath\n"
else
  echo -e "Searching for Spotify client...\n"
  if linux_search_path; then
    echo -e "Found client dir: ${green}$installPath${clr}\n"
  else
    echo -e "${red}Error:${clr} Spotify not found." >&2
    echo -e "Install it first, then re-run. Per distro:" >&2
    echo -e "  Arch/CachyOS : ${green}yay -S spotify-launcher${clr}  (or spotify, or flatpak)" >&2
    echo -e "  Debian/Ubuntu: spotify-client via Spotify apt repo, or ${green}flatpak install flathub com.spotify.Client${clr}" >&2
    echo -e "  Fedora       : ${green}flatpak install flathub com.spotify.Client${clr} (or RPM Fusion / lpf)" >&2
    echo -e "  openSUSE     : ${green}flatpak install flathub com.spotify.Client${clr} or opi spotify" >&2
    echo -e "  Any distro   : ${green}flatpak install flathub com.spotify.Client${clr}" >&2
    echo -e "  Custom path  : $0 -P /path/to/spotify" >&2
    exit 1
  fi
fi

# snap guard
if [[ "$installPath" == *snap* ]]; then echo -e "${red}Error:${clr} Snap install detected — read-only, cannot patch. Migrate to Flatpak/native." >&2; exit 1; fi

appPath="$installPath"
appBinary="$appPath/spotify"
xpuiPath="$appPath/Apps"
xpuiSpa="$xpuiPath/xpui.spa"
xpuiBak="$xpuiPath/xpui.bak"
appBak="$appBinary.bak"
xpuiDir="$xpuiPath/xpui"

xpuiJs="$xpuiDir/xpui.js"
xpuiCss="$xpuiDir/xpui.css"
xpuiDesktopModalsJs="$xpuiDir/xpui-desktop-modals.js"
homeV2Js="$xpuiDir/home-v2.js"
vendorXpuiJs="$xpuiDir/vendor~xpui.js"

# ---------------- version ----------------
clientVer=''
if "$appBinary" --version >/dev/null 2>&1; then
  clientVer="$("$appBinary" --version 2>/dev/null | grep -oE '1\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
fi
echo -e "Detected client version: ${clientVer:-${red}N/A${clr}}"
if [[ -n "$clientVer" ]] && (($(ver "$clientVer") < $(ver "$SUPPORTED_MIN"))); then
  echo -e "${red}Error:${clr} $clientVer < minimum $SUPPORTED_MIN" >&2; exit 1
fi

command pkill -9 '[sS]potify' 2>/dev/null || true

check_write_permission "$appPath" "$appBinary" "$xpuiPath" "$xpuiSpa"

# staged copy for root-owned installs
targetAppBinary="$appBinary"; targetXpuiSpa="$xpuiSpa"
targetAppBak="$appBak"; targetXpuiBak="$xpuiBak"
workDir=''
if [[ -n "$stagedInstall" && -n "$protectedInstall" ]]; then
  workDir="$(mktemp -d /tmp/spotx-linux.XXXXXXXX)" && chmod 700 "$workDir"
  mkdir -p "$workDir/client/Apps"
  appPath="$workDir/client"; appBinary="$appPath/spotify"; appBak="$appBinary.bak"
  xpuiPath="$appPath/Apps"; xpuiSpa="$xpuiPath/xpui.spa"; xpuiBak="$xpuiPath/xpui.bak"; xpuiDir="$xpuiPath/xpui"
  xpuiJs="$xpuiDir/xpui.js"; xpuiCss="$xpuiDir/xpui.css"
  xpuiDesktopModalsJs="$xpuiDir/xpui-desktop-modals.js"; homeV2Js="$xpuiDir/home-v2.js"; vendorXpuiJs="$xpuiDir/vendor~xpui.js"
  sudo_run cat -- "$targetAppBinary" > "$appBinary"
  sudo_run cat -- "$targetXpuiSpa" > "$xpuiSpa"
  chmod 600 "$appBinary" "$xpuiSpa"
  [[ -f "$targetAppBak" ]] && { sudo_run cat -- "$targetAppBak" > "$appBak"; }
  [[ -f "$targetXpuiBak" ]] && { sudo_run cat -- "$targetXpuiBak" > "$xpuiBak"; }
fi
cleanup() { [[ -n "${workDir:-}" && -d "$workDir" ]] && rm -rf "$workDir"; }
trap cleanup EXIT

atomic_copy() { local s="$1" d="$2" t; t="$(mktemp -d "${d}.spotx.XXXXXXXX")"; cp "$s" "$t/$(basename "$d")" && mv -f "$t/$(basename "$d")" "$d"; local r=$?; rm -rf "$t"; return $r; }
backup_spotx() { atomic_copy "$xpuiSpa" "$xpuiBak" && atomic_copy "$appBinary" "$appBak"; }
uninstall_spotx() { atomic_copy "$appBak" "$appBinary" && atomic_copy "$xpuiBak" "$xpuiSpa"; rm -f "$appBak" "$xpuiBak"; rm -rf "$xpuiDir"; }

# ---------------- uninstall ----------------
if [[ -n "$uninstallSpotx" ]]; then
  [[ -f "$appBak" && -f "$xpuiBak" ]] || { echo -e "${red}Error:${clr} no .bak backup found." >&2; exit 1; }
  uninstall_spotx || { echo -e "${red}Error:${clr} restore failed." >&2; exit 1; }
  if [[ -n "$stagedInstall" ]]; then
    sudo_run cp -- "$appBinary" "$targetAppBinary" && sudo_run cp -- "$xpuiSpa" "$targetXpuiSpa" \
      && sudo_run rm -f -- "$targetAppBak" "$targetXpuiBak" || { echo -e "${red}Error:${clr} sudo commit failed." >&2; exit 1; }
  fi
  echo -e "${green}Uninstalled — backups restored.${clr}"; exit 0
fi

[[ -f "$xpuiSpa" ]] || { echo -e "${red}Error:${clr} xpui.spa missing: $xpuiSpa" >&2; exit 1; }

# existing install?
if [[ -f "$appBak" || -f "$xpuiBak" ]] && [[ -z "$forceSpotx" ]]; then
  echo -e "${yellow}SpotX already installed.${clr} Use -f/--force to re-patch, or --uninstall to restore."
  exit 0
fi
if [[ -n "$forceSpotx" && -f "$xpuiBak" ]]; then atomic_copy "$xpuiBak" "$xpuiSpa"; echo "Restored backup before re-patch."; fi
backup_spotx || { echo -e "${red}Error:${clr} backup failed." >&2; exit 1; }
echo -e "${green}Created backup (.bak).${clr}"

# ---------------- unpack ----------------
rm -rf "$xpuiDir"; mkdir -p "$xpuiDir"
zip_extract "$xpuiSpa" "$xpuiDir" || { echo -e "${red}Error:${clr} unpack xpui.spa failed." >&2; exit 1; }
if [[ ! -f "$xpuiJs" ]]; then echo -e "${red}Error:${clr} xpui.js not found after unpack (modified client?)." >&2; exit 1; fi
if [[ -z "$clientVer" ]]; then
  clientVer="$(perl -ne '/[Vv]ersion[:=,\x22]{1,3}(1\.[0-9]+\.[0-9]+\.[0-9]+)\.g[0-9a-f]+/ && print "$1"' "$xpuiJs" | head -n1)"
  [[ -z "$clientVer" ]] && clientVer="9.9.9.9"
  echo "Version from xpui.js: $clientVer"
fi

# ---------------- patch engine (perl, version-gated) ----------------
perlVar="perl -0777pi -w -e"
apply_patch() { # name|match|replace|flags|file|fr|to ; mirrors SpotX-Bash perlVar + patches.json fr/to
  local a
  IFS='&' read -r -a a <<< "$1"
  local name="${a[0]}" match="${a[1]:-}" repl="${a[2]:-}" flags="${a[3]:-}" fvar="${a[4]:-}" fr="${a[5]:-}" to="${a[6]:-}"
  [[ -z "$match" ]] && return 0
  if [[ -n "$fr" ]] && (($(ver "$clientVer") < $(ver "$fr"))); then return 0; fi
  if [[ -n "$to" ]] && (($(ver "$clientVer") > $(ver "$to"))); then return 0; fi
  local p=""
  if [[ -n "$fvar" ]]; then p="${!fvar}"; fi
  [[ -n "$p" && -f "$p" ]] || return 0
  # shellcheck disable=SC2086
  $perlVar 'BEGIN{$m=0} $m += s&'"$match"'&'"$repl"'&'"$flags"'; END{}' "$p" 2>/dev/null || true
}

# Core ad/logic blocks (subset of SpotX-Bash aoEx + Windows patches.json free.*).
aoEx=(
'adsEmptyBlock&adsEnabled:!\K0&1&&xpuiJs'
'sponsors&allSponsorships&&g&xpuiJs'
'hideUpgradeButton&(return|.=.=>)"free"===(.+?)(return|.=.=>)"premium"===&$1"premium"===$2$3"free"===&g&xpuiJs&1.1.59.710&1.1.92.647'
'adsCosmos&(case .:|async enable\(.\)\{)(this.enabled=.+?\(.{1,3},"audio"\),|return this.enabled=...+?\(.{1,3},"audio"\))((;case 4:)?this.subscription=this.audioApi).+?this.onAdMessage\)&$1$3.cosmosConnector.increaseStreamTime(-100000000000)&&xpuiJs&1.1.59.710&1.1.92.647'
'connectOld& connect-device-list-item--disabled&&&&xpuiJs&1.1.70.610&1.1.90.859'
'logSentry&sentry\.io&localhost.io&&xpuiJs&1.1.70.610'
'logV3&sp://logging/v3/\w+&&g&xpuiJs&1.1.70.610'
)
freeEx=(
'esperantoProductState&(this\.(?:productStateApi|_product_state)(?:|_service)=(.))(?=}|(?:,.{1,30})?,this\.productStateApi|,this\._events)&$1,$2.putOverridesValues({pairs:{ads:'\''0'\'',catalogue:'\''premium'\'',type:'\''premium'\'',name:'\''Spotify'\''}})&&xpuiJs'
'hideDlQual&(\(.,..jsxs\)\(.{1,3}|(.\(\).|..)createElement\(.{1,4}),\{(filterMatchQuery|filter:.,title|(variant:"viola",semanticColor:"textSubdued"|..:"span",variant:.{3,6}mesto,color:.{3,6}),htmlFor:"desktop.settings.downloadQuality.+?).{1,6}get\("desktop.settings.downloadQuality.title.+?(children:.{1,2}\(.,.\).+?,|\(.,.\){3,4},|,.\)}},.\(.,.\)\),)&&&xpuiJs&1.1.59.710&1.2.29.605'
)
# Binary (ELF) ad/logic stubs — byte-zeroing like SpotX-Bash freeEx bSlot/bLogic.
binEx=(
'bSlot&\x00\K\x73(?=\x6C\x6F\x74\x73\x00)&\x00&g&appBinary&1.1.70.610'
'bLogic&\x00\K\x61(?=\x64\x2D\x6C\x6F\x67\x69\x63\x2F\x73)&\x00&&appBinary&1.1.70.610&1.2.28.581'
)
devEx=(
'enableDebugTools&debug tools and features for employees",default:\K!1&true&s&xpuiJs&1.2.60.564'
)
podEx=(
'hidePodcasts2&(case 6:|const .=await .\([^\)]*\);)((return .\.abrupt\(\"|return[ \"],?)(null!=n\x26\x26|return\",)?(.)(\);case 9|\??.errors\?.*?Promise.reject.+?errors\)+:.))&$1$5?.data?.home?.sectionContainer?.sections?.items?.forEach(x => x?.sectionItems?.items \x26\x26 (x.sectionItems.items = x.sectionItems.items.filter(i => !['\''Podcast'\'','\''Audiobook'\'','\''Episode'\''].includes(i?.content?.data?.__typename))));$2&&xpuiJs&1.1.86.857&1.2.85.519'
'hidePodcasts3&(try\{let (.)=await [^\(]+\([^\)]*\);)(if\(.\?\.errors\)return[\s\S]+?Promise\.reject\(.\?\.errors\);return .\}catch\(.\))&$1$2?.data?.home?.sectionContainer?.sections?.items?.forEach(x => x?.sectionItems?.items \x26\x26 (x.sectionItems.items = x.sectionItems.items.filter(i => !['\''Podcast'\'','\''Audiobook'\'','\''Episode'\''].includes(i?.content?.data?.__typename))));$3&&xpuiJs&1.2.86.502'
)
expEx=(
'enableEqualizer&audio equalizer for Desktop and Web Player",default:\K!1&true&s&xpuiJs&1.1.88.595'
'enableViewMode&list . compact mode in entity pages",default:\K!1&true&s&xpuiJs&1.2.24.754'
'enableRightSidebar&Enable the view on the right sidebar",default:\K!1&true&s&xpuiJs&1.1.98.683&1.2.93.667'
'enableFullscreenMode&Enable fullscreen mode",default:\K!1&true&s&xpuiJs&1.2.31.1205'
'enableSleepTimer&Sleep timer",default:\K!1&true&s&xpuiJs&1.2.69.448'
)
lyricsBgEx=(
'lyricsBg1&--lyrics-color-inactive":\K(.).inactive&$1.background&&xpuiJs&1.2.0.1165&1.2.44.405'
'lyricsBg2&--lyrics-color-background":\K(.).background&$1.inactive&&xpuiJs&1.2.0.1165&1.2.44.405'
)

# --- interactive ---
if [[ -n "$interactiveMode" && -z "$nonInteractive" ]]; then
  read -r -p "Hide podcasts/audiobooks? [y/N] " yn; [[ "$yn" =~ ^[Yy] ]] && hideNonMusic='true'
  read -r -p "Premium account? [y/N] " yn; [[ "$yn" =~ ^[Yy] ]] && paidPremium='true'
  read -r -p "Enable dev mode? [y/N] " yn; [[ "$yn" =~ ^[Yy] ]] && devMode='true'
fi

# --- run ---
# Full-version generated sets from vendor/patches.json
# (DisableExp/EnableExp/CustomExp). Sourced from alongside the script when
# present (repo checkout or /usr/share/spotx-linux install); falls back to
# the embedded minimal sets.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
genDisableEx=(); genEnableEx=(); genCustomSuppressEx=(); genCustomEnableEx=()
for _inc in "$SCRIPT_DIR/generated_exp.inc" "$SCRIPT_DIR/../share/spotx-linux/generated_exp.inc" \
            "/usr/share/spotx-linux/generated_exp.inc" "$SCRIPT_DIR/tools/generated_exp.inc"; do
  if [[ -f "$_inc" ]]; then
    # shellcheck disable=SC1090
    source "$_inc"; break
  fi
done
unset _inc
for e in "${aoEx[@]}" "${genDisableEx[@]}" "${genCustomSuppressEx[@]}"; do apply_patch "$e"; done
[[ "${#genDisableEx[@]}" -gt 0 ]] && echo -e "${green}Applied ${#genDisableEx[@]} synced disable-flags + ${#genCustomSuppressEx[@]} ad-suppress customs.${clr}"
if [[ -z "$paidPremium" ]]; then
  for e in "${freeEx[@]}" "${binEx[@]}"; do apply_patch "$e"; done
  printf '\n%s\n' '.BKsbV2Xl786X9a09XROH{display:none}' >> "$xpuiCss"
  echo -e "${green}Applied free-tier patches.${clr}"
else echo "Premium mode: skipped ad patches."; fi

if [[ -n "$devMode" ]]; then for e in "${devEx[@]}"; do apply_patch "$e"; done; echo -e "${green}Enabled dev mode.${clr}"; fi
if [[ -z "$excludeExp" ]]; then for e in "${expEx[@]}" "${genEnableEx[@]}" "${genCustomEnableEx[@]}"; do apply_patch "$e"; done; echo -e "${green}Enabled experimental features (${#expEx[@]} base + ${#genEnableEx[@]} synced + ${#genCustomEnableEx[@]} customs).${clr}";
else echo "Skipped experimental features."; fi
if [[ -n "$hideNonMusic" ]]; then for e in "${podEx[@]}"; do apply_patch "$e"; done; echo -e "${green}Hid non-music sections.${clr}"; fi
if [[ -n "$oldUi" ]]; then echo -e "${yellow}Old UI only valid <=1.2.13.661; skipping auto logic in MVP (use -e set + manual).${clr}"; fi
if [[ -n "$lyricsBg" ]]; then for e in "${lyricsBgEx[@]}"; do apply_patch "$e"; done; echo -e "${green}Lyrics background patch.${clr}"; fi
if [[ -n "$clearCache" ]]; then
  rm -rf "$HOME/.cache/spotify/"{Browser,Data} "$HOME/.var/app/com.spotify.Client/cache/spotify/"{Browser,Data} 2>/dev/null || true
  echo "Cache cleared (if existed)."
fi

echo -e "\n//# SpotX-Linux was here" >> "$xpuiJs"

# ---------------- repack + commit ----------------
tmpSpa="$(mktemp /tmp/spotx-linux-spa.XXXXXXXX)"
rm -f "$tmpSpa"
zip_repack "$xpuiDir" "$tmpSpa" || { echo -e "${red}Error:${clr} repack failed." >&2; uninstall_spotx; exit 1; }
zip_test "$tmpSpa" || { echo -e "${red}Error:${clr} repacked spa invalid." >&2; rm -f "$tmpSpa"; uninstall_spotx; exit 1; }
mv -f "$tmpSpa" "$xpuiSpa"
rm -rf "$xpuiDir"

if [[ -n "$stagedInstall" ]]; then
  sudo_run cp -- "$appBinary" "$targetAppBinary" || { echo -e "${red}Error:${clr} sudo commit appBinary failed." >&2; exit 1; }
  sudo_run cp -- "$xpuiSpa" "$targetXpuiSpa" || { echo -e "${red}Error:${clr} sudo commit xpui.spa failed." >&2; exit 1; }
  sudo_run cp -- "$appBak" "$targetAppBak" 2>/dev/null || true
  sudo_run cp -- "$xpuiBak" "$targetXpuiBak" 2>/dev/null || true
  echo -e "${green}Committed with sudo to:${clr} $targetAppBinary"
fi

echo -e "\n${green}Done. Restart Spotify.${clr}"
echo "Uninstall: $0 --uninstall $([[ -n "$installPathSet" ]] && echo "-P $installPath")"
