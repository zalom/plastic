#!/bin/sh
set -eu

channel="${1:-latest}"
repo="https://github.com/zalom/plastic"
share="${PLASTIC_SHARE:-$HOME/.local/share/plastic}"
bin="${PLASTIC_BIN:-$HOME/.local/bin}"

command -v ruby >/dev/null || { echo "plastic needs Ruby 3.3 or later, and no ruby is on the PATH" >&2; exit 1; }

if [ -z "${PLASTIC_ARCHIVE_URL:-}" ]; then
  tags=$(curl -fsSL "https://api.github.com/repos/zalom/plastic/releases?per_page=100" |
    grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
  case "$channel" in
    latest) tag=$(echo "$tags" | grep -v -- '-' | head -1) ;;
    alpha | beta) tag=$(echo "$tags" | grep -- "-$channel" | head -1) ;;
    *) echo "usage: install.sh [latest|beta|alpha]" >&2; exit 2 ;;
  esac
  [ -n "$tag" ] || { echo "no $channel release of plastic was found" >&2; exit 1; }
  PLASTIC_ARCHIVE_URL="$repo/releases/download/$tag/plastic.tgz"
fi

archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
curl -fsSL "$PLASTIC_ARCHIVE_URL" -o "$archive"

rm -rf "$share.new"
mkdir -p "$share.new" "$bin"
tar -xzf "$archive" -C "$share.new" --strip-components=1
rm -rf "$share"
mv "$share.new" "$share"
ln -sf "$share/bin/plastic" "$bin/plastic"

echo "plastic is installed at $bin/plastic"
echo "next: plastic install"
