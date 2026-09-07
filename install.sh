#!/usr/bin/env bash
#
# Simple installer for spotx-linux.
# Usage:
#   ./install.sh                  # install to /usr/local/bin/spotx
#   ./install.sh --prefix ~/.local # user install, no sudo
#   ./install.sh --uninstall       # remove installed binary
#
set -u

PREFIX="/usr/local"
UNINSTALL=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; [[ -n "$PREFIX" ]] || { echo "--prefix needs a value" >&2; exit 1; }; shift 2 ;;
    --uninstall) UNINSTALL='true'; shift ;;
    --help|-h) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
done

# Locate spotx.sh next to this installer (works from repo root or linux/).
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
SRC="$HERE/spotx.sh"
[[ -f "$SRC" ]] || SRC="$HERE/linux/spotx.sh"
[[ -f "$SRC" ]] || { echo "spotx.sh not found next to install.sh" >&2; exit 1; }
INC="$HERE/generated_exp.inc"
[[ -f "$INC" ]] || INC="$HERE/tools/generated_exp.inc"
[[ -f "$INC" ]] || INC="$HERE/linux/tools/generated_exp.inc"
[[ -f "$INC" ]] || INC=""

DEST="$PREFIX/bin/spotx"
SHAREDEST="$PREFIX/share/spotx-linux/generated_exp.inc"

if [[ -n "$UNINSTALL" ]]; then
  if [[ -f "$DEST" ]]; then
    if [[ -w "$DEST" ]]; then rm -f "$DEST";
    else sudo rm -f "$DEST"; fi
    echo "Removed $DEST"
  else echo "Not installed: $DEST"; fi
  if [[ -f "$SHAREDEST" ]]; then
    if [[ -w "$SHAREDEST" ]]; then rm -f "$SHAREDEST";
    else sudo rm -f "$SHAREDEST"; fi
    echo "Removed $SHAREDEST"
  fi
  exit 0
fi

bash -n "$SRC" || { echo "spotx.sh failed syntax check" >&2; exit 1; }

mkdir -p "$PREFIX/bin" "$PREFIX/share/spotx-linux" 2>/dev/null \
  || sudo mkdir -p "$PREFIX/bin" "$PREFIX/share/spotx-linux"
if [[ -w "$PREFIX/bin" ]]; then
  install -m755 "$SRC" "$DEST"
else
  sudo install -m755 "$SRC" "$DEST"
fi
if [[ -n "$INC" ]]; then
  if [[ -w "$PREFIX/share/spotx-linux" ]]; then
    install -m644 "$INC" "$SHAREDEST"
  else
    sudo install -m644 "$INC" "$SHAREDEST"
  fi
  echo "Installed flags db to $SHAREDEST"
else echo "Note: generated_exp.inc not found — installing binary only (embedded patches)."; fi

echo "Installed to $DEST"
echo "Run: spotx --help"
command -v perl >/dev/null || echo "Note: 'perl' missing — install it to run spotx."
command -v curl >/dev/null || echo "Note: 'curl' missing — install it to run spotx."
if ! command -v unzip >/dev/null || ! command -v zip >/dev/null; then
  command -v python3 >/dev/null || echo "Note: need 'unzip+zip' or 'python3' for xpui.spa handling."
fi
