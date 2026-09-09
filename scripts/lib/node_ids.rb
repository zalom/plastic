# encoding: UTF-8
# frozen_string_literal: true

require_relative "node_file"
require_relative "graph_file"
require_relative "graph_edges"
require_relative "node_ledger"

# NodeIds (intent 335a): every node id one intent has EVER seen, gathered from
# the three places an id can appear, so NodeFile.mint_id can mint one past the
# highest and never reissue a deleted node's id.
#
# Why this exists as its own module rather than inside NodeFile: NodeFile is
# 334's deliberately dependency-free envelope reader (yaml and date only), and
# gathering needs the graph parsers and the ledger. It is not inside
# WorkGraphValidator either, because that module reports errors and minting is
# not validation.
#
# The rule this serves (335a D1, owner ruling 2026-09-09): a removed node still
# reserves its id. Deletion is not a ledger transition, so a reissued id would
# silently inherit the dead node's transition history, evidence included.
module NodeIds
  module_function

  # Every id seen in `intent_dir`, sorted and deduplicated. Each of the three
  # sources is guarded on its own (D5): an intent that has not started yet is
  # the ordinary case, not an error.
  #
  # The result deliberately OVER-reserves (D11). An id that no kind's grammar
  # matches costs nothing, because mint_id filters by prefix; a missed id costs
  # a false history.
  def taken(intent_dir)
    return [] unless intent_dir && File.directory?(intent_dir)

    (from_node_files(intent_dir) + from_graph(intent_dir) + from_ledger(intent_dir))
      .reject { |id| id.nil? || id.empty? }
      .uniq
      .sort
  end

  # Both the filename's id AND the envelope's `node:` (D7). A file can disagree
  # with its own name, and a file whose frontmatter will not parse yields no
  # envelope id at all, which is exactly when the filename is the only thing
  # standing between a corrupt node file and a reissued id.
  #
  # Plain glob (D8): a zero-byte or sentinel-marked node file still names a node
  # whose id is taken. Savepoint.has_real_files_in?'s filter answers a different
  # question (has this intent started) and is not reused here.
  def from_node_files(intent_dir)
    Dir.glob(File.join(intent_dir, "nodes", "*.md")).sort.flat_map do |path|
      [id_from_filename(path), NodeFile.parse(path)[:node]]
    end
  end

  # The id a node filename declares: the basename up to the "--" separator, so
  # both shapes 334 D11r ratifies reserve - the bare `n2.md` and the slugged
  # `n1--graph-edges.md` (D6). Taking the whole basename would reserve nothing
  # for every slugged file in the store, which is the dominant shape.
  def id_from_filename(path)
    File.basename(path, ".md").split("--", 2).first.to_s
  end

  # Declared plus targeted, from the `## Graph` section only (D9). The gatherer
  # inherits GraphEdges' looseness: it is not fence-aware, so an id inside a
  # fenced example is gathered. That over-reserves, which is the safe direction.
  #
  # `## Status` is NOT read (D10): it is a projection rendered from the ledger
  # and rewritten wholesale, so every id it can carry the ledger already carries.
  def from_graph(intent_dir)
    path = File.join(intent_dir, "graph.md")
    return [] unless File.exist?(path)

    section = GraphFile.section_body(File.read(path).scrub, "## Graph")
    return [] unless section

    GraphEdges.parse(section)[:nodes].to_a
  end

  # Subjects only, read through NodeLedger.entries, NEVER a token scan (D4).
  # A node id can sit inside an ordinary milestone's free text and does today:
  # intent 335's own ledger carries "ACTION_1 v2" inside a Review line, and 23
  # such tokens exist across the live store. NodeLedger.entries already owns the
  # two-space split and already keeps a torn line's subject, so this reuses that
  # seam rather than making a third copy of it.
  #
  # The literal `Intent` subject is dropped: it is an intent-scope line, not a
  # node, and no kind's grammar would match it anyway.
  def from_ledger(intent_dir)
    path = File.join(intent_dir, "savepoint.md")
    return [] unless File.exist?(path)

    NodeLedger.entries(path)
              .map { |entry| entry[:subject] }
              .reject { |subject| subject == Savepoint::INTENT_SUBJECT }
  end
end
