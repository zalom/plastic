# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tmpdir"

load File.expand_path("../../bin/verify-change", __dir__) unless defined?(VerifyChange)

# Runs the whole change gate on a small fixture project. A fake runner answers each step with the
# exit code the test names for it, so no tool starts.
module GateRun
  Finished = Struct.new(:code, :out, :err, :ran)
  Git = Struct.new(:output) do
    def success? = true
  end
  SOURCE = "lib/plastic/new_routine.rb"
  STEP_WORDS = { "rubocop" => "Lint", "simplecov" => "Patch coverage", "bin/crap" => "CRAP scores", "reek" => "Code smells",
                 "rubycritic" => "RubyCritic score" }.freeze

  MISS_TEXT = { "RubyCritic score" => "Score (85.2) is below the minimum 90.0\n" }.freeze

  def gate_fixture
    root = Dir.mktmpdir("gate-run")
    { "Gemfile.lock" => "GEM\n  specs:\n\nDEPENDENCIES\n  rubocop\n  rubycritic (~> 4.12)\n\n", ".rubocop.yml" => "AllCops:\n  NewCops: enable\n",
      ".reek.yml" => "---\ndetectors: {}\n", SOURCE => "", "test/plastic/new_routine_test.rb" => "" }.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), text)
    end
    root
  end

  def step_of(command)
    STEP_WORDS.find { |word, _| command.join(" ").include?(word) }&.last || "Tests with coverage"
  end

  # `codes` maps a step title to the exit code its fake tool gives; every other step gives 0.
  def run_gate(codes)
    root = gate_fixture
    ran = []
    out = StringIO.new
    err = StringIO.new
    Finished.new(gate_for(root, out, err, runner_for(codes, ran)).call, out.string, err.string, ran)
  ensure
    FileUtils.remove_entry(root) if root
  end

  # A code alone is a miss as the tool prints it; a pair names its own output.
  def answer(code, title)
    return code if code.is_a?(Array) || code.zero?

    [code, MISS_TEXT.fetch(title, "")]
  end

  def runner_for(codes, ran)
    lambda do |_env, command|
      title = step_of(command)
      ran << title
      answer(codes.fetch(title, 0), title)
    end
  end

  def gate_for(root, out, err, runner)
    git = ->(*args) { [args.include?("diff") ? "#{SOURCE}\n" : "abc123\n", Git.new] }
    sandbox = { "HOME" => "/nowhere", "PLASTIC_TMP" => "/nowhere" }
    VerifyChange.new(["main"], root:, out:, err:, git:, run: runner, sandbox:)
  end
end
