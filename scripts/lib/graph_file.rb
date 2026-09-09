# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_edges"
require_relative "atomic_write"

# GraphFile (intent 334, n2): the four graph.md sections (## Goal,
# ## Decisions, ## Graph, ## Status), the verify:-none directive, and the two
# writers - write_status and append_decision. Both writers refuse a cyclic
# graph and both go through AtomicWrite (fold D19r). Fence-aware everywhere a
# heading is located, so a fenced example carrying a fake "## " line never
# splits or ends a real section (fold A8's sibling concern, applied to
# section boundaries rather than edge lines).
module GraphFile
  module_function

  FENCE_LINE_RE = /\A\s{0,3}(`{3,}|~{3,})/.freeze
  DIRECTIVE_RE = /\A-\s*verify:\s*none(?:\s+reason=(.*))?\z/i.freeze
  SECTIONS = %w[## Goal ## Decisions ## Graph ## Status].freeze

  # {ok:, goal:, decisions:, graph:, status:, verify:, errors:}. `graph` is
  # GraphEdges.parse's own Result hash, over the Graph section text with any
  # verify:-none directive line stripped first (fold A8). A missing ## Graph
  # section, or one that declares no nodes, is an error naming which (fold
  # A10).
  def parse(path)
    return failure(["graph file not found: #{path}"]) unless File.exist?(path)

    content = File.read(path)
    goal = section_body(content, "## Goal")
    decisions = section_body(content, "## Decisions")
    graph_section = section_body(content, "## Graph")
    status = section_body(content, "## Status")

    errors = []
    if graph_section.nil?
      errors << "missing ## Graph section"
      return { ok: false, goal: goal, decisions: decisions, graph: nil, status: status, verify: nil, errors: errors }
    end

    directive, directive_errors, remaining = extract_verify_directive(graph_section)
    errors.concat(directive_errors)

    parsed_graph = GraphEdges.parse(remaining)
    errors.concat(parsed_graph[:errors])
    errors << "## Graph declares no nodes" if parsed_graph[:nodes].empty?

    { ok: errors.empty?, goal: goal, decisions: decisions, graph: parsed_graph, status: status, verify: directive, errors: errors }
  end

  def failure(errors)
    { ok: false, goal: nil, decisions: nil, graph: nil, status: nil, verify: nil, errors: errors }
  end

  # Rows shaped {node:, state:, detail:} parsed back from the ## Status
  # table (D8r's round-trip guarantee).
  def status_rows(path)
    parsed = parse(path)
    rows_from_table(parsed[:status])
  end

  # Replace the whole ## Status section with rows, creating the section if
  # absent. Refuses a cyclic graph (D8r); goes through AtomicWrite (D19r).
  def write_status(path, rows, renamer: File.method(:rename))
    guard = refuse_if_cyclic(path)
    return guard if guard

    content = File.read(path)
    new_content = replace_or_append_section(content, "## Status", render_status_table(rows))
    AtomicWrite.write(path, new_content, renamer: renamer)
    { ok: true, errors: [] }
  end

  # Append one answered decision as a list item to ## Decisions (C26),
  # leaving every other section byte-identical. Refuses a cyclic graph.
  def append_decision(path, text, renamer: File.method(:rename))
    guard = refuse_if_cyclic(path)
    return guard if guard

    content = File.read(path)
    bounds = section_bounds(content, "## Decisions")
    return { ok: false, errors: ["missing ## Decisions section"] } unless bounds

    start_idx, end_idx = bounds
    heading_line_end = line_end(content, start_idx)
    body = content[heading_line_end...end_idx]
    trimmed = body.rstrip
    trailing = body[trimmed.length..]
    new_body = trimmed.empty? ? "- #{text}#{trailing}" : "#{trimmed}\n- #{text}#{trailing}"
    new_content = content[0...heading_line_end] + new_body + content[end_idx..]
    AtomicWrite.write(path, new_content, renamer: renamer)
    { ok: true, errors: [] }
  end

  def refuse_if_cyclic(path)
    parsed = parse(path)
    return { ok: false, errors: parsed[:errors] } if parsed[:graph].nil?

    cyc = GraphEdges.cycle(parsed[:graph][:edges])
    return { ok: false, errors: ["cyclic graph, refusing to write: #{cyc.join(' > ')}"] } if cyc

    nil
  end

  # --- verify: none directive --------------------------------------------------

  def extract_verify_directive(graph_section)
    return [nil, [], graph_section] if graph_section.nil?

    reason = nil
    present = false
    errors = []
    remaining_lines = []

    graph_section.each_line do |line|
      stripped = line.strip
      m = stripped.match(DIRECTIVE_RE)
      if m
        present = true
        captured = m[1].to_s.strip
        if captured.empty?
          errors << "verify: none requires reason=<text>: #{stripped.inspect}"
        else
          reason = captured
        end
      else
        remaining_lines << line
      end
    end

    directive = present ? { reason: reason } : nil
    [directive, errors, remaining_lines.join]
  end

  # --- fence-aware section location ---------------------------------------------

  def each_fence_line(text)
    return enum_for(:each_fence_line, text) unless block_given?

    marker = nil
    text.to_s.each_line do |line|
      if marker
        yield line, true
        m = line.match(FENCE_LINE_RE)
        next unless m && m[1][0] == marker[0] && m[1].length >= marker[1]
        next unless line.sub(FENCE_LINE_RE, "").strip.empty?

        marker = nil
      else
        m = line.match(FENCE_LINE_RE)
        if m
          marker = [m[1][0], m[1].length]
          yield line, true
        else
          yield line, false
        end
      end
    end
  end

  # [start_of_heading_line, start_of_next_top_level_heading_or_EOF] byte
  # offsets for the FIRST line, outside any fence, whose stripped text
  # exactly equals heading_text. nil when no such line exists.
  def section_bounds(content, heading_text)
    offset = 0
    heading_start = nil

    each_fence_line(content) do |line, fenced|
      if !fenced && heading_start.nil? && line.strip == heading_text
        heading_start = offset
      elsif !fenced && heading_start && offset > heading_start && line.match?(/\A##[^#]/)
        return [heading_start, offset]
      end
      offset += line.length
    end

    heading_start ? [heading_start, offset] : nil
  end

  def section_body(content, heading_text)
    bounds = section_bounds(content, heading_text)
    return nil unless bounds

    start_idx, end_idx = bounds
    content[(line_end(content, start_idx))...end_idx].to_s
  end

  def line_end(content, start_idx)
    idx = content.index("\n", start_idx)
    idx ? idx + 1 : content.length
  end

  def replace_or_append_section(content, heading_text, body_text)
    rendered_body = body_text.to_s
    rendered_body += "\n" unless rendered_body.end_with?("\n")
    section = "#{heading_text}\n#{rendered_body}"

    bounds = section_bounds(content, heading_text)
    if bounds
      start_idx, end_idx = bounds
      tail = content[end_idx..].to_s
      section += "\n" unless tail.empty?
      content[0...start_idx] + section + tail
    else
      head = content.dup
      head += "\n" unless head.end_with?("\n")
      head += "\n" unless head.end_with?("\n\n")
      head + section
    end
  end

  # --- table rendering and reading -----------------------------------------------

  def render_status_table(rows)
    lines = ["| Node | State | Detail |", "| --- | --- | --- |"]
    rows.each { |r| lines << "| #{r[:node]} | #{r[:state]} | #{r[:detail]} |" }
    "#{lines.join("\n")}\n"
  end

  def rows_from_table(text)
    return [] if text.nil?

    lines = []
    each_fence_line(text) do |line, fenced|
      next if fenced

      stripped = line.strip
      lines << stripped if stripped.start_with?("|")
    end
    sep_idx = lines.index { |l| l.match?(/\A\|[\s:|-]+\|?\z/) }
    return [] unless sep_idx

    lines[(sep_idx + 1)..].map do |l|
      cells = l.split("|", -1).map(&:strip)[1..-2].to_a
      { node: cells[0], state: cells[1], detail: cells[2] }
    end
  end
end
