# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_file"
require_relative "graph_edges"
require_relative "node_ledger"
require_relative "intent_screen"

# NodeProgress (intent 337a, n1): the graph-era progress reader every report
# screen's node count calls instead of counting checklist.md items. A
# graph-era intent (graph.md AND nodes/ both present, D4) counts declared
# nodes - GraphFile.parse's ## Graph section, via GraphEdges - against
# NodeLedger.status's last-non-torn-line-per-subject state; a checklist-era
# intent gets nil, so its screen keeps counting checklist.md exactly as
# before. No second parser: every number here comes from GraphFile,
# GraphEdges or NodeLedger, never a hand-rolled scan.
#
# Pure: an explicit intent_dir and store_root: in, a fields hash or nil out;
# no ENV, no Dir.pwd, no raise across the boundary (a malformed record
# answers nil or zeroed fields, matrix row 1.16).
module NodeProgress
  module_function

  # Same keys IntentScreen.progress_fields returns, plus "progress.unit".
  # nil for a pre-graph intent (D4), so the caller keeps counting
  # checklist.md.
  def fields(intent_dir, store_root: nil)
    return nil unless graph_era?(intent_dir)

    nodes = declared_nodes(File.join(intent_dir, "graph.md"))
    return nil if nodes.nil? || nodes.empty?

    status = NodeLedger.status(File.join(intent_dir, "savepoint.md"))
    done = nodes.count { |n| status[n] == "done" }
    running = nodes.count { |n| status[n] == "running" }
    total = nodes.length

    inferred = done.zero? && delivered?(intent_dir, store_root)
    done = total if inferred

    {
      "progress.bar" => bar_for(done, total),
      "progress.done" => done.to_s,
      "progress.total" => total.to_s,
      "progress.note" => note_for(done, total, running, inferred),
      "progress.unit" => "nodes",
    }
  rescue StandardError
    nil
  end

  # D4: graph-era means graph.md AND nodes/ both exist.
  def graph_era?(intent_dir)
    File.exist?(File.join(intent_dir, "graph.md")) && Dir.exist?(File.join(intent_dir, "nodes"))
  end

  # Declared node ids from the ## Graph section (GraphFile/GraphEdges), never
  # from Dir over nodes/. nil for a missing ## Graph section or one that
  # declares no nodes (matrix row 1.16).
  def declared_nodes(graph_md_path)
    parsed = GraphFile.parse(graph_md_path)
    graph = parsed && parsed[:graph]
    return nil unless graph

    ids = graph[:nodes]
    ids.nil? || ids.empty? ? nil : ids
  end
  private_class_method :declared_nodes

  def bar_for(done, total)
    width = IntentScreen::BAR_WIDTH
    on = total.zero? ? 0 : (done * width) / total
    (IntentScreen::ON * on) + (IntentScreen::OFF * (width - on))
  end
  private_class_method :bar_for

  # D8's four exact note strings.
  def note_for(done, total, running, inferred)
    return "inferred: delivered before the node ledger" if inferred

    open = total - done
    return "all nodes done" if open.zero?
    return "#{open} nodes open, #{running} running" if running.positive?

    "#{open} nodes open"
  end
  private_class_method :note_for

  # Delivered, proven twice (the inferred fallback's precondition):
  # outcome.md on disk plus either an INDEX ## Completed line (store_root:
  # given) or a Done savepoint line (store_root: nil, the roadmap-entries
  # path that pays for no INDEX read per entry).
  def delivered?(intent_dir, store_root)
    return false unless File.exist?(File.join(intent_dir, "outcome.md"))

    store_root ? index_completed?(store_root, intent_id(intent_dir)) : done_savepoint_line?(intent_dir)
  end
  private_class_method :delivered?

  def intent_id(intent_dir)
    File.basename(intent_dir).split("--", 2).first
  end
  private_class_method :intent_id

  def index_completed?(store_root, id)
    path = File.join(store_root, "INDEX.md")
    return false unless File.exist?(path)

    content = File.read(path).scrub
    section = content[/^## Completed\n(.*?)(?=^## |\z)/m, 1]
    return false unless section

    section.each_line.any? { |line| line.strip.match?(/\A-\s*\[#{Regexp.escape(id)}(?=[\s\]])/) }
  end
  private_class_method :index_completed?

  def done_savepoint_line?(intent_dir)
    path = File.join(intent_dir, "savepoint.md")
    return false unless File.exist?(path)

    File.read(path).scrub.each_line.any? do |line|
      m = line.strip.match(IntentScreen::SAVEPOINT_RE)
      m && m[2] == "Done"
    end
  end
  private_class_method :done_savepoint_line?
end
