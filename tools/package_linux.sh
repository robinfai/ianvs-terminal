#!/usr/bin/env bash
# Build relocatable and Debian Linux packages. Never embeds a user profile/keyring.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FLUTTER=${FLUTTER:-flutter}
OUTPUT=${OUTPUT_DIR:-"$ROOT/build/linux-packages"}
case "$(uname -m)" in
  x86_64) FLUTTER_ARCH=x64; DEB_ARCH=amd64 ;;
  aarch64) FLUTTER_ARCH=arm64; DEB_ARCH=arm64 ;;
  *) printf 'Unsupported host architecture\n' >&2; exit 2 ;;
esac
VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' "$ROOT/example/pubspec.yaml" | head -1)
COMMIT=$(git -C "$ROOT" rev-parse --short=12 HEAD)
NAME="trail-${VERSION}-linux-${FLUTTER_ARCH}"
if [[ ${SKIP_BUILD:-0} != 1 ]]; then
  (cd "$ROOT/example" && "$FLUTTER" build linux --release)
fi
BUNDLE="$ROOT/example/build/linux/$FLUTTER_ARCH/release/bundle"
test -x "$BUNDLE/trail"
test -f "$BUNDLE/lib/libianvs_core.so"
test -f "$BUNDLE/lib/libapp.so"
python3 "$ROOT/tools/verify_linux_font_bundle.py" "$BUNDLE"
mkdir -p "$OUTPUT"
STAGE=$(mktemp -d "$OUTPUT/.stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME"
cp -a "$BUNDLE/." "$STAGE/$NAME/"
cp "$ROOT/example/linux/assets/work.ianvs.trail.desktop" "$STAGE/$NAME/"
cp "$ROOT/example/linux/assets/work.ianvs.trail.png" "$STAGE/$NAME/"
cat > "$STAGE/$NAME/README.txt" <<INFO
Trail (Ianvs Terminal) $VERSION, source $COMMIT
Run ./trail from this extracted directory. Keep data/ and lib/ beside it.
Runtime: GNU/Linux, GTK 3, libsecret and an unlocked Secret Service (e.g.
GNOME Keyring or compatible KWallet), OpenGL/Mesa, and a POSIX shell.
The package contains no user settings, recordings, SSH keys or keyring data.
Configuration, encrypted credentials and recordings use your XDG data directory.
Linux keyrings do not automatically synchronize with Apple iCloud Keychain.
INFO
printf '{"version":"%s","commit":"%s","architecture":"%s"}\n' "$VERSION" "$(git -C "$ROOT" rev-parse HEAD)" "$DEB_ARCH" > "$STAGE/$NAME/build-info.json"
tar -C "$STAGE" -czf "$OUTPUT/$NAME.tar.gz" "$NAME"
DEB="$STAGE/deb"
mkdir -p "$DEB/DEBIAN" "$DEB/opt/trail" "$DEB/usr/bin" "$DEB/usr/share/applications" "$DEB/usr/share/icons/hicolor/256x256/apps"
cp -a "$STAGE/$NAME/." "$DEB/opt/trail/"
ln -s /opt/trail/trail "$DEB/usr/bin/trail"
cp "$ROOT/example/linux/assets/work.ianvs.trail.desktop" "$DEB/usr/share/applications/"
cp "$ROOT/example/linux/assets/work.ianvs.trail.png" "$DEB/usr/share/icons/hicolor/256x256/apps/"
# Derive the actual glibc baseline of every ELF in the bundle.
GLIBC=$(find "$BUNDLE" -type f -exec objdump -T {} \; 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | cut -d_ -f2 | sort -V | tail -1)
cat > "$DEB/DEBIAN/control" <<CONTROL
Package: trail
Version: ${VERSION}+git${COMMIT}
Section: utils
Priority: optional
Architecture: $DEB_ARCH
Maintainer: robinfai <robinfai9@gmail.com>
Depends: libc6 (>= ${GLIBC:-2.34}), libstdc++6, libgcc-s1, libgtk-3-0t64 | libgtk-3-0, libsecret-1-0
Recommends: gnome-keyring | kwalletmanager
Installed-Size: $(du -sk "$DEB/opt/trail" | cut -f1)
Homepage: https://github.com/robinfai/ianvs-terminal
Description: Trail terminal emulator
 Native PTY terminal with SSH/SFTP, profiles, panes and session recording.
 Credentials remain encrypted using the desktop Secret Service.
CONTROL
dpkg-deb --root-owner-group --build "$DEB" "$OUTPUT/${NAME}.deb"
(cd "$OUTPUT" && sha256sum "$NAME.tar.gz" "$NAME.deb" > SHA256SUMS)
printf 'Packages and SHA256SUMS: %s\n' "$OUTPUT"
