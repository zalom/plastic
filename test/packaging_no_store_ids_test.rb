# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "json"

# Intent 211 - founding hard rule (owner ruling 2026-07-16): no Plastic artifact shipped in the
# npm package may embed personal/user-specific store data (intent-id lists, per-user snapshots,
# allowlists keyed on one store's contents). Proven by the legacy_bookend_amnesty.rb precedent
# (intent 170a), which shipped ~63 of the owner's own intent ids to every installer before 211
# removed it. This guard scans every file the npm "files" set would actually ship (derived from
# package.json itself, never a hand list - matching install_packaging_test.rb's precedent) for
# the same shape: a frozen array/hash literal carrying five or more Folgezettel-shaped id tokens.

REPO_ROOT = File.expand_path("..", __dir__)

# Matches every real id observed in the removed amnesty file: "1", "11", "121a", "124", "1a",
# "1b1a3", "4a1c1", "30a1a", etc. - digit-leading, optionally followed by any mix of letters and
# digits. Deliberately does not match letter-leading tokens (e.g. "plastic-statusline",
# "delivered", "SessionStart"), which is why the full-tree audit below finds zero legitimate
# shipped literals crossing the 5-token threshold.
FOLGEZETTEL_TOKEN = /\A\d+[a-zA-Z0-9]*\z/

module StoreIdLiteralScan
  module_function

  # Every file package.json's own "files" entry would actually ship, expanded from the real
  # repo tree (never a hand-maintained list - if "files" grows or shrinks, this scan follows).
  def shipped_files(repo_root: REPO_ROOT)
    files_globs = JSON.parse(File.read(File.join(repo_root, "package.json")))["files"]
    files_globs.flat_map do |entry|
      path = File.join(repo_root, entry)
      if entry.end_with?("/")
        Dir.glob(File.join(path, "**", "*")).select { |f| File.file?(f) }
      else
        File.file?(path) ? [path] : []
      end
    end
  end

  # Every %w[...] word-array literal, and every ["...", "...", ...] bracket-of-quoted-strings
  # literal, found in `text`. Returns an array of token arrays (one per literal found). Multiline
  # literals (like the removed amnesty file's project:plastic list) are matched via /m.
  def literal_token_groups(text)
    groups = []
    text.scan(/%w\[([^\]]*)\]/m) { |(body)| groups << body.split(/\s+/).reject(&:empty?) }
    text.scan(/\[\s*((?:"[^"]*"|'[^']*')(?:\s*,\s*(?:"[^"]*"|'[^']*'))*)\s*\]/m) do |(body)|
      groups << body.scan(/"([^"]*)"|'([^']*)'/).flatten.compact
    end
    groups
  end

  # A violation is a single literal carrying 5+ Folgezettel-shaped tokens - the exact shape of
  # the removed amnesty file's project:plastic list (60 tokens), never a coincidental one-off.
  def violations_in(text)
    literal_token_groups(text).select { |tokens| tokens.count { |t| t =~ FOLGEZETTEL_TOKEN } >= 5 }
  end
end

class PackagingNoStoreIdsTest < Minitest::Test
  # RED case (208 property 1: a check must ship with a test proving it CAN report a problem):
  # a fixture reconstructing the removed amnesty file's exact shape must be caught, independent
  # of whether scripts/lib/legacy_bookend_amnesty.rb still exists on disk.
  def test_detects_a_frozen_id_list_literal_fixture
    fixture = <<~RUBY
      module LegacyBookendAmnesty
        LIST = {
          "project:plastic" => %w[
            1 11 121a 124 128 13 13b 15 158 158a 159 160 163
          ].freeze,
        }.freeze
      end
    RUBY

    violations = StoreIdLiteralScan.violations_in(fixture)
    refute_empty violations, "the scanner must be able to catch the known amnesty-shaped literal"
  end

  # GREEN case: nothing under the CURRENT shipped set (package.json "files") embeds a
  # store-id-list literal. This is the proof case for 211's removal of
  # scripts/lib/legacy_bookend_amnesty.rb: this assertion would have FAILED against pre-removal
  # main (the amnesty file, still shipped then, matches this exact shape) and passes now only
  # because this intent's own diff deleted it.
  def test_shipped_tree_carries_no_store_id_list_literal
    offenders = StoreIdLiteralScan.shipped_files.filter_map do |path|
      text = File.read(path)
      violations = StoreIdLiteralScan.violations_in(text)
      "#{path}: #{violations.size} literal(s)" unless violations.empty?
    end

    assert_empty offenders,
      "shipped file(s) embed a store-specific id-list literal (founding hard rule, intent 211): " \
      "#{offenders.join('; ')}"
  end
end
