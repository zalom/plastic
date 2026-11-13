# frozen_string_literal: true

require_relative "test_helper"

# Guard test. No file of the graph puts a value into SQL text: values are bound.
class GraphSQLGuardTest < Minitest::Test
  ROOT = File.expand_path("../lib/plastic/graph", __dir__)
  FORBIDDEN = /SQL\.bind|SQL\.literal|\.literal\(/

  def test_no_file_of_the_graph_builds_sql_from_literals
    offenders = Dir.glob("**/*.rb", base: ROOT).select { |path| File.read(File.join(ROOT, path)).match?(FORBIDDEN) }

    assert_empty offenders
  end
end
