# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"

class LazyCommandDispatchTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_each_dependency_family_dispatches_in_a_fresh_process
    Dir.mktmpdir do |home|
      %w[status intent\ discover\ 1\ term architecture\ status\ --project\ missing hook\ resume].each do |command|
        _stdout, stderr, _status = Open3.capture3(environment(home), File.join(ROOT, "bin", "plastic"), *command.split)

        refute_match(/uninitialized constant/, stderr, command)
      end
    end
  end

  private

  def environment(home) = { "PLASTIC_HOME" => home, "PLASTIC_TMP" => File.join(home, "tmp") }
end
