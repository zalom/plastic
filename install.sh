#!/bin/sh
set -eu

archive_url="${PLASTIC_ARCHIVE_URL:-https://github.com/zalom/plastic/releases/latest/download/plastic.tgz}"
share="${PLASTIC_SHARE:-$HOME/.local/share/plastic}"
bin="${PLASTIC_BIN:-$HOME/.local/bin}"

command -v ruby >/dev/null || { echo "plastic needs Ruby 3.3 or later, and no ruby is on the PATH" >&2; exit 1; }

archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
curl -fsSL "$archive_url" -o "$archive" || { echo "no stable release of plastic carries plastic.tgz yet" >&2; exit 1; }

rm -rf "$share.new"
mkdir -p "$share.new" "$bin"
tar -xzf "$archive" -C "$share.new" --strip-components=1
rm -rf "$share"
mv "$share.new" "$share"
ln -sf "$share/bin/plastic" "$bin/plastic"

echo "plastic is installed at $bin/plastic"
echo "next: plastic install"
