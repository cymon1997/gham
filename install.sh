#!/usr/bin/env bash
# Install or update gham.
#
#   curl -fsSL https://raw.githubusercontent.com/cymon1997/gham/main/install.sh | bash
#   ./install.sh            # from a local clone
#
# Environment:
#   GHAM_HOME   where gham lives (default: ~/.gham)
#   GHAM_REF    git ref to install when downloading (default: main)
set -euo pipefail

GHAM_HOME="${GHAM_HOME:-$HOME/.gham}"
GHAM_REF="${GHAM_REF:-main}"
RAW="https://raw.githubusercontent.com/cymon1997/gham/$GHAM_REF/gham"

mkdir -p "$GHAM_HOME/bin" "$GHAM_HOME/accounts"

src_dir=""
# Piped through `curl | bash` there is no script file, so always download.
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -n "$src_dir" && -f "$src_dir/gham" && -f "$src_dir/install.sh" ]]; then
  cp "$src_dir/gham" "$GHAM_HOME/bin/gham.new"
  echo "Installing gham from $src_dir"
else
  command -v curl >/dev/null || { echo "install.sh: curl is required" >&2; exit 1; }
  curl -fsSL "$RAW" -o "$GHAM_HOME/bin/gham.new"
  echo "Downloaded gham ($GHAM_REF)"
fi
chmod 755 "$GHAM_HOME/bin/gham.new"
mv "$GHAM_HOME/bin/gham.new" "$GHAM_HOME/bin/gham"
ln -sfn gham "$GHAM_HOME/bin/git"
ln -sfn gham "$GHAM_HOME/bin/gh"

echo "Installed $("$GHAM_HOME/bin/gham" version) to $GHAM_HOME/bin"

rc=""
case "$(basename "${SHELL:-}")" in
  zsh) rc="$HOME/.zshrc" ;;
  bash) rc="$HOME/.bashrc" ;;
esac

if [[ -n "$rc" ]] && grep -q 'gham init' "$rc" 2>/dev/null; then
  echo "Shell integration already present in $rc."
else
  cat <<EOF

Next, enable shell integration by adding this line to ${rc:-your shell rc}:

  eval "\$($GHAM_HOME/bin/gham init)"

then open a new shell and register your first account:

  gham add personal --import        # reuse your current gh login and git identity
  gham add work                     # or log a new account in (gh login + new SSH key)
  gham bind ~/Codes/work work       # then use it automatically under a directory
EOF
fi
