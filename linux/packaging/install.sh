#!/usr/bin/env sh
# Registers an already-extracted Sozo tarball with the desktop session.
#
# The tarball is a raw Flutter bundle: it runs if you invoke ./soplay by hand,
# but the session knows nothing about it — no launcher, no icon, and no owner
# for the sozo:// scheme the app's own deeplink handling expects. This script
# closes that gap without asking for root, so wherever the user unpacked the
# tarball is where the app stays.
#
#   ./install.sh            register
#   ./install.sh --uninstall  undo it
set -eu

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
DESKTOP="$DATA/applications/sozo.desktop"
ICON="$DATA/icons/hicolor/256x256/apps/sozo.png"

MESSAGE="Done. Launch Sozo from the applications menu; sozo:// links now open it."

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$DESKTOP" "$ICON"

  # xdg-mime can set a default but has no verb to clear one, so the association
  # written below has to come back out of mimeapps.list by hand. Left behind, it
  # points x-scheme-handler/sozo at a .desktop file that no longer exists, and a
  # browser following a sozo:// link then fails instead of falling through to
  # whatever else the user has. Both paths are checked because the spec moved
  # the file to $XDG_CONFIG_HOME while older xdg-utils still write the copy under
  # the data directory. Only our own entry is dropped, never someone else's
  # handler for the same scheme.
  for list in "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list" \
              "$DATA/applications/mimeapps.list"; do
    [ -f "$list" ] || continue
    if sed '/^x-scheme-handler\/sozo=sozo\.desktop;\{0,1\}$/d' "$list" > "$list.sozo-tmp" 2>/dev/null; then
      mv "$list.sozo-tmp" "$list" || rm -f "$list.sozo-tmp"
    else
      rm -f "$list.sozo-tmp"
    fi
  done

  MESSAGE="Removed the launcher, the icon and the sozo:// association. The extracted app itself is untouched."
else
  [ -x "$APP_DIR/soplay" ] || { echo "soplay not found next to $0 — run this from inside the extracted tarball." >&2; exit 1; }

  mkdir -p "$(dirname "$DESKTOP")" "$(dirname "$ICON")"
  ln -sf "$APP_DIR/sozo.png" "$ICON"

  # The icon is a symlink but the .desktop file is rewritten, because its Exec
  # line has to name the binary by absolute path. A graphical session does not
  # read the shell profile that puts ~/.local/bin on PATH, so a bare `soplay`
  # launches from a terminal and fails from the applications menu — the exact
  # split that is hardest to diagnose afterwards.
  #
  # The path comes in as an awk variable and goes out quoted, because it is
  # wherever the user happened to unpack the tarball: "|" and "&" are syntax to
  # sed's replacement text, and a space is an argument separator to the Exec
  # line, so "~/My Apps/Sozo" would have produced a launcher that silently ran
  # a program called "/home/you/My".
  awk -v exe="$APP_DIR/soplay" '
    /^Exec=soplay / { print "Exec=\"" exe "\"" substr($0, length("Exec=soplay") + 1); next }
    { print }
  ' "$APP_DIR/sozo.desktop" > "$DESKTOP"
  chmod 644 "$DESKTOP"

  # The MimeType line only advertises that Sozo can handle the scheme. Claiming
  # it as the default is a separate, explicit step, and it is the one a browser
  # actually consults.
  xdg-mime default sozo.desktop x-scheme-handler/sozo 2>/dev/null || true
fi

# Both are best-effort: they are absent on minimal systems, and a stale cache
# costs an icon or a mis-routed link, never a broken install.
update-desktop-database "$DATA/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$DATA/icons/hicolor" 2>/dev/null || true

echo "$MESSAGE"
