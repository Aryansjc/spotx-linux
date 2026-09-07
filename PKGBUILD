# Maintainer: you <you@example.com>
pkgname=spotx-linux
pkgver=0.1.0
pkgrel=1
pkgdesc="Universal adblock patcher for the Spotify desktop client on Linux"
arch=('any')
url="https://github.com/<YOU>/<REPO>"
license=('MIT')
depends=('bash' 'perl' 'curl' 'python')
optdepends=(
  'unzip: faster xpui.spa extraction (python3 fallback otherwise)'
  'zip: faster xpui.spa repacking (python3 fallback otherwise)'
  'flatpak: install Spotify via flatpak'
)
# Built from the same directory: spotx.sh, README.md live next to this PKGBUILD.
# For a VCS package from git, switch to the -git style source below.
source=('spotx.sh' 'tools/generated_exp.inc' 'README.md')
sha256sums=('SKIP' 'SKIP' 'SKIP')

package() {
  install -Dm755 spotx.sh "$pkgdir/usr/bin/spotx"
  install -Dm644 tools/generated_exp.inc "$pkgdir/usr/share/spotx-linux/generated_exp.inc"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
}
