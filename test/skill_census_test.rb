# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "date"
require "open3"
require "rbconfig"
require "set"

require_relative "../bin/lib/skill_census"

# Intent 324: the skill usage census. Every row of ACTION_1's failure-mode
# matrix (S1 to S8) is proven here, hermetically. No test reads ~/.claude;
# every test builds its own fixture under test/fixtures/skill_census/ or a
# Dir.mktmpdir, except the one live-roster test, which reads the repo's own
# skills/ directory (that is the point of that one test).

ROOT = File.expand_path("../..", __FILE__)
FIXTURES = File.join(ROOT, "test", "fixtures", "skill_census")
FIXTURE_SKILLS = File.join(FIXTURES, "skills")
FIXTURE_HISTORY = File.join(FIXTURES, "history.jsonl")
FIXTURE_TRANSCRIPTS = File.join(FIXTURES, "transcripts")
CENSUS = File.join(ROOT, "bin", "plastic-skill-census")

# Writes one JSONL file (an array of Hashes, one per line) under dir/rel_path,
# creating parent directories as needed.
def write_jsonl(dir, rel_path, records)
  path = File.join(dir, rel_path)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, records.map { |r| JSON.generate(r) }.join("\n") + "\n")
  path
end

def build_skills_dir(dir, entries)
  entries.each do |name, frontmatter|
    skill_dir = File.join(dir, name)
    FileUtils.mkdir_p(skill_dir)
    next if frontmatter.nil?

    File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
      ---
      #{frontmatter}
      ---

      # #{name} (fixture)
    MD
  end
end

# ---------------------------------------------------------------------------
# S1 - Roster
# ---------------------------------------------------------------------------
class SkillCensusRosterTest < Minitest::Test
  def test_roster_lists_only_dirs_with_skill_md
    names = SkillCensus::Roster.load(FIXTURE_SKILLS).map(&:name)

    refute_includes names, "plastic-_notes"
    refute_includes names, "plastic-empty"
    assert_includes names, "plastic-auto"
  end

  def test_roster_user_invocable_true
    roster = SkillCensus::Roster.load(FIXTURE_SKILLS)

    assert roster.find { |s| s.name == "plastic-auto" }.user_invocable
    assert roster.find { |s| s.name == "plastic-doctor" }.user_invocable
  end

  def test_roster_explicit_false_is_false
    roster = SkillCensus::Roster.load(FIXTURE_SKILLS)

    refute roster.find { |s| s.name == "plastic-explicit-false" }.user_invocable
  end

  def test_roster_missing_flag_is_false
    roster = SkillCensus::Roster.load(FIXTURE_SKILLS)

    refute roster.find { |s| s.name == "plastic-conventions" }.user_invocable
  end

  def test_live_roster_matches_skills_tree
    live_skills_dir = File.join(ROOT, "skills")
    roster = SkillCensus::Roster.load(live_skills_dir)

    expected = Dir.children(live_skills_dir).select do |entry|
      File.file?(File.join(live_skills_dir, entry, "SKILL.md"))
    end.sort

    assert_equal expected.map { |e| "plastic-#{e}" }.sort, roster.map(&:name).sort
    assert_equal 20, roster.length
    assert_equal 3, roster.count { |s| !s.user_invocable }
  end

  def test_name_map_targets_are_live_roster_names
    roster_names = SkillCensus::Roster.load(File.join(ROOT, "skills")).map(&:name)

    SkillCensus::NAME_MAP.each_value do |target|
      assert_includes roster_names, target, "NAME_MAP target #{target} is not a live roster name"
    end
  end

  def test_scripts_agents_retired_and_name_map_are_disjoint
    map_raw = SkillCensus::NAME_MAP.keys.to_set
    map_targets = SkillCensus::NAME_MAP.values.to_set
    retired = SkillCensus::RETIRED.to_set
    scripts = SkillCensus::SCRIPTS.to_set
    agents = SkillCensus::AGENTS.to_set

    assert_empty scripts & map_raw, "a script name must never map into a skill via NAME_MAP"
    assert_empty scripts & map_targets, "a script must never be a NAME_MAP target"
    assert_empty agents & map_raw, "an agent name must never map into a skill via NAME_MAP"
    assert_empty agents & map_targets, "an agent must never be a NAME_MAP target"
    assert_empty scripts & agents
    assert_empty scripts & retired
    assert_empty agents & retired
  end
end

# ---------------------------------------------------------------------------
# S2 - Transcript file walk and parsing
# ---------------------------------------------------------------------------
class SkillCensusTranscriptWalkTest < Minitest::Test
  def test_scans_dash_named_project_dirs
    result = SkillCensus::TranscriptScanner.new(FIXTURE_TRANSCRIPTS, cutoff: "2026-09-02").scan

    assert_equal 2, result.files_top
  end

  def test_workflows_nesting_is_a_subagent_file
    result = SkillCensus::TranscriptScanner.new(FIXTURE_TRANSCRIPTS, cutoff: "2026-09-02").scan

    assert_equal 2, result.files_top
    assert_equal 2, result.files_subagent
  end

  def test_unparsable_line_is_counted_and_skipped
    Dir.mktmpdir("skill-census-s2") do |dir|
      path = write_jsonl(dir, "proj/s1.jsonl", [{ "type" => "user", "uuid" => "u1", "timestamp" => "2026-07-01T00:00:00Z", "message" => { "role" => "user", "content" => "hello" } }])
      File.write(path, File.read(path) + "{not valid json\n")

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.unparsable_lines
      assert_equal 1, result.record_count
    end
  end

  def test_string_content_and_block_content_both_classified
    Dir.mktmpdir("skill-census-s2") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "user", "uuid" => "u1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "user", "content" => "<command-name>/plastic-auto</command-name>" } },
        { "type" => "user", "uuid" => "u2", "timestamp" => "2026-07-01T00:01:00Z",
          "message" => { "role" => "user", "content" => [{ "type" => "text", "text" => "<command-name>/plastic-doctor</command-name>" }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan
      names = result.transcript_typed.map(&:name)

      assert_includes names, "plastic-auto"
      assert_includes names, "plastic-doctor"
    end
  end

  def test_missing_transcripts_dir_raises
    assert_raises(StandardError) do
      SkillCensus::TranscriptScanner.new("/no/such/dir", cutoff: "2026-09-02").scan
    end
  end

  def test_first_and_last_seen_ignore_records_without_timestamp
    Dir.mktmpdir("skill-census-s2") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "user", "uuid" => "u1", "message" => { "role" => "user", "content" => "no timestamp here" } },
        { "type" => "user", "uuid" => "u2", "timestamp" => "2026-07-05T00:00:00Z", "message" => { "role" => "user", "content" => "text" } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal Date.new(2026, 7, 5), result.first_seen
      assert_equal Date.new(2026, 7, 5), result.last_seen
    end
  end

  def test_only_user_type_records_are_classified
    Dir.mktmpdir("skill-census-s2") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "system", "uuid" => "u1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "system", "content" => "<command-name>/plastic-doctor</command-name>" } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_empty result.transcript_typed
      assert_empty result.mentions
    end
  end
end

# ---------------------------------------------------------------------------
# S3 - Typed commands from the prompt history
# ---------------------------------------------------------------------------
class SkillCensusHistoryTest < Minitest::Test
  def scan(cutoff: "2026-09-02")
    SkillCensus::HistoryScanner.new(FIXTURE_HISTORY, cutoff: cutoff).scan
  end

  def test_history_typed_counts
    result = scan
    typed_names = result.typed.map(&:name)

    assert_equal 2, typed_names.count("plastic-doctor")
    assert_equal 1, typed_names.count("plastic-continuing") # plastic-continuing retired in 2.0 (intent 304)
  end

  def test_colon_namespace_maps_onto_hyphen_form
    result = scan
    typed_names = result.typed.map(&:name)

    assert_equal 2, typed_names.count("plastic-update")
    assert_includes typed_names, "plastic-auto"
  end

  def test_typed_with_args_keeps_the_verb
    Dir.mktmpdir("skill-census-s3") do |dir|
      path = File.join(dir, "history.jsonl")
      File.write(path, JSON.generate({ "display" => "/plastic-auto go now", "timestamp" => 1_780_000_000_000, "project" => "/x" }) + "\n")

      result = SkillCensus::HistoryScanner.new(path, cutoff: "2026-09-02").scan

      assert_equal ["plastic-auto"], result.typed.map(&:name)
    end
  end

  def test_history_mid_sentence_is_a_mention_not_typed
    result = scan

    refute_includes result.typed.map(&:name), nil
    assert_equal 0, result.typed.count { |e| e.detail.to_s.include?("run /plastic-auto now") }
    assert_operator result.mentions.count { |e| e.detail.to_s.include?("run /plastic-auto now") }, :>=, 1
  end

  def test_history_backticked_is_a_mention
    result = scan

    assert_operator result.mentions.count { |e| e.detail.to_s.include?("`/plastic-auto`") }, :>=, 1
    assert_equal 0, result.typed.count { |e| e.detail.to_s.include?("`/plastic-auto`") }
  end

  def test_history_builtins_tallied_separately
    result = scan

    assert_equal 1, result.builtins["clear"]
    refute_includes result.typed.map(&:name), "clear"
  end

  def test_history_records_after_cutoff_are_excluded
    result = scan

    self_generated_dates = result.self_generated.map(&:date)

    assert_includes self_generated_dates, Date.new(2026, 9, 3)
    typed_dates = result.typed.select { |e| e.name == "plastic-doctor" }.map(&:date)
    refute_includes typed_dates, Date.new(2026, 9, 3)
  end

  def test_history_typed_events_carry_project_and_date
    result = scan
    doctor_event = result.typed.find { |e| e.name == "plastic-doctor" }

    assert_equal "/Users/z/app", doctor_event.project
    assert_equal Date.new(2026, 6, 1), doctor_event.date
  end

  def test_history_monthly_rows
    result = scan

    assert_equal 6, result.monthly["2026-06"]
    assert_equal 1, result.monthly["2026-07"]
  end
end

# ---------------------------------------------------------------------------
# S4 - Agent invocation classification
# ---------------------------------------------------------------------------
class SkillCensusCallsTest < Minitest::Test
  def test_skill_call_counts
    Dir.mktmpdir("skill-census-s4") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "t1", "name" => "Skill", "input" => { "skill" => "plastic-auto" } }] } },
        { "type" => "assistant", "uuid" => "a2", "timestamp" => "2026-07-01T00:01:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "t2", "name" => "Skill", "input" => { "skill" => "plastic-doctor", "args" => "--core" } }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      names = result.calls_main.map(&:name)
      assert_includes names, "plastic-auto"
      assert_includes names, "plastic-doctor"
    end
  end

  def test_calls_split_main_and_agent
    result = SkillCensus::TranscriptScanner.new(FIXTURE_TRANSCRIPTS, cutoff: "2026-09-02").scan

    assert_includes result.calls_main.map(&:name), "plastic-auto"
    assert_includes result.calls_agent.map(&:name), "plastic-doctor"
    assert_includes result.calls_agent.map(&:name), "plastic-update"
  end

  def test_duplicate_tool_use_id_counted_once
    Dir.mktmpdir("skill-census-s4") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "dup", "name" => "Skill", "input" => { "skill" => "plastic-auto" } }] } },
        { "type" => "assistant", "uuid" => "a2", "timestamp" => "2026-07-01T00:01:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "dup", "name" => "Skill", "input" => { "skill" => "plastic-auto" } }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.calls_main.count { |c| c.tool_use_id == "dup" }
    end
  end

  def test_bash_command_text_is_not_a_call_or_typed
    Dir.mktmpdir("skill-census-s4") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "b1", "name" => "Bash", "input" => { "command" => "/plastic-auto go" } }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_empty result.calls_main
      assert_empty result.calls_agent
      assert_empty result.transcript_typed
    end
  end

  def test_corroboration_reads_tool_use_result_command_name
    Dir.mktmpdir("skill-census-s4") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "c1", "name" => "Skill", "input" => { "skill" => "plastic-auto" } }] } },
        { "type" => "user", "uuid" => "a2", "timestamp" => "2026-07-01T00:00:01Z",
          "toolUseResult" => { "success" => true, "commandName" => "plastic-auto" },
          "message" => { "role" => "user", "content" => [{ "type" => "tool_result", "tool_use_id" => "c1", "content" => [{ "type" => "text", "text" => "Launching skill: plastic-auto" }] }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.corroboration.matched
      assert_empty result.corroboration.disagreements
    end
  end

  def test_corroboration_disagreement_is_reported
    Dir.mktmpdir("skill-census-s4") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "d1", "name" => "Skill", "input" => { "skill" => "plastic-artifact-design" } }] } },
        { "type" => "user", "uuid" => "a2", "timestamp" => "2026-07-01T00:00:01Z",
          "toolUseResult" => { "success" => true, "commandName" => "plastic-artifact-design" },
          "message" => { "role" => "user", "content" => [{ "type" => "tool_result", "tool_use_id" => "d1", "content" => [{ "type" => "text", "text" => "Launching skill: plastic-other-name" }] }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.corroboration.disagreements.length
      disagreement = result.corroboration.disagreements.first
      assert_equal "plastic-artifact-design", disagreement[:command_name]
      assert_equal "plastic-other-name", disagreement[:launching_text]
    end
  end

  def test_non_plastic_calls_go_to_other_skills
    Dir.mktmpdir("skill-census-s4") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "e1", "name" => "Skill", "input" => { "skill" => "writing-style" } }] } },
        { "type" => "assistant", "uuid" => "a2", "timestamp" => "2026-07-01T00:01:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "e2", "name" => "Skill", "input" => { "skill" => "claudish-to-english:claudish" } }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.other_skills["writing-style"][:calls]
      assert_equal 1, result.other_skills["claudish-to-english:claudish"][:calls]
      assert_empty result.calls_main
    end
  end
end

# ---------------------------------------------------------------------------
# S5 - Loads, attribution, and mentions
# ---------------------------------------------------------------------------
class SkillCensusLoadsAttributionMentionsTest < Minitest::Test
  def test_skill_body_injection_is_a_load_only
    Dir.mktmpdir("skill-census-s5") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "user", "uuid" => "u1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "user", "content" => "Base directory for this skill: /some/path/plastic-auto" } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 0, result.transcript_typed.length
      assert_equal 0, result.mentions.length
      assert_equal 1, result.loads.length
      assert_equal "plastic-auto", result.loads.first.name
    end
  end

  def test_call_without_load_still_counts
    Dir.mktmpdir("skill-census-s5") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "f1", "name" => "Skill", "input" => { "skill" => "plastic-artifact-design" } }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.calls_main.length
      assert_equal 0, result.loads.length
    end
  end

  def test_attribution_is_a_separate_column
    Dir.mktmpdir("skill-census-s5") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-07-01T00:00:00Z",
          "attributionSkill" => "plastic-auto",
          "message" => { "role" => "assistant", "content" => [{ "type" => "text", "text" => "working" }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.attributed["plastic-auto"]
      assert_empty result.calls_main
    end
  end

  def test_script_path_occurrence_is_not_a_skill_mention
    Dir.mktmpdir("skill-census-s5") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "user", "uuid" => "u1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "user", "content" => "run ~/.plastic/scripts/plastic-lock --intent 324" } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.scripts["plastic-lock"]
      assert_empty result.mentions
    end
  end

  def test_agent_name_goes_to_the_agents_table
    Dir.mktmpdir("skill-census-s5") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "user", "uuid" => "u1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "user", "content" => "dispatch plastic-enforcer for this intent" } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.agents["plastic-enforcer"]
      assert_empty result.mentions
    end
  end

  def test_command_name_in_subagent_file_is_not_typed
    Dir.mktmpdir("skill-census-s5") do |dir|
      write_jsonl(dir, "proj/sess/subagents/agent-1.jsonl", [
        { "type" => "user", "uuid" => "u1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "user", "content" => "<command-message>plastic-auto</command-message>\n<command-name>/plastic-auto</command-name>" } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_empty result.transcript_typed
      assert_empty result.self_generated
    end
  end

  def test_transcript_typed_events_are_counted_for_cross_check
    result = SkillCensus::TranscriptScanner.new(FIXTURE_TRANSCRIPTS, cutoff: "2026-09-02").scan

    assert_kind_of Array, result.transcript_typed
  end

  def test_duplicate_uuid_counted_once
    Dir.mktmpdir("skill-census-s5") do |dir|
      record = { "type" => "assistant", "uuid" => "dup-uuid", "timestamp" => "2026-07-01T00:00:00Z",
                 "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "g1", "name" => "Skill", "input" => { "skill" => "plastic-auto" } }] } }
      write_jsonl(dir, "proj/s1.jsonl", [record, record])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_equal 1, result.record_count
      assert_equal 1, result.calls_main.length
    end
  end

  # D16 leaked on three dimensions (lead, post-exec review 2026-09-03): a
  # post-cutoff Skill call, load, and tool_result corroboration all still
  # landed in the live counts. This proves the fix.
  def test_cutoff_excludes_calls_loads_and_corroboration
    Dir.mktmpdir("skill-census-s5") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-09-02T00:00:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "post1", "name" => "Skill", "input" => { "skill" => "plastic-auto" } }] } },
        { "type" => "user", "uuid" => "u1", "timestamp" => "2026-09-02T00:01:00Z",
          "message" => { "role" => "user", "content" => "Base directory for this skill: /some/path/plastic-auto" } },
        { "type" => "user", "uuid" => "u2", "timestamp" => "2026-09-02T00:02:00Z",
          "toolUseResult" => { "success" => true, "commandName" => "plastic-auto" },
          "message" => { "role" => "user", "content" => [{ "type" => "tool_result", "tool_use_id" => "post1", "content" => "done" }] } },
      ])

      result = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan

      assert_empty result.calls_main
      assert_empty result.calls_agent
      assert_empty result.loads
      assert_equal 0, result.corroboration.matched
      assert_equal 1, result.self_generated_calls
      assert_equal 1, result.self_generated_loads
    end
  end

  def test_self_generated_counts_are_per_dimension
    Dir.mktmpdir("skill-census-s5") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-09-02T00:00:00Z",
          "message" => { "role" => "assistant", "content" => [{ "type" => "tool_use", "id" => "post1", "name" => "Skill", "input" => { "skill" => "plastic-auto" } }] } },
        { "type" => "user", "uuid" => "u1", "timestamp" => "2026-09-02T00:01:00Z",
          "message" => { "role" => "user", "content" => "Base directory for this skill: /some/path/plastic-auto" } },
        { "type" => "assistant", "uuid" => "a2", "timestamp" => "2026-09-02T00:02:00Z",
          "attributionSkill" => "plastic-auto",
          "message" => { "role" => "assistant", "content" => [{ "type" => "text", "text" => "working" }] } },
        { "type" => "user", "uuid" => "u2", "timestamp" => "2026-09-02T00:03:00Z",
          "message" => { "role" => "user", "content" => "<command-message>plastic-auto</command-message>\n<command-name>/plastic-auto</command-name>" } },
      ])

      roster = SkillCensus::Roster.load(FIXTURE_SKILLS)
      history_scan = SkillCensus::HistoryScanner.new(FIXTURE_HISTORY, cutoff: "2026-09-02").scan
      transcript_scan = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan
      built = SkillCensus::Tally.new(history_scan, transcript_scan, roster).build

      md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

      assert_includes md, "| typed | 1 |"
      assert_includes md, "| calls | 1 |"
      assert_includes md, "| loads | 1 |"
      assert_includes md, "| attributed | 1 |"
    end
  end

  def test_non_plastic_loads_and_attribution_go_to_other_skills
    Dir.mktmpdir("skill-census-s5") do |dir|
      write_jsonl(dir, "proj/s1.jsonl", [
        { "type" => "user", "uuid" => "u1", "timestamp" => "2026-07-01T00:00:00Z",
          "message" => { "role" => "user", "content" => "Base directory for this skill: /some/path/writing-style" } },
        { "type" => "assistant", "uuid" => "a1", "timestamp" => "2026-07-01T00:01:00Z",
          "attributionSkill" => "writing-style",
          "message" => { "role" => "assistant", "content" => [{ "type" => "text", "text" => "working" }] } },
      ])

      roster = SkillCensus::Roster.load(FIXTURE_SKILLS)
      history_scan = SkillCensus::HistoryScanner.new(FIXTURE_HISTORY, cutoff: "2026-09-02").scan
      transcript_scan = SkillCensus::TranscriptScanner.new(dir, cutoff: "2026-09-02").scan
      built = SkillCensus::Tally.new(history_scan, transcript_scan, roster).build

      assert_equal 0, built.unmapped.loads
      assert_equal 0, built.unmapped.attributed
      assert_equal 1, transcript_scan.other_skills["writing-style"][:loads]
      assert_equal 1, transcript_scan.other_skills["writing-style"][:attributed]
    end
  end
end

# ---------------------------------------------------------------------------
# S6 - Name mapping
# ---------------------------------------------------------------------------
class SkillCensusTallyTest < Minitest::Test
  def roster
    SkillCensus::Roster.load(FIXTURE_SKILLS)
  end

  def history_scan(typed_names)
    events = typed_names.map { |name| SkillCensus::Event.new(name: name, date: Date.new(2026, 7, 1), project: "/x") }
    empty = SkillCensus::HistoryScanner::Result.new(record_count: 0, first_seen: nil, last_seen: nil,
                                                      typed: events, mentions: [], builtins: {},
                                                      self_generated: [], monthly: {})
    empty
  end

  def transcript_scan
    SkillCensus::TranscriptScanner::Result.new(
      files_top: 0, files_subagent: 0, record_count: 0, unparsable_lines: 0,
      first_seen: nil, last_seen: nil, calls_main: [], calls_agent: [], other_skills: {},
      loads: [], attributed: {}, mentions: [], scripts: {}, agents: {},
      transcript_typed: [], self_generated: [],
      corroboration: SkillCensus::TranscriptScanner::Corroboration.new(matched: 0, disagreements: [])
    )
  end

  def test_absorbed_name_maps_into_successor
    built = SkillCensus::Tally.new(history_scan(["plastic-intent-brainstorming"]), transcript_scan, roster).build # plastic-intent-brainstorming retired in 2.0

    speccing = built.skills.find { |s| s.name == "plastic-intent-speccing" }
    assert_equal 1, speccing.typed
    assert_equal 1, speccing.mapped_from["plastic-intent-brainstorming"] # plastic-intent-brainstorming retired in 2.0
  end

  def test_row_shows_mapped_from_names_and_their_counts
    roster_with_target = roster + [SkillCensus::Roster::Skill.new(name: "plastic-intent-continuing", user_invocable: true)]
    built = SkillCensus::Tally.new(
      history_scan(["plastic-continuing"] * 5 + ["plastic-intent-continuing"]), # plastic-continuing retired in 2.0
      transcript_scan, roster_with_target
    ).build

    row = built.skills.find { |s| s.name == "plastic-intent-continuing" }
    assert_equal 6, row.typed
    assert_equal 5, row.mapped_from["plastic-continuing"] # plastic-continuing retired in 2.0
  end

  def test_retired_name_goes_to_retired_row
    built = SkillCensus::Tally.new(history_scan(["plastic-intent-discovering"]), transcript_scan, roster).build # plastic-intent-discovering retired in 2.0

    assert_equal 1, built.retired.typed
  end

  def test_unknown_name_goes_to_unmapped_row
    built = SkillCensus::Tally.new(history_scan(["plastic-foo"]), transcript_scan, roster).build

    assert_equal 1, built.unmapped.typed
  end

  def test_roster_name_maps_to_itself
    built = SkillCensus::Tally.new(history_scan(["plastic-auto"]), transcript_scan, roster).build

    assert_equal 1, built.skills.find { |s| s.name == "plastic-auto" }.typed
    assert_empty built.skills.find { |s| s.name == "plastic-auto" }.mapped_from
  end

  def test_rows_follow_roster_order_then_retired_then_unmapped
    built = SkillCensus::Tally.new(history_scan([]), transcript_scan, roster).build
    roster_order = roster.map(&:name)

    assert_equal roster_order, built.skills.map(&:name)
    assert_equal "retired", built.retired.name
    assert_equal "unmapped", built.unmapped.name
  end

  def test_map_coverage_lists_every_entry_with_its_observed_count
    built = SkillCensus::Tally.new(history_scan([]), transcript_scan, roster).build

    assert_equal SkillCensus::NAME_MAP.length, built.map_coverage.length
    zero_entry = built.map_coverage.find { |e| e[:observed].zero? }
    refute_nil zero_entry
  end

  def test_mechanism_skill_renders_na_not_zero
    mechanism_roster = [SkillCensus::Roster::Skill.new(name: "plastic-agent-advisor", user_invocable: false)]
    built = SkillCensus::Tally.new(history_scan([]), transcript_scan, mechanism_roster).build

    row = built.skills.find { |s| s.name == "plastic-agent-advisor" }
    refute row.evidence?
    refute_nil row.mechanism
  end

  def test_first_and_last_seen_per_skill
    events = [
      SkillCensus::Event.new(name: "plastic-auto", date: Date.new(2026, 6, 1)),
      SkillCensus::Event.new(name: "plastic-auto", date: Date.new(2026, 7, 1)),
    ]
    hs = SkillCensus::HistoryScanner::Result.new(record_count: 0, first_seen: nil, last_seen: nil,
                                                   typed: events, mentions: [], builtins: {},
                                                   self_generated: [], monthly: {})
    built = SkillCensus::Tally.new(hs, transcript_scan, roster).build

    row = built.skills.find { |s| s.name == "plastic-auto" }
    assert_equal Date.new(2026, 6, 1), row.first_seen
    assert_equal Date.new(2026, 7, 1), row.last_seen
  end
end

# ---------------------------------------------------------------------------
# S7 - Report rendering
# ---------------------------------------------------------------------------
class SkillCensusReportTest < Minitest::Test
  def built
    roster = SkillCensus::Roster.load(FIXTURE_SKILLS)
    history_scan = SkillCensus::HistoryScanner.new(FIXTURE_HISTORY, cutoff: "2026-09-02").scan
    transcript_scan = SkillCensus::TranscriptScanner.new(FIXTURE_TRANSCRIPTS, cutoff: "2026-09-02").scan
    SkillCensus::Tally.new(history_scan, transcript_scan, roster).build
  end

  def test_markdown_has_a_summary_row_per_roster_skill_plus_retired_and_unmapped
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_includes md, "plastic-auto"
    assert_includes md, "| retired |"
    assert_includes md, "| unmapped |"
  end

  def test_summary_table_has_a_user_invocable_column
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_includes md, "user_invocable"
  end

  def test_summary_table_has_calls_main_and_calls_agent_columns
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_includes md, "calls_main"
    assert_includes md, "calls_agent"
  end

  def test_markdown_has_a_section_per_skill
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_includes md, "## plastic-auto"
  end

  def test_markdown_states_the_method
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_includes md, "## Method"
    assert_includes md, "history"
    assert_includes md, "cutoff"
  end

  def test_attribution_column_carries_its_caveat
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_match(/attribut\w+.*(time|caveat|invocation)/i, md)
  end

  def test_na_rows_render_na_and_the_mechanism
    mechanism_roster = [SkillCensus::Roster::Skill.new(name: "plastic-agent-advisor", user_invocable: false)]
    empty_history = SkillCensus::HistoryScanner::Result.new(record_count: 0, first_seen: nil, last_seen: nil,
                                                               typed: [], mentions: [], builtins: {},
                                                               self_generated: [], monthly: {})
    empty_transcript = SkillCensus::TranscriptScanner::Result.new(
      files_top: 0, files_subagent: 0, record_count: 0, unparsable_lines: 0,
      first_seen: nil, last_seen: nil, calls_main: [], calls_agent: [], other_skills: {},
      loads: [], attributed: {}, mentions: [], scripts: {}, agents: {},
      transcript_typed: [], self_generated: [],
      corroboration: SkillCensus::TranscriptScanner::Corroboration.new(matched: 0, disagreements: [])
    )
    built_na = SkillCensus::Tally.new(empty_history, empty_transcript, mechanism_roster).build
    md = SkillCensus::Report.markdown(built_na, cutoff: "2026-09-02")

    assert_includes md, "n/a"
    assert_includes md, "dispatched as the plastic-advisor"
  end

  def test_zero_counts_render_as_zero
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_match(/\|\s*0\s*\|/, md)
  end

  def test_markdown_lists_every_typed_event
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02", history_path: FIXTURE_HISTORY)

    assert_includes md, "/Users/z/app"
  end

  def test_markdown_has_builtin_other_skill_scripts_and_agents_tables
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_includes md, "Built-in"
    assert_includes md, "Other skill"
    assert_includes md, "Script"
    assert_includes md, "Agent"
  end

  def test_markdown_prints_the_history_versus_transcript_cross_check
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_includes md, "Cross-check"
  end

  def test_markdown_reports_self_generated_records
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    assert_includes md, "Self-generated"
  end

  def test_json_output_parses_with_skills_and_counters
    json_text = SkillCensus::Report.json(built, cutoff: "2026-09-02")
    data = JSON.parse(json_text)

    assert data.key?("skills")
    assert data.key?("history")
    assert data.key?("transcript")
  end

  def test_report_has_no_em_or_en_dash
    md = SkillCensus::Report.markdown(built, cutoff: "2026-09-02")

    refute_includes md, "—"
    refute_includes md, "–"
  end
end

# ---------------------------------------------------------------------------
# S8 - CLI
# ---------------------------------------------------------------------------
class SkillCensusCliTest < Minitest::Test
  def run_cli(*args)
    Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, CENSUS, *args)
  end

  def test_the_census_is_executable
    assert File.executable?(CENSUS), "bin/plastic-skill-census must be executable"
  end

  def test_cli_unknown_flag_exits_2
    _out, _err, status = run_cli("--nope")

    assert_equal 2, status.exitstatus
  end

  def test_cli_without_history_exits_2
    _out, _err, status = run_cli("--transcripts", FIXTURE_TRANSCRIPTS)

    assert_equal 2, status.exitstatus
  end

  def test_cli_without_transcripts_exits_2
    _out, _err, status = run_cli("--history", FIXTURE_HISTORY)

    assert_equal 2, status.exitstatus
  end

  def test_source_has_no_dir_home
    lib_source = File.read(File.join(ROOT, "bin", "lib", "skill_census.rb"))
    cli_source = File.read(CENSUS)

    refute_match(/Dir\.home/, lib_source)
    refute_match(/ENV\[.HOME.\]/, lib_source)
    refute_match(/Dir\.home/, cli_source)
    refute_match(/ENV\[.HOME.\]/, cli_source)
  end

  def test_cli_missing_dir_exits_1
    _out, _err, status = run_cli("--history", "/no/such/history.jsonl", "--transcripts", FIXTURE_TRANSCRIPTS)

    assert_equal 1, status.exitstatus
  end

  def test_cli_prints_markdown_report
    out, err, status = run_cli("--history", FIXTURE_HISTORY, "--transcripts", FIXTURE_TRANSCRIPTS, "--skills-dir", FIXTURE_SKILLS)

    assert_equal 0, status.exitstatus, err
    assert_includes out, "# Plastic skill usage census"
  end

  def test_cli_writes_out_file
    Dir.mktmpdir("skill-census-cli") do |dir|
      out_path = File.join(dir, "report.md")
      _out, err, status = run_cli("--history", FIXTURE_HISTORY, "--transcripts", FIXTURE_TRANSCRIPTS,
                                   "--skills-dir", FIXTURE_SKILLS, "--out", out_path)

      assert_equal 0, status.exitstatus, err
      assert File.file?(out_path)
      assert_includes File.read(out_path), "# Plastic skill usage census"
    end
  end

  def test_cli_json_format
    out, err, status = run_cli("--history", FIXTURE_HISTORY, "--transcripts", FIXTURE_TRANSCRIPTS,
                                "--skills-dir", FIXTURE_SKILLS, "--format", "json")

    assert_equal 0, status.exitstatus, err
    assert JSON.parse(out).key?("skills")
  end

  def test_cli_cutoff_flag_changes_the_count
    out_before, _err1, _s1 = run_cli("--history", FIXTURE_HISTORY, "--transcripts", FIXTURE_TRANSCRIPTS,
                                      "--skills-dir", FIXTURE_SKILLS, "--cutoff", "2026-06-01")
    out_after, _err2, _s2 = run_cli("--history", FIXTURE_HISTORY, "--transcripts", FIXTURE_TRANSCRIPTS,
                                     "--skills-dir", FIXTURE_SKILLS, "--cutoff", "2026-09-02")

    refute_equal out_before, out_after
  end

  def test_report_header_names_the_given_paths
    out, err, status = run_cli("--history", FIXTURE_HISTORY, "--transcripts", FIXTURE_TRANSCRIPTS, "--skills-dir", FIXTURE_SKILLS)

    assert_equal 0, status.exitstatus, err
    assert_includes out, FIXTURE_HISTORY
    assert_includes out, FIXTURE_TRANSCRIPTS
  end
end
