require_relative "../test_helper"
require_relative "../../tools/crap"
require "stringio"
require "tmpdir"
require "fileutils"

class CrapTest < Minitest::Test
  SOURCE = <<~RUBY_SOURCE
    module Shop
      class Order
        def plain
          1
        end

        def branchy(a, b)
          return 0 if a.nil?
          if a && b
            1
          elsif a || b
            2
          else
            a&.size
          end
        end

        def self.build(kind)
          case kind
          when :a then 1
          when :b then 2
          end
        end
      end
    end
  RUBY_SOURCE

  def found
    Crap.methods_in_source(SOURCE, "lib/shop/order.rb")
  end

  def test_names_methods_with_their_namespace
    assert_equal ["Shop::Order#plain", "Shop::Order#branchy", "Shop::Order.build"], found.map { _1[:name] }
  end

  def test_counts_cyclomatic_complexity
    assert_equal [1, 7, 3], found.map { _1[:complexity] }
  end

  def test_records_method_line_ranges
    assert_equal [[3, 5], [7, 16], [18, 23]], found.map { [_1[:first_line], _1[:last_line]] }
  end

  def test_formula_matches_crap4j
    assert_equal 6.0, Crap.formula(6, 1.0)
    assert_equal 42.0, Crap.formula(6, 0.0)
    assert_equal 10.5, Crap.formula(6, 0.5)
  end

  def test_method_coverage_ignores_def_and_end_lines
    lines = [nil, nil, 1, 0, nil]
    assert_equal 0.0, Crap.method_coverage({ first_line: 3, last_line: 5 }, lines)
    assert_equal 1.0, Crap.method_coverage({ first_line: 3, last_line: 5 }, [nil, nil, 1, 1, nil])
  end

  def test_method_without_coverage_data_counts_as_uncovered
    assert_equal 0.0, Crap.method_coverage({ first_line: 3, last_line: 5 }, nil)
  end

  def test_merges_runs_by_taking_the_highest_hit_count
    resultset = { "a" => { "coverage" => { "/x.rb" => { "lines" => [nil, 0, 2] } } },
                  "b" => { "coverage" => { "/x.rb" => { "lines" => [nil, 3, 0] } } } }.to_json
    assert_equal({ "/x.rb" => [nil, 3, 2] }, Crap.line_coverage(resultset))
  end

  def test_reads_changed_lines_from_a_zero_context_diff
    diff = <<~DIFF
      +++ b/lib/shop/order.rb
      @@ -7,0 +8,3 @@ class Order
      @@ -20 +23 @@ def self.build
      +++ b/lib/shop/cart.rb
      @@ -4,2 +4,0 @@
    DIFF
    assert_equal({ "lib/shop/order.rb" => [8, 9, 10, 23], "lib/shop/cart.rb" => [4] }, Crap.changed_lines(diff))
  end

  def test_touched_when_a_changed_line_falls_inside_the_method
    changed = { "lib/shop/order.rb" => [9] }
    assert Crap.touched?({ file: "lib/shop/order.rb", first_line: 7, last_line: 16 }, changed)
    refute Crap.touched?({ file: "lib/shop/order.rb", first_line: 3, last_line: 5 }, changed)
  end

  def test_cli_reports_methods_and_fails_above_the_threshold
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib/shop"))
      File.write(File.join(root, "lib/shop/order.rb"), SOURCE)
      out = StringIO.new
      status = Crap::CLI.new(["--threshold", "30", "lib/shop/order.rb"], root: root, out: out).run
      assert_equal 1, status
      assert_includes out.string, "56.0    7          0%        Shop::Order#branchy"
      assert_includes out.string, "3 methods, 1 above CRAP 30"
    end
  end

  def test_cli_scores_only_touched_methods_with_since
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib/shop"))
      File.write(File.join(root, "lib/shop/order.rb"), SOURCE)
      out = StringIO.new
      git = ->(*) { "+++ b/lib/shop/order.rb\n@@ -3 +3 @@\n" }
      status = Crap::CLI.new(["--since", "main", "lib/shop/order.rb"], root: root, out: out, git: git).run
      assert_equal 0, status
      assert_includes out.string, "1 methods, 0 above CRAP 30"
    end
  end

  def test_cli_prints_usage_with_help
    out = StringIO.new
    assert_equal 0, Crap::CLI.new(["--help"], root: Dir.pwd, out: out).run
    assert_includes out.string, "Exit codes: 0 no method above the threshold"
  end

  def test_cli_rejects_an_unknown_option_with_usage
    out = StringIO.new
    assert_equal 2, Crap::CLI.new(["--bogus"], root: Dir.pwd, out: out).run
    assert_includes out.string, "Usage: bin/crap"
  end

  def test_cli_rejects_an_option_missing_its_value_at_the_end_of_the_arguments
    out = StringIO.new
    assert_equal 2, Crap::CLI.new(["--threshold"], root: Dir.pwd, out: out).run
    assert_includes out.string, "Usage: bin/crap"
  end

  def test_cli_rejects_an_option_missing_its_value_before_another_option
    out = StringIO.new
    assert_equal 2, Crap::CLI.new(["--since", "--coverage", "coverage/.resultset.json"], root: Dir.pwd, out: out).run
    assert_includes out.string, "Usage: bin/crap"
  end
end
