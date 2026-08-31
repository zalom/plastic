require "minitest/autorun"

# Intent 316a, O7/matrix row 50: skills/intent-continuing/SKILL.md is the only
# place that prints the intent screen. D13 requires the screen to be the
# first thing in the reply (chunk 0 is the only chance the MessageDisplay
# hook gets to recognize it); D14 requires the session's own "What this
# means" bullets to sit under it. This pins that the skill actually says so,
# plus one sentence on the substitution mechanism (fail-open, Claude Code
# only, nothing about how the screen prints ever changes).
class IntentContinuingSkillContentTest < Minitest::Test
  SKILL = File.expand_path("../skills/intent-continuing/SKILL.md", __dir__)

  def content
    @content ||= File.read(SKILL)
  end

  def test_screen_must_be_the_first_thing_in_the_reply
    assert_match(/first thing in the reply/i, content)
    assert_match(/nothing before it/i, content)
  end

  def test_what_this_means_bullets_are_written_under_the_screen
    assert_match(/\*\*What this means\*\*/, content)
    assert_match(/needs input:/, content)
  end

  def test_one_sentence_names_the_substitution_mechanism
    assert_match(/MessageDisplay/, content)
    assert_match(/fail-open/i, content)
    assert_match(/transcript.*keep|keep.*transcript/im, content)
  end
end
