#!/usr/bin/env bash
#
# Real-client test matrix for spotx-linux.
# Usage: ./tests/real_client_test.sh [-P /path/to/spotify]
# Must be run from the repo root. Exits nonzero on any failure.
#
set -u

HERE="$(cd -- "$(dirname -- "$0")/.." && pwd)"
SPOTX="$HERE/spotx.sh"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "PASS: $*"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $*"; }

# Resolve client dir the same way spotx.sh does (arg or auto-detect).
CLIENT=""
if [[ "${1:-}" == "-P" ]]; then CLIENT="${2:-}"; fi
if [[ -z "$CLIENT" ]]; then
  for c in /opt/spotify /usr/share/spotify \
           "$HOME/.local/share/spotify-launcher/install/usr/share/spotify" \
           "$HOME/.local/share/flatpak/app/com.spotify.Client/current/active/files/extra/share/spotify" \
           "/var/lib/flatpak/app/com.spotify.Client/current/active/files/extra/share/spotify"; do
    if [[ -f "$c/Apps/xpui.spa" ]]; then CLIENT="$c"; break; fi
  done
  if [[ -z "$CLIENT" ]] && command -v flatpak >/dev/null 2>&1; then
    loc="$(flatpak info --show-location com.spotify.Client 2>/dev/null || true)"
    for c in "$loc" "$loc/files/extra/share/spotify" "$loc/files/share/spotify"; do
      if [[ -n "$c" && -f "$c/Apps/xpui.spa" ]]; then CLIENT="$c"; break; fi
    done
  fi
fi
[[ -n "$CLIENT" ]] || { echo "FAIL: no Spotify client found" >&2; exit 1; }
echo "Client: $CLIENT"

BIN="$CLIENT/spotify"
SPA="$CLIENT/Apps/xpui.spa"
BIN_BAK="$CLIENT/spotify.bak"
SPA_BAK="$CLIENT/Apps/xpui.bak"
[[ -f "$BIN" && -f "$SPA" ]] || { echo "FAIL: $BIN or $SPA missing" >&2; exit 1; }

command pkill -9 '[sS]potify' 2>/dev/null || true
# Flatpak binaries need the sandbox runtime; try direct exec, then flatpak run.
bin_version() {
  "$BIN" --version 2>/dev/null | grep -oE '1\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}
if [[ -z "$(bin_version)" && "$CLIENT" == *flatpak* ]] && command -v flatpak >/dev/null 2>&1; then
  bin_version() {
    timeout 60 flatpak run --command=/app/extra/share/spotify/spotify com.spotify.Client --version 2>/dev/null | grep -oE '1\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1
  }
fi
if [[ -n "$(bin_version)" ]]; then echo "Binary runs pre-patch: $(bin_version)"; else echo "NOTE: binary --version failed pre-patch ( continuing )"; fi

# --- T0: normalize to pristine (a previous run may have left a patched tree) ---
if [[ -f "$BIN_BAK" || -f "$SPA_BAK" ]]; then
  bash "$SPOTX" -P "$CLIENT" --uninstall --noninteractive >/dev/null 2>&1
  echo "T0: restored pristine state from leftover backups"
fi

SHA_BIN_BEFORE="$(sha256sum "$BIN" | cut -d' ' -f1)"
SHA_SPA_BEFORE="$(sha256sum "$SPA" | cut -d' ' -f1)"
VER_BEFORE="$(bin_version)"
echo "Version: ${VER_BEFORE:-unknown}"

# --- T1: default run ---
if bash "$SPOTX" -P "$CLIENT" --noninteractive -f >/tmp/opencode/t1.log 2>&1; then ok "T1 default run exit 0"; else bad "T1 default run (see /tmp/opencode/t1.log)"; fi
[[ -f "$BIN_BAK" && -f "$SPA_BAK" ]] && ok "T1 .bak backups exist" || bad "T1 .bak backups missing"

# --- T2: markers + key patches present ---
TMPD="$(mktemp -d)"; python3 -c "import zipfile; zipfile.ZipFile('$SPA').extractall('$TMPD')" 2>/dev/null
T2JS="$TMPD/xpui.js"; [[ -f "$T2JS" ]] || T2JS="$TMPD/xpui-snapshot.js"
if grep -q "SpotX-Linux was here" "$T2JS" 2>/dev/null; then ok "T2 marker present ($T2JS)"; else bad "T2 marker missing"; fi
if grep -q "adsEnabled:!1" "$T2JS" 2>/dev/null; then ok "T2 adsEnabled patched"; else bad "T2 adsEnabled not patched"; fi
if grep -q "allSponsorships" "$T2JS" 2>/dev/null; then bad "T2 allSponsorships still present"; else ok "T2 allSponsorships removed"; fi
if grep -q "sentry.io" "$T2JS" 2>/dev/null; then bad "T2 sentry.io still present"; else ok "T2 sentry.io blocked"; fi
N_TRUE="$(grep -o '",default:true}' "$T2JS" 2>/dev/null | wc -l)"
if [[ "$N_TRUE" -gt 10 ]]; then ok "T2 $N_TRUE enabled-exp flags true"; else bad "T2 only $N_TRUE enabled-exp flags"; fi
N_FALSE="$(grep -o '",default:false}' "$T2JS" 2>/dev/null | wc -l)"
if [[ "$N_FALSE" -gt 10 ]]; then ok "T2 $N_FALSE disabled-exp flags false"; else bad "T2 only $N_FALSE disabled-exp flags"; fi
python3 -c "import zipfile; zipfile.ZipFile('$SPA').testzip()" 2>/dev/null \
  && ok "T2 repacked spa is valid zip" || bad "T2 repacked spa corrupt"
rm -rf "$TMPD"

# --- T3: idempotency (no -f => refuse) ---
if bash "$SPOTX" -P "$CLIENT" --noninteractive >/tmp/opencode/t3.log 2>&1; then ok "T3 second run exit 0 (already-installed path)"; else bad "T3 second run failed"; fi

# --- T4: flag matrix (premium + noexp + dev + hide + lyrics) ---
if bash "$SPOTX" -P "$CLIENT" --noninteractive -f -p -e -d -h -l >/tmp/opencode/t4.log 2>&1; then ok "T4 flag matrix exit 0"; else bad "T4 flag matrix (see /tmp/opencode/t4.log)"; fi
# T4b: -h inserted the podcast/audiobook filter into the patched tree
TMPD4="$(mktemp -d)"; python3 -c "import zipfile; zipfile.ZipFile('$SPA').extractall('$TMPD4')" 2>/dev/null
T4JS="$TMPD4/xpui.js"; [[ -f "$T4JS" ]] || T4JS="$TMPD4/xpui-snapshot.js"
if grep -q "sectionItems.items.filter" "$T4JS" 2>/dev/null; then ok "T4b podcast filter inserted by -h"; else bad "T4b podcast filter missing after -h"; fi
rm -rf "$TMPD4"

# --- T5: binary still runs post-patch ---
if [[ -n "$(bin_version)" ]]; then ok "T5 binary runs post-patch ($(bin_version))"; else bad "T5 binary broken post-patch"; fi

# --- T6: uninstall restores byte-identical originals ---
if bash "$SPOTX" -P "$CLIENT" --uninstall --noninteractive >/tmp/opencode/t6.log 2>&1; then ok "T6 uninstall exit 0"; else bad "T6 uninstall failed"; fi
[[ "$(sha256sum "$BIN" | cut -d' ' -f1)" == "$SHA_BIN_BEFORE" ]] && ok "T6 binary byte-identical" || bad "T6 binary differs after uninstall"
[[ "$(sha256sum "$SPA" | cut -d' ' -f1)" == "$SHA_SPA_BEFORE" ]] && ok "T6 xpui.spa byte-identical" || bad "T6 xpui.spa differs after uninstall"
[[ ! -f "$BIN_BAK" && ! -f "$SPA_BAK" ]] && ok "T6 .bak cleaned" || bad "T6 .bak leftovers"

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
