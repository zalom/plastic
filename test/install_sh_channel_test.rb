# frozen_string_literal: true

require_relative "support/install_sh_helper"

class InstallShChannelTest < Minitest::Test
  include InstallShHelper

  ASSETS = '[{"name": "plastic.tgz"}, {"name": "plastic.tgz.sha256"}, {"name": "plastic.manifest.json"}]'

  def setup
    super
    write_releases(<<~JSON)
      [
        {"tag_name": "v2.1.0-alpha.29", "prerelease": true, "assets": #{ASSETS}},
        {"tag_name": "v2.1.0-alpha.27", "prerelease": false, "assets": []},
        {"tag_name": "v2.0.3", "prerelease": false, "assets": #{ASSETS}}
      ]
    JSON
    write_tool("curl", fake_curl)
  end

  def write_releases(json) = File.write(File.join(@dir, "releases.json"), json)

  def fake_curl
    <<~SH
      #!/bin/sh
      url=""
      out=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -o) out="$2"; shift 2 ;;
          -H|--proto|--tlsv1.2) [ "$1" = "--tlsv1.2" ] && shift || shift 2 ;;
          -*) shift ;;
          *) url="$1"; shift ;;
        esac
      done
      case "$url" in
        *api.github.com*) cat "#{@dir}/releases.json" ;;
        *) echo "$url" >> "#{@dir}/asked-for"
           tag=$(basename "$(dirname "$url")")
           cp "#{@dir}/releases/$tag/$(basename "$url")" "$out" ;;
      esac
    SH
  end

  def asked_for = File.readlines(File.join(@dir, "asked-for"), chomp: true)

  def test_the_default_channel_takes_the_newest_stable_release
    release("2.0.3")
    _out, err, status = install

    assert_equal 0, status.exitstatus, err
    assert_includes asked_for, "https://github.com/zalom/plastic/releases/download/v2.0.3/plastic.tgz"
    assert_equal "2.0.3\n", run_launcher
  end

  def test_the_alpha_channel_takes_the_newest_alpha_with_all_three_files
    release("2.1.0-alpha.29")
    _out, err, status = install(PLASTIC_CHANNEL: "alpha")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.1.0-alpha.29\n", run_launcher
  end

  def test_an_exact_version_skips_the_release_list
    release("2.0.2")
    _out, err, status = install(PLASTIC_VERSION: "2.0.2")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.0.2\n", run_launcher
  end

  def test_a_dry_run_downloads_only_the_manifest
    release("2.0.3")
    _out, err, status = install("--dry-run")

    assert_equal 0, status.exitstatus, err
    assert_equal ["https://github.com/zalom/plastic/releases/download/v2.0.3/plastic.manifest.json"], asked_for
    refute_path_exists File.join(@home, ".local")
  end

  def test_a_channel_with_no_complete_release_names_the_way_out
    write_releases("[]")
    _out, err, status = install

    assert_equal 1, status.exitstatus
    assert_includes err, "PLASTIC_CHANNEL=alpha"
  end
end
