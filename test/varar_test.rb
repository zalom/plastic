# frozen_string_literal: true

require "minitest/autorun"
require "varar/minitest"
require_relative "../lib/plastic/cli/table"

# Turn every Markdown oath matched by varar.config.json into Minitest tests —
# varar.config.json lives at the project root (the parent of test/).
Varar::Minitest.generate_tests(Object, root: File.expand_path("..", __dir__))

# The acceptance documents are the end-to-end (e2e) layer, run by `bin/test --e2e`, and the core list: the commands whose whole path through a
# child process, two homes or a legacy store is the subject. The cases of every other
# command are kernel tests.
class VararCoverageTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  CORE = %w[status sync-up sync-down sync-import sync-second-home backup backup-list backup-restore legacy-import].freeze

  def documents = Dir.glob(File.join(REPO, "varar", "*.md")).map { |path| File.basename(path, ".md") }.sort

  def test_the_acceptance_documents_are_exactly_the_core_list
    assert_equal CORE.sort, documents
  end
end
