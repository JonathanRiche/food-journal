#!/usr/bin/env bash
set -euo pipefail

REPO="JonathanRiche/food-journal"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

if [[ -z "${HOME:-}" ]]; then
  echo "HOME is not set." >&2
  exit 1
fi

os_name="$(uname -s)"
arch_name="$(uname -m)"

case "$os_name" in
  Linux) os_tag="linux" ;;
  Darwin) os_tag="macos" ;;
  *)
    echo "Unsupported OS: $os_name" >&2
    exit 1
    ;;
esac

case "$arch_name" in
  x86_64|amd64) arch_tag="x86_64" ;;
  arm64|aarch64) arch_tag="aarch64" ;;
  *)
    echo "Unsupported architecture: $arch_name" >&2
    exit 1
    ;;
esac

if [[ "$os_tag" == "linux" ]]; then
  if [[ "$arch_tag" != "x86_64" ]]; then
    echo "Unsupported Linux architecture: $arch_name" >&2
    exit 1
  fi
  target="${arch_tag}-linux-gnu"
else
  target="${arch_tag}-macos"
fi

api_url="https://api.github.com/repos/${REPO}/releases/latest"
download_url="$(curl -fsSL "$api_url" | awk -v target="$target" -F'"' '$2=="browser_download_url" && $4 ~ target {print $4; exit}')"

if [[ -z "$download_url" ]]; then
  echo "No release asset found for target: $target" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsSL "$download_url" -o "$tmp_dir/food-journal.tar.gz"
tar -xzf "$tmp_dir/food-journal.tar.gz" -C "$tmp_dir"

install -d "$INSTALL_DIR"

if [[ -x "$INSTALL_DIR/food-journal" ]]; then
  action="Updated"
else
  action="Installed"
fi

install -m 755 "$tmp_dir/food-journal" "$INSTALL_DIR/food-journal"

echo "$action food-journal to $INSTALL_DIR/food-journal"

case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    ;;
  *)
    profile="$HOME/.profile"
    if [[ -n "${SHELL:-}" ]]; then
      shell_name="$(basename "$SHELL")"
      case "$shell_name" in
        zsh) profile="$HOME/.zshrc" ;;
        bash) profile="$HOME/.bashrc" ;;
      esac
    fi

    if [[ ! -f "$profile" ]]; then
      touch "$profile"
    fi

    if ! grep -qs "$INSTALL_DIR" "$profile"; then
      {
        echo ""
        echo "export PATH=\"$INSTALL_DIR:\$PATH\""
      } >> "$profile"
      echo "Added $INSTALL_DIR to PATH in $profile"
    fi

    export PATH="$INSTALL_DIR:$PATH"
    ;;
esac

echo ""
reply=""
if [[ -t 0 ]]; then
  read -r -p "Add the agent skill now? [y/N] " reply
elif [[ -r /dev/tty ]]; then
  read -r -p "Add the agent skill now? [y/N] " reply < /dev/tty
fi
case "$reply" in
  y|Y|yes|YES)
    if command -v npx >/dev/null 2>&1; then
      npx skills add https://github.com/JonathanRiche/food-journal --skill food-journal
    else
      echo "npx not found. Install Node.js or run the command later:"
      echo "  npx skills add https://github.com/JonathanRiche/food-journal --skill food-journal"
    fi
    ;;
  *)
    echo "Skipping skill installation."
    ;;
esac
