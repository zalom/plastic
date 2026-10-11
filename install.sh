#!/bin/sh
# Installs Plastic from a GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
set -eu

channel="${PLASTIC_CHANNEL:-stable}"
version="${PLASTIC_VERSION:-}"
local_release="${PLASTIC_LOCAL_RELEASE:-}"
share="${PLASTIC_SHARE:-$HOME/.local/share/plastic}"
bin="${PLASTIC_BIN:-$HOME/.local/bin}"
api="https://api.github.com/repos/zalom/plastic/releases?per_page=50"
download="https://github.com/zalom/plastic/releases/download"
files="plastic.tgz plastic.tgz.sha256 plastic.manifest.json"
dry_run=false

# The Ruby each platform runs, pinned by address, SHA-256 and size. One line:
# platform, folder key, Ruby version, bytes, SHA-256, folder in the archive, address.
ruby_pins='
arm64-darwin 4.0.7-jdx-2 4.0.7 37382165 6ad0acc5b0c437a2514679ff9a0f925e8b66ad4e96357e9ae2764b622f5d88d4 ruby-4.0.7 https://github.com/jdx/ruby/releases/download/4.0.7-2/ruby-4.0.7.macos.tar.gz
x86_64-darwin 4.0.7-homebrew-0 4.0.7 12241978 57bebadc864405cbd39743e32eef741f4b75c0ba121f5cd9296ab84994b9f83b portable-ruby/4.0.7 https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:57bebadc864405cbd39743e32eef741f4b75c0ba121f5cd9296ab84994b9f83b
x86_64-linux 4.0.7-jdx-2 4.0.7 98842474 659c4c80138145f3be439b3e4275b616cc87022e9488b823d708ab75a77558a9 ruby-4.0.7 https://github.com/jdx/ruby/releases/download/4.0.7-2/ruby-4.0.7.x86_64_linux.tar.gz
aarch64-linux 4.0.7-jdx-2 4.0.7 96845779 ed4a403f5cd7eb5941cb96e52e4382eaa81660715e4ce7c9c5dbb4bf77fcde37 ruby-4.0.7 https://github.com/jdx/ruby/releases/download/4.0.7-2/ruby-4.0.7.arm64_linux.tar.gz
'

say() { printf '%s\n' "$*"; }
fail() { printf 'plastic: %s\n' "$*" >&2; exit 1; }

for argument in "$@"; do
  case "$argument" in
    --dry-run) dry_run=true ;;
    *) fail "unknown option $argument" ;;
  esac
done

[ -z "${PLASTIC_ARCHIVE_URL:-}" ] || fail "PLASTIC_ARCHIVE_URL is not read: install.sh downloads only official releases over HTTPS. For development, set PLASTIC_LOCAL_RELEASE to a directory holding $files."

case "$channel" in
  stable) feed_channel=latest ;;
  beta | alpha) feed_channel="$channel" ;;
  *) fail "PLASTIC_CHANNEL must be stable, beta or alpha, not $channel" ;;
esac

missing=false
need() {
  printf 'plastic needs %s.\n  macOS: %s\n  Linux: %s\n' "$1" "$2" "$3" >&2
  missing=true
}

command -v curl >/dev/null 2>&1 || need "curl" "curl ships with macOS; run xcode-select --install to restore it" "install curl with your distribution's package manager"
command -v tar >/dev/null 2>&1 || need "tar" "tar ships with macOS; run xcode-select --install to restore it" "install tar with your distribution's package manager"
if command -v sha256sum >/dev/null 2>&1; then
  digest="sha256sum -c"
elif command -v shasum >/dev/null 2>&1; then
  digest="shasum -a 256 -c"
else
  need "sha256sum or shasum" "shasum ships with macOS; run xcode-select --install to restore it" "install coreutils, which provides sha256sum, with your distribution's package manager"
fi
[ "$missing" = false ] || exit 1

tmp=$(mktemp -d "${TMPDIR:-/tmp}/plastic-install.XXXXXX")
stage=""
trap 'chmod -R u+w "$tmp"; rm -rf "$tmp"; [ -z "$stage" ] || { chmod -R u+w "$stage"; rm -rf "$stage"; }' EXIT
trap 'exit 1' INT TERM

fetch() { curl --proto '=https' --tlsv1.2 -fsSL "$1" -o "$2"; }

detect_platform() {
  system=$(uname -s)
  machine=$(uname -m)
  case "$system $machine" in
    "Darwin arm64") platform=arm64-darwin ;;
    "Darwin x86_64")
      platform=x86_64-darwin
      [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" != 1 ] || platform=arm64-darwin ;;
    "Linux x86_64") platform=x86_64-linux ;;
    "Linux aarch64" | "Linux arm64") platform=aarch64-linux ;;
    *) fail "no Ruby build exists for $system $machine. Plastic runs on macOS and on Linux with glibc 2.29 or later; on Windows, install it inside WSL." ;;
  esac
  case "$platform" in
    *-linux)
      if (ldd --version 2>&1 || true) | grep -qi musl; then
        fail "Alpine and other musl systems are not supported: Plastic's Ruby needs glibc 2.29 or later."
      fi ;;
  esac
}

check_entries() {
  names=$(tar -tzf "$1") || fail "$2 cannot be read"
  printf '%s\n' "$names" | while IFS= read -r name; do
    case "$name" in
      /* | .. | ../* | */.. | */../*) exit 1 ;;
    esac
  done || fail "$2 holds an unsafe entry: an absolute path or a parent directory"
  kinds=$(tar -tvzf "$1" | cut -c1 | sort -u | tr -d '\n')
  case "$kinds" in
    *[!d-]*) fail "$2 holds an unsafe entry: a link or a special file" ;;
  esac
}

download_ruby() {
  case "$ruby_url" in
    https://ghcr.io/*) curl --proto '=https' --tlsv1.2 -fsSL -H 'Authorization: Bearer QQ==' "$ruby_url" -o "$1" ;;
    *) fetch "$ruby_url" "$1" ;;
  esac || fail "could not download Ruby $ruby_version from $ruby_url"
  bytes=$(wc -c < "$1" | tr -d ' ')
  [ "$bytes" = "$ruby_size" ] || fail "the Ruby archive has $bytes bytes, not the pinned $ruby_size"
  printf '%s  ruby.tar.gz\n' "$ruby_sha" > "$tmp/ruby.tar.gz.sha256"
  (cd "$tmp" && $digest ruby.tar.gz.sha256 >/dev/null 2>&1) || fail "the Ruby archive does not match its pinned SHA-256"
  check_entries "$1" "the Ruby archive"
}

install_ruby() {
  say "downloading Ruby $ruby_version for $platform"
  download_ruby "$tmp/ruby.tar.gz"
  mkdir -p "$rubies"
  stage=$(mktemp -d "$rubies/.stage-XXXXXX")
  tar -xzf "$tmp/ruby.tar.gz" -C "$stage" || fail "the Ruby archive cannot be unpacked"
  started=$("$stage/$ruby_root/bin/ruby" --disable-gems -rrbconfig -e 'require "openssl"; require "zlib"; require "psych"; print RUBY_VERSION' 2>&1) || true
  [ "$started" = "$ruby_version" ] || fail "the downloaded Ruby does not start: $started"
  printf '%s\n' "$ruby_sha" > "$stage/$ruby_root/.plastic-ruby"
  mv "$stage/$ruby_root" "$rubies/$ruby_key"
  chmod -R a-w "$rubies/$ruby_key"
  chmod -R u+w "$stage"
  rm -rf "$stage"
  stage=""
}

marked() { [ "$(cat "$1/$ruby_key/.plastic-ruby" 2>/dev/null || true)" = "$ruby_sha" ]; }

choose_ruby() {
  detect_platform
  pin=$(printf '%s\n' "$ruby_pins" | grep "^$platform ") || fail "install.sh pins no Ruby for $platform"
  read -r _ ruby_key ruby_version ruby_size ruby_sha ruby_root ruby_url <<EOF
$pin
EOF
  rubies="$share/rubies"
  if ! marked "$rubies"; then
    [ ! -e "$rubies/$ruby_key" ] || fail "$rubies/$ruby_key holds another Ruby; remove that folder and run this again"
    [ "$dry_run" = false ] || rubies="$tmp/rubies"
    install_ruby
  fi
  ruby="$rubies/$ruby_key/bin/ruby"
}

if [ -n "${PLASTIC_RUBY:-}" ]; then
  ruby="$PLASTIC_RUBY"
  say "development mode: running the installer with PLASTIC_RUBY=$ruby"
else
  choose_ruby
fi

newest_version() {
  feed=$(curl --proto '=https' --tlsv1.2 -fsSL -H 'Accept: application/vnd.github+json' "$api") ||
    fail "could not read the release list from GitHub"
  printf '%s' "$feed" > "$tmp/releases.json"
  "$ruby" --disable-gems -rjson -rrubygems/version - "$tmp/releases.json" "$feed_channel" <<'RUBY'
names = %w[plastic.tgz plastic.tgz.sha256 plastic.manifest.json]
versions = JSON.parse(File.read(ARGV[0])).filter_map do |release|
  next unless (names - release.fetch("assets").map { |asset| asset["name"] }).empty?
  version = release.fetch("tag_name").delete_prefix("v")
  version if (version[/-(alpha|beta)\b/, 1] || "latest") == ARGV[1]
end
print versions.max_by { |version| Gem::Version.new(version) }
RUBY
}

manifest_version() {
  "$ruby" --disable-gems -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("release", "version")' "$tmp/plastic.manifest.json"
}

[ "$dry_run" = false ] || files="plastic.manifest.json"
if [ -n "$local_release" ]; then
  say "development mode: reading the release from $local_release; this claims no release trust"
  for name in $files; do
    [ -f "$local_release/$name" ] || fail "$local_release has no $name"
    cp "$local_release/$name" "$tmp/$name"
  done
  [ -n "$version" ] || version=$(manifest_version)
else
  [ -n "$version" ] || version=$(newest_version)
  [ -n "$version" ] || fail "no $channel release carries $files. Choose another channel, such as PLASTIC_CHANNEL=alpha."
  for name in $files; do
    fetch "$download/v$version/$name" "$tmp/$name" || fail "could not download $name of v$version"
  done
fi

if [ "$dry_run" = true ]; then
  say "would install Plastic $(manifest_version) under $share"
  say "would run it with $ruby"
  say "would link $bin/plastic"
  exit 0
fi

(cd "$tmp" && $digest plastic.tgz.sha256 >/dev/null 2>&1) || fail "plastic.tgz does not match its published checksum"

check_entries "$tmp/plastic.tgz" plastic.tgz
plastic_home="${PLASTIC_HOME:-$HOME/.plastic}"
next_step="plastic init"
[ ! -f "$plastic_home/VERSION" ] || next_step="plastic version"
mkdir "$tmp/boot"
tar -xzf "$tmp/plastic.tgz" -C "$tmp/boot" package/scripts/install-release package/scripts/lib/installer_release.rb package/scripts/lib/installer_release
"$ruby" --disable-gems -rrbconfig "$tmp/boot/package/scripts/install-release" --directory "$tmp" --version "$version" --home "$share" \
  --bin "$bin" --plastic-home "$plastic_home" --user-home "$HOME" || exit 1

say "Plastic $version is active."
case ":$PATH:" in
  *":$bin:"*) ;;
  *) say "$bin is not on your PATH. Add this line to your shell profile:"
     say "  export PATH=\"$bin:\$PATH\"" ;;
esac
say "next: $next_step"
