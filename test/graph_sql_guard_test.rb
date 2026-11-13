# frozen_string_literal: true

require_relative "test_helper"

class GraphSQLGuardTest < Minitest::Test
  ROOT = File.expand_path("../lib/plastic/graph", __dir__)
  FORBIDDEN = /SQL\.bind|SQL\.literal|\.literal\(/
  KEYWORD = /\b(SELECT|INSERT|UPDATE|DELETE|WHERE|VALUES)\b/
  QUOTED_INTERPOLATION = /'[^'\n]*#\{[^}\n]*\}[^'\n]*'/

  def graph_files = Dir.glob("**/*.rb", base: ROOT).to_h { |path| [path, File.read(File.join(ROOT, path))] }

  def interpolated_values(text) = text.lines.select { |line| line.match?(KEYWORD) && line.match?(QUOTED_INTERPOLATION) }

  def test_no_file_of_the_graph_builds_sql_from_literals
    offenders = graph_files.select { |_path, text| text.match?(FORBIDDEN) }.keys

    assert_empty offenders
  end

  def test_no_file_of_the_graph_puts_a_value_between_quotes_in_sql
    offenders = graph_files.transform_values { |text| interpolated_values(text) }.reject { |_path, lines| lines.empty? }

    assert_empty offenders
  end

  def test_the_guard_sees_a_value_between_quotes_in_sql
    assert_equal 1, interpolated_values(%(rows("SELECT * FROM t WHERE a = '\#{value}'"))).size
    assert_empty interpolated_values(%(rows("SELECT * FROM t WHERE a = :a")))
  end
end
