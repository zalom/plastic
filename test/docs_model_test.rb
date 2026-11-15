# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# The docs describe the model: the hooks of each harness.
class DocsModelTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ADAPTERS = File.join(ROOT, "docs", "reference", "harness-adapters.md")

  def test_adapters_doc_names_the_hooks_of_each_harness
    body = File.read(ADAPTERS).gsub(/\s+/, " ")

    ["`hook start`, `hook stop` and `hook end`", "the update check", "no hooks"].each { |phrase| assert_includes body, phrase }
  end

  def test_adapters_doc_names_no_removed_hook
    body = File.read(ADAPTERS)

    ["`record`", "spawn preamble", "delivery.lock", "day ledger"].each { |phrase| refute_includes body, phrase }
  end
end
