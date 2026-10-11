# frozen_string_literal: true

require "json"
require_relative "test_helper"

# Every Ruby file the release archive ships loads only files the archive
# ships, so no installed file fails on a missing require_relative.
class ShippedRequiresGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REQUIRE = /^\s*require_relative\s+["']([^"'#]+)["']/
  RUBY_LINE = %r{\A#!/usr/bin/env (-S )?ruby}

  def shipped
    @shipped ||= JSON.parse(File.read(File.join(ROOT, "package.json"))).fetch("files").flat_map { |entry| expand(entry) }
  end

  def expand(entry)
    return [entry] unless entry.end_with?("/")

    Dir.glob("#{entry}**/*", File::FNM_DOTMATCH, base: ROOT).select { |name| File.file?(File.join(ROOT, name)) }
  end

  def ruby?(name) = name.end_with?(".rb") || File.open(File.join(ROOT, name), &:gets).to_s.match?(RUBY_LINE)

  def missing(name, text, files)
    text.scan(REQUIRE).flatten.filter_map do |required|
      target = File.expand_path(required, File.dirname(File.join(ROOT, name)))
      target = "#{target}.rb" unless target.end_with?(".rb")
      "#{name} requires #{required}" unless files.include?(target)
    end
  end

  def shipped_paths = shipped.to_set { |name| File.join(ROOT, name) }

  def test_no_shipped_ruby_file_requires_a_file_that_does_not_ship
    subjects = shipped.select { |name| File.file?(File.join(ROOT, name)) && ruby?(name) }
    paths = shipped_paths

    refute_empty subjects
    assert_empty subjects.flat_map { |name| missing(name, File.read(File.join(ROOT, name)), paths) }
  end

  def test_a_require_of_a_file_that_does_not_ship_is_caught
    assert_equal ["bin/crap requires ../tools/crap"], missing("bin/crap", %(require_relative "../tools/crap"\n), shipped_paths)
  end

  def test_a_require_of_a_shipped_file_is_left_alone
    assert_empty missing("bin/plastic", %(require_relative "../scripts/lib/plastic"\n), shipped_paths)
  end
end
