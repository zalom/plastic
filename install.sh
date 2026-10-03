#!/bin/sh
set -eu

repo="${PLASTIC_REPO:-zalom/plastic}"
channel="${PLASTIC_CHANNEL:-stable}"
share="${PLASTIC_SHARE:-$HOME/.local/share/plastic}"
bin="${PLASTIC_BIN:-$HOME/.local/bin}"
dry_run=false
[ "${1:-}" = "--dry-run" ] && dry_run=true

command -v ruby >/dev/null || { echo "plastic needs Ruby 4.0 or later, and no ruby is on the PATH" >&2; exit 1; }
command -v curl >/dev/null || { echo "plastic's installer needs curl, and no curl is on the PATH" >&2; exit 1; }

if [ "$dry_run" = true ]; then
  echo "would read release metadata for $repo ($channel)"
  echo "would stage and activate Plastic under $share"
  echo "next: plastic install"
  exit 0
fi

# The newest release on the channel that actually carries plastic.tgz. A release
# with no archive, and a pre-release wearing the Latest badge, both used to send
# this script to a URL that 404s, so it reads the release list rather than
# trusting releases/latest/download.
resolve_archive_url() {
  curl -fsSL -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$repo/releases?per_page=50" |
    ruby -rjson -e '
      channel = ARGV[0]
      releases = JSON.parse($stdin.read)
      wanted = releases.find do |release|
        tag = release["tag_name"].to_s
        on_channel =
          case channel
          when "alpha" then tag.include?("-alpha.")
          when "beta"  then tag.include?("-beta.")
          else !tag.include?("-") && release["prerelease"] != true
          end
        on_channel && release["assets"].to_a.any? { |a| a["name"] == "plastic.tgz" }
      end
      abort if wanted.nil?
      puts wanted["assets"].find { |a| a["name"] == "plastic.tgz" }["browser_download_url"]
    ' "$channel"
}

if [ -n "${PLASTIC_ARCHIVE_URL:-}" ]; then
  archive_url="$PLASTIC_ARCHIVE_URL"
else
  archive_url=$(resolve_archive_url) || {
    echo "no $channel release of plastic carries plastic.tgz yet" >&2
    echo "try another channel: PLASTIC_CHANNEL=alpha sh install.sh" >&2
    exit 1
  }
fi

archive=$(mktemp)
stage="$share.stage.$$"
backup="$share.previous.$$"
trap 'rm -f "$archive"; rm -rf "$stage"' EXIT
curl -fsSL "$archive_url" -o "$archive" || { echo "could not download $archive_url" >&2; exit 1; }

rm -rf "$stage" "$backup"
mkdir -p "$stage" "$bin"
tar -xzf "$archive" -C "$stage" --strip-components=1
[ -x "$stage/bin/plastic" ] || { echo "archive has no executable plastic command" >&2; exit 1; }

if [ -e "$share" ]; then
  mv "$share" "$backup" || { echo "could not preserve the current installation" >&2; exit 1; }
fi
if ! mv "$stage" "$share"; then
  [ ! -e "$backup" ] || mv "$backup" "$share"
  echo "could not activate the new installation; restored the previous installation" >&2
  exit 1
fi
rm -rf "$backup"
ln -sf "$share/bin/plastic" "$bin/plastic"

echo "plastic is installed at $bin/plastic"
echo "next: plastic install"
