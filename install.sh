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

mise_steps="install mise with curl https://mise.run | sh, then run mise use --global ruby@4.0"
if command -v ruby >/dev/null 2>&1; then
  ruby_version=$(ruby --disable-gems -e 'print RUBY_VERSION' 2>/dev/null || true)
  ruby_major="${ruby_version%%.*}"
  case "$ruby_major" in '' | *[!0-9]*) ruby_major=0 ;; esac
  [ "$ruby_major" -ge 4 ] || need "Ruby 4.0 or later (found Ruby $ruby_version)" "$mise_steps" "$mise_steps"
else
  need "Ruby 4.0 or later" "$mise_steps" "$mise_steps"
fi
command -v bundle >/dev/null 2>&1 || need "Bundler" "Bundler ships with Ruby 4.0; run gem install bundler" "Bundler ships with Ruby 4.0; run gem install bundler"
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
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

fetch() { curl --proto '=https' --tlsv1.2 -fsSL "$1" -o "$2"; }

newest_version() {
  feed=$(curl --proto '=https' --tlsv1.2 -fsSL -H 'Accept: application/vnd.github+json' "$api") ||
    fail "could not read the release list from GitHub"
  printf '%s' "$feed" | ruby --disable-gems -rjson -rrubygems/version -e '
    names = %w[plastic.tgz plastic.tgz.sha256 plastic.manifest.json]
    versions = JSON.parse($stdin.read).filter_map do |release|
      next unless (names - release.fetch("assets").map { |asset| asset["name"] }).empty?
      version = release.fetch("tag_name").delete_prefix("v")
      version if (version[/-(alpha|beta)\b/, 1] || "latest") == ARGV[0]
    end
    print versions.max_by { |version| Gem::Version.new(version) }
  ' "$feed_channel"
}

inspect_archive() {
  names=$(tar -tzf "$tmp/plastic.tgz") || fail "plastic.tgz cannot be read"
  printf '%s\n' "$names" | while IFS= read -r name; do
    case "$name" in
      /* | .. | ../* | */.. | */../*) exit 1 ;;
    esac
  done || fail "plastic.tgz holds an unsafe entry: an absolute path or a parent directory"
  kinds=$(tar -tvzf "$tmp/plastic.tgz" | cut -c1 | sort -u | tr -d '\n')
  case "$kinds" in
    *[!d-]*) fail "plastic.tgz holds an unsafe entry: a link or a special file" ;;
  esac
}

manifest_version() {
  ruby --disable-gems -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("release", "version")' "$tmp/plastic.manifest.json"
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
  [ -n "$version" ] || fail "no $channel release carries $files. Choose another channel, such as PLASTIC_CHANNEL=alpha, or install with npm."
  for name in $files; do
    fetch "$download/v$version/$name" "$tmp/$name" || fail "could not download $name of v$version"
  done
fi

if [ "$dry_run" = true ]; then
  say "would install Plastic $(manifest_version) under $share"
  say "would link $bin/plastic"
  exit 0
fi

(cd "$tmp" && $digest plastic.tgz.sha256 >/dev/null 2>&1) || fail "plastic.tgz does not match its published checksum"

inspect_archive
plastic_home="${PLASTIC_HOME:-$HOME/.plastic}"
next_step="plastic install"
[ ! -f "$plastic_home/VERSION" ] || next_step="plastic version"
mkdir "$tmp/boot"
tar -xzf "$tmp/plastic.tgz" -C "$tmp/boot" package/scripts/install-release package/scripts/lib/installer_release.rb package/scripts/lib/installer_release
ruby --disable-gems "$tmp/boot/package/scripts/install-release" --directory "$tmp" --version "$version" --home "$share" \
  --bin "$bin" --plastic-home "$plastic_home" --user-home "$HOME" || exit 1

say "Plastic $version is active."
case ":$PATH:" in
  *":$bin:"*) ;;
  *) say "$bin is not on your PATH. Add this line to your shell profile:"
     say "  export PATH=\"$bin:\$PATH\"" ;;
esac
say "next: $next_step"
