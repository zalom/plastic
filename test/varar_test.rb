# frozen_string_literal: true

require "minitest/autorun"
require "varar/minitest"
require_relative "../scripts/lib/plastic/cli/table"

# Turn every Markdown oath matched by varar.config.json into Minitest tests —
# varar.config.json lives at the project root (the parent of test/).
Varar::Minitest.generate_tests(Object, root: File.expand_path("..", __dir__))

# Intent 397 cutover: install, migrate stores, update, rollback, and project new drove
# store-layout.md, update-safety.md, and project-links.md, and none of that old-script
# behavior is in the kernel, so the three documents and their shared steps file
# (test/varar/store_layout.steps.rb) are retired with the rest of the legacy suite (D9,
# logged in resources/deleted_legacy_tests.txt). What a graph intent needs proven instead
# is narrower and more durable: every command the kernel actually registers has a document
# that walks it end to end, so a command can never ship with no acceptance coverage again.
class VararCoverageTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def test_every_kernel_command_has_a_varar_document
    Plastic::CLI::TABLE.each_key do |command|
      slug = command.tr(" ", "-")
      path = File.join(REPO, "varar", "#{slug}.md")

      assert File.file?(path), "`plastic #{command}` has no varar/#{slug}.md acceptance document"
    end
  end
end
