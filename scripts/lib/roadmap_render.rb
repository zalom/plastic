# encoding: UTF-8
# frozen_string_literal: true

require_relative "roadmap_graph"
require_relative "roadmap_savepoint"
require_relative "graph_file"
require_relative "graph_tree"
require_relative "atomic_write"

# RoadmapRender (intent 337, n3): renders "## Tree" and the roadmap's own
# grouping section (## Batches, or legacy ## Waves, owner ruling 145 -
# never renamed) from the RoadmapGraph model and writes both back through
# AtomicWrite, replacing exactly those two sections and leaving every other
# byte of the file alone.
#
# The regroup is surgical, never a rebuild from parsed fields (327's own
# lesson, merged at the 2026-09-10 plan review, rows 3.2/3.13/3.14): only
# entry lines RoadmapGraph itself recognized (the canonical checkbox +
# status grammar) ever move. A line the grammar cannot parse, and any prose
# a human wrote between batch headings, is untouched OUTPUT text - it is
# never even looked at, so it can never be lost. An id that already sits in
# its computed batch's heading block is never rewritten; only an id that
# needs to move is removed from its old block and appended, verbatim, to
# its new one. This is what makes a no-op render byte-identical (row 3.9)
# and a genuinely moved entry keep its own exact text (row 3.2).
module RoadmapRender
  module_function

  TREE_WIDTH = 100

  def write(path, renamer: File.method(:rename), dry_run: false, index_path: nil)
    original = File.read(path)
    resolved_index = index_path || default_index_path(path)

    analysis = RoadmapGraph.analyze(path, index_path: resolved_index)
    return refusal(analysis[:reason]) if analysis[:reason]
    return refusal("cyclic graph, refusing to render: #{analysis[:cycle].join(' > ')}") if analysis[:cycle]

    tree_result = render_tree(analysis)
    return refusal(tree_result[:error]) unless tree_result[:ok]

    content = GraphFile.replace_or_append_section(original, "## Tree", tree_result[:text])

    heading = RoadmapSavepoint.grouping_heading(original)
    return refusal("neither ## Batches nor ## Waves grouping heading found") unless heading

    heading_text = "## #{heading}"
    original_body = RoadmapSavepoint.grouping_section_body(original, path: path)
    regrouped = regroup(original_body, analysis)
    content = GraphFile.replace_or_append_section(content, heading_text, regrouped)

    if dry_run
      { ok: true, content: content, written: false, error: nil }
    else
      AtomicWrite.write(path, content, renamer: renamer)
      { ok: true, content: content, written: true, error: nil }
    end
  end

  def refusal(reason)
    { ok: false, content: nil, written: false, error: reason }
  end

  def default_index_path(roadmap_path)
    File.join(File.dirname(File.dirname(roadmap_path)), "INDEX.md")
  end

  def render_tree(analysis)
    labels = analysis[:entries].each_with_object({}) { |(id, e), h| h[id] = e[:title] }
    marks = {
      critical_path: analysis[:critical_paths] ? (analysis[:critical_paths][:critical_path] || []) : [],
      ready: analysis[:ready] || [],
    }
    GraphTree.render(edges: analysis[:edges], labels: labels, marks: marks, width: TREE_WIDTH)
  end

  # --- the surgical regroup ------------------------------------------------------

  ENTRY_ID_RE = /\A-\s*\[([ xX])\]\s+(\S+)\b/.freeze
  HEADING_RE = /\A###\s+/.freeze

  def regroup(body, analysis)
    preamble, blocks = split_into_blocks(body)

    real_batches = (analysis[:batches] || []).map { |layer| layer & analysis[:entries].keys }
    original_line_for = build_original_line_index(blocks)

    total = [blocks.length, real_batches.length].max
    rendered_blocks = (0...total).map do |i|
      block = blocks[i]
      computed_ids = real_batches[i] || []

      existing_ids = block ? block[:lines].filter_map { |l| entry_id(l) } : []
      removed = existing_ids - computed_ids
      added = computed_ids - existing_ids

      heading_line = block ? block[:heading] : "### Batch #{i + 1}\n"
      lines = block ? block[:lines].reject { |l| removed.include?(entry_id(l)) } : []
      lines += added.filter_map { |id| original_line_for[id] }

      heading_line + lines.join
    end

    # GraphFile.replace_or_append_section always adds its own single blank
    # line before a non-empty tail; a body that already ends in blank lines
    # (round-tripped from a previous render) would otherwise grow by one
    # blank line on every render (row 3.9's byte-identical requirement).
    (preamble.join + rendered_blocks.join).rstrip + "\n"
  end

  def entry_id(line)
    m = line.match(ENTRY_ID_RE)
    m && m[2]
  end

  def build_original_line_index(blocks)
    index = {}
    blocks.each do |block|
      block[:lines].each do |line|
        id = entry_id(line)
        index[id] ||= line if id
      end
    end
    index
  end

  # [preamble_lines, blocks] - blocks is [{heading:, lines: []}, ...] in file
  # order. Every original byte is accounted for: it lives either in the
  # preamble (before the first "### " heading) or in exactly one block's
  # heading/lines.
  def split_into_blocks(body)
    preamble = []
    blocks = []
    current = nil

    body.each_line do |line|
      if line.match?(HEADING_RE)
        blocks << current if current
        current = { heading: line, lines: [] }
      elsif current
        current[:lines] << line
      else
        preamble << line
      end
    end
    blocks << current if current

    [preamble, blocks]
  end
end
