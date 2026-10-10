# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/architecture_figures_helper"
require "architecture_figures"
require "open3"
require "tmpdir"

class ArchitectureFiguresCommandCallTest < Minitest::Test
  include ArchitectureFiguresHelper

  SESSION_VARIABLES = %w[PLASTIC_SESSION CLAUDE_CODE_SESSION_ID CODEX_SESSION_ID CODEX_THREAD_ID].freeze
  CREATE_STORE = 'require "plastic"; require "plastic/graph"; Plastic::Graph.create(home: ARGV.fetch(0), store: "global")'

  def environment(home) = SESSION_VARIABLES.to_h { |name| [name, nil] }.merge("HOME" => home, "PLASTIC_HOME" => home, "PLASTIC_TMP" => File.join(home, "tmp"))

  def normalize(line) = line.gsub(/\bintent:? \d+/) { |match| match.sub(/\d+/, "ID") }.gsub(/\d+--sample-title/, "ID--slug").squeeze(" ").strip

  def real_report
    Dir.mktmpdir do |home|
      _out, err, status = Open3.capture3({ "RUBYOPT" => "" }, "ruby", "-I", File.join(ROOT, "scripts", "lib"), "-e", CREATE_STORE, home)
      assert_predicate status, :success?, err
      out, err, status = Open3.capture3(environment(home), File.join(ROOT, "bin", "plastic"), "intent", "new", "Sample title")
      assert_predicate status, :success?, err
      out.lines.map { |line| normalize(line) }.reject(&:empty?)
    end
  end

  def test_the_drawn_report_lines_match_a_real_intent_new
    drawn = texts(ArchitectureFigures.render.fetch("command-call.svg")).select { |style, _text| style == "r" }.map { |_style, text| normalize(text) }

    refute_empty drawn
    assert_empty drawn - real_report
  end

  def test_the_normalizer_turns_ids_into_a_placeholder
    assert_equal "intent: ID", normalize("intent: 12")
    assert_equal "store/ID--slug/intent.md", normalize("        store/7--sample-title/intent.md")
    assert_equal "1 document in x.db", normalize("1  document in x.db")
  end
end
