# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_file"
require_relative "graph_edges"
require_relative "node_file"
require_relative "savepoint"
require_relative "work_graph_validator"

# ActionGraphShim (intent 342, G9): a read-time backward shim that presents
# any intent directory's actions/*.md as a node graph, in the record shape
# NodeFile.parse returns, so 336, 338 and 339 read a legacy intent through
# the same call they already use for an authored graph.md (spec.md D1-D18).
#
# Writes nothing, anywhere, ever (D1). An authored graph.md always wins over
# the synthetic chain (D3) - the reverse of 334's forward shim, which
# resolves content and prefers the older, richer source. This one resolves
# structure, where an authored graph is the only real graph.
module ActionGraphShim
  module_function

  FILES_NEGATION_RE = /\bnot\b|\bnever\b|\bavoid\b|don't/i.freeze
  BACKTICK_RE = /`([^`]+)`/.freeze
  PROVEN_BY_LABEL_RE = /\AS\d+\z/.freeze

  # :authored when graph.md exists, :actions when it does not but the intent
  # holds at least one real action file (D7's exact realness test, reused
  # rather than reimplemented so the shim can never disagree with
  # Savepoint.has_real_action? about whether an intent has work in it), :none
  # otherwise. A directory that does not exist returns :none and never
  # raises.
  def shape(intent_dir)
    return :none unless intent_dir && File.directory?(intent_dir.to_s)
    return :authored if File.exist?(File.join(intent_dir, "graph.md"))
    return :actions if Savepoint.has_real_files_in?("actions", intent_dir)

    :none
  end

  # The seven-key hash GraphFile.parse returns (ok:, goal:, decisions:,
  # graph:, status:, verify:, errors:), for whichever shape the directory
  # is in. On :authored this is literally GraphFile.parse, unmodified (D3).
  # On :actions the same hash is built from the action files, with goal:,
  # decisions: and status: nil (a 2024 action file was never asked for
  # them) and verify: a fixed reason so a trivial-bar check the caller may
  # run stays self-consistent. On :none it is GraphFile.parse's own
  # not-found failure, produced by delegating to it rather than
  # reformatting the message ourselves.
  def view(intent_dir)
    case shape(intent_dir)
    when :authored
      GraphFile.parse(File.join(intent_dir, "graph.md"))
    when :actions
      synth = synthetic_graph(intent_dir)
      {
        ok: synth[:errors].empty?,
        goal: nil,
        decisions: nil,
        graph: synth,
        status: nil,
        verify: { reason: "backward shim: legacy actions/ carry no verify node" },
        errors: synth[:errors],
      }
    else
      GraphFile.parse(File.join(intent_dir, "graph.md"))
    end
  end

  # Node records for either shape (D8), always carrying NodeFile.parse's own
  # key set (ok:, node:, kind:, files:, budget:, body:, errors:) plus
  # needs:, path: and proven_by:. [] on :none, never a raise on a real
  # directory.
  def nodes(intent_dir)
    case shape(intent_dir)
    when :authored
      authored_nodes(intent_dir)
    when :actions
      synthetic_nodes(intent_dir)
    else
      []
    end
  end

  # The needs targets for one node id, under either shape; [] for an id the
  # graph does not declare, and [] for a directory with no graph at all.
  def needs(intent_dir, node_id)
    graph = view(intent_dir)[:graph]
    return [] unless graph

    (graph[:edges] || {})[node_id] || []
  end

  # --- authored shape -------------------------------------------------------

  def authored_nodes(intent_dir)
    parsed = GraphFile.parse(File.join(intent_dir, "graph.md"))
    edges = parsed.dig(:graph, :edges) || {}

    Dir.glob(File.join(intent_dir, "nodes", "*.md")).sort.map do |path|
      nf = NodeFile.parse(path)
      nf.merge(
        needs: edges[nf[:node]] || [],
        path: path,
        proven_by: proven_by_labels(nf[:body].to_s)
      )
    end
  end

  # --- actions shape ----------------------------------------------------------

  # {nodes:, edges:, errors:} built directly over the minted chain, in the
  # same shape GraphEdges.parse returns, rather than rendering a "## Graph"
  # section and reparsing it.
  def synthetic_graph(intent_dir)
    ids = real_action_files(intent_dir).each_index.map { |i| "n#{i + 1}" }
    edges = {}
    ids.each_with_index { |id, i| edges[id] = i.zero? ? [] : [ids[i - 1]] }
    { nodes: ids, edges: edges, errors: [] }
  end

  def synthetic_nodes(intent_dir)
    files = real_action_files(intent_dir)
    files.each_with_index.map do |path, i|
      id = "n#{i + 1}"
      needs_targets = i.zero? ? [] : ["n#{i}"]
      begin
        text = File.read(path)
        {
          ok: true,
          node: id,
          kind: "work",
          files: files_section_paths(text),
          budget: nil,
          body: text,
          errors: [],
          needs: needs_targets,
          path: path,
          proven_by: proven_by_labels(text),
        }
      rescue StandardError => e
        {
          ok: false,
          node: id,
          kind: "work",
          files: [],
          budget: nil,
          body: nil,
          errors: ["could not read #{path}: #{e.message}"],
          needs: needs_targets,
          path: path,
          proven_by: [],
        }
      end
    end
  end

  # Real action files (File.file?, non-zero size, Savepoint.stage_file_present?
  # - D7's own three-part predicate, applied per file since has_real_files_in?
  # only answers true/false), ordered by the integer trailing the basename,
  # falling back to the basename itself so the key is a total order over
  # every basename shape the live store holds (D4).
  def real_action_files(intent_dir)
    Dir.glob(File.join(intent_dir.to_s, "actions", "*.md"))
       .select { |f| File.file?(f) && File.size(f) > 0 && Savepoint.stage_file_present?(f) }
       .sort_by { |f| sort_key(File.basename(f)) }
  end

  def sort_key(basename)
    m = basename.match(/\d+/)
    m ? [0, m[0].to_i, basename] : [1, 0, basename]
  end

  # The first heading whose leading token is "Files" (case-insensitively),
  # unless the heading text carries a negation, in which case it is not a
  # files section and the search continues (D10). Paths come out of that
  # section's BODY through extract_files_paths, which is itself
  # negation-aware and fence-aware (D17, D18). No qualifying heading gives
  # [] (D9).
  def files_section_paths(text)
    NodeFile.split_by_headings(text).each do |heading, section|
      next unless files_heading?(heading)

      return extract_files_paths(section.to_s)
    end
    []
  end

  # Fence-aware (D18) and negation-aware over the section body, not only
  # its heading (D17). D10 already stops a heading like "## Files you must
  # NOT change" from being read as a files section at all; this handles
  # the equally common case where a legitimate "## Files to touch" heading
  # is followed, inside the same section, by an out-of-bounds paragraph -
  # live on this intent's own dogfood fixture. A fenced block is dropped
  # before anything else runs, reusing NodeFile.each_fence_line rather than
  # a bare backtick scan, which is exactly what that helper exists to
  # prevent. Lines are scanned in document order; harvesting stops at the
  # first line carrying a negation, and only what precedes it is scanned
  # (D17's own wording), so an out-of-bounds clause never contributes a
  # path regardless of what follows it in the same section. Any span that
  # still holds a newline is rejected as a backstop: a path is never more
  # than one line.
  def extract_files_paths(section)
    kept = +""
    NodeFile.each_fence_line(section) do |line, fenced|
      next if fenced
      break if line.match?(FILES_NEGATION_RE)

      kept << line
    end
    kept.scan(BACKTICK_RE).flatten.reject { |s| s.include?("\n") }.uniq
  end

  def files_heading?(heading)
    stripped = heading.to_s.sub(/\A#+\s*/, "")
    first_token = stripped.split(/\s+/, 2).first.to_s.sub(/[^A-Za-z]+\z/, "")
    return false unless first_token.casecmp?("Files")

    !heading.to_s.match?(FILES_NEGATION_RE)
  end

  # The S\d+ tokens of a file's headings, in heading order, taking a
  # heading only when it owns at least one table data row (D5) - the same
  # table-owning rule WorkGraphValidator.has_valid_matrix? and ReportScreen
  # already apply, reused unmodified rather than adapted, so a prose
  # mention of an S-label never manufactures a Proven-by source (334's
  # post-execution review defect, in the other direction).
  def proven_by_labels(text)
    labels = []
    NodeFile.split_by_headings(text).each do |heading, section|
      next unless NodeFile.table_rows(section).any?

      WorkGraphValidator.heading_tokens(heading).each do |token|
        labels << token if token.match?(PROVEN_BY_LABEL_RE)
      end
    end
    labels
  end
end
