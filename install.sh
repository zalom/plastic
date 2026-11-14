#!/bin/sh
# Installs Plastic from a GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
set -eu

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

case "$version" in
  *-alpha* | *-beta*) fail "install.sh installs the stable release only. To follow an alpha or beta release, install the stable release, then run: plastic update" ;;
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
command -v git >/dev/null 2>&1 || need "git" "run xcode-select --install, or brew install git" "install git with your distribution's package manager"

ruby=$(command -v "${PLASTIC_RUBY:-ruby}" 2>/dev/null || true)
ruby_hint_mac="brew install ruby, then add its bin folder to PATH: export PATH=\"\$(brew --prefix ruby)/bin:\$PATH\""
ruby_hint_linux="install Ruby 4.0 or later with your distribution's package manager, or with a Ruby version manager"
if [ -z "$ruby" ]; then
  need "Ruby 4.0 or later" "$ruby_hint_mac" "$ruby_hint_linux"
else
  banner=$("$ruby" --version 2>/dev/null || true)
  found=${banner#ruby }
  found=${found%% *}
  found=${found%%p[0-9]*}
  major=${found%%.*}
  case "$major" in
    '' | *[!0-9]*) need "Ruby 4.0 or later; $ruby gave no version" "$ruby_hint_mac" "$ruby_hint_linux" ;;
    *) [ "$major" -ge 4 ] || need "Ruby 4.0 or later; found $found" "$ruby_hint_mac" "$ruby_hint_linux" ;;
  esac
fi
[ "$missing" = false ] || exit 1

tmp=$(mktemp -d "${TMPDIR:-/tmp}/plastic-install.XXXXXX")
trap 'chmod -R u+w "$tmp"; rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

fetch() { curl --proto '=https' --tlsv1.2 -fsSL "$1" -o "$2"; }

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

newest_version() {
  feed=$(curl --proto '=https' --tlsv1.2 -fsSL -H 'Accept: application/vnd.github+json' "$api") ||
    fail "could not read the release list from GitHub"
  printf '%s' "$feed" > "$tmp/releases.json"
  "$ruby" --disable-gems -rjson -rrubygems/version - "$tmp/releases.json" <<'RUBY'
names = %w[plastic.tgz plastic.tgz.sha256 plastic.manifest.json]
versions = JSON.parse(File.read(ARGV[0])).filter_map do |release|
  next unless (names - release.fetch("assets").map { |asset| asset["name"] }).empty?
  version = release.fetch("tag_name").delete_prefix("v")
  version unless version.match?(/-(alpha|beta)\b/)
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
  [ -n "$version" ] || fail "no stable release carries $files."
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
tar -xzf "$tmp/plastic.tgz" -C "$tmp/boot" package/scripts/install-release package/scripts/lib/installer_release.rb package/scripts/lib/installer_release package/lib/plastic/installations/launcher_link.rb package/lib/plastic/installations/release_files.rb
PLASTIC_RUBY="$ruby" "$ruby" --disable-gems -rrbconfig "$tmp/boot/package/scripts/install-release" --directory "$tmp" --version "$version" --home "$share" \
  --bin "$bin" --plastic-home "$plastic_home" --user-home "$HOME" || exit 1

say "Plastic $version is active."
case ":$PATH:" in
  *":$bin:"*) ;;
  *) say "$bin is not on your PATH. Add this line to your shell profile:"
     say "  export PATH=\"$bin:\$PATH\"" ;;
esac
say "next: $next_step"
