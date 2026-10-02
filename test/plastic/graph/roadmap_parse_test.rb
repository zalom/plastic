# frozen_string_literal: true

require_relative "../../test_helper"

class RoadmapParseTest < Plastic::TestCase
  def parse(text) = Plastic::Graph::RoadmapParse.call(text, path: "roadmaps/r1.md")

  def test_a_status_followed_by_more_words_still_reads
    result = parse("# R1\n\n## Batches\n\n### Batch 1 — First\n- [ ] 7 Build it — queued, deferred to later\n")

    item = sole(result.items)

    assert_equal %w[7 queued Build\ it], [item.item, item.status, item.title]
    assert_empty result.problems
  end

  def test_an_indented_bullet_continues_the_log_line_above_it
    result = parse("# R1\n\n## Log\n- 2026-09-01 Opened the roadmap\n  - with a sub-point\n- 2026-09-02 Closed it\n")

    assert_equal 2, result.log.size
    assert_includes result.log.first.text, "with a sub-point"
    assert_empty result.problems
  end
end
