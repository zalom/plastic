# encoding: UTF-8
# frozen_string_literal: true

require_relative "qmd_sync"

# PowerTools — detect-then-degrade harness for Plastic's optional power-tools
# (intent 66b; demoted to recommendations in intent 108, D8). It owns
# deterministic detection of each tool and builds a RECOMMENDATION string for
# whichever tools are present, so the agent is reminded (not obliged) to prefer
# them: QMD for finding intents, Serena for code navigation.
#
# Strictly detect-then-degrade: a tool that is absent contributes nothing, and
# `mandate` returns nil when no tool is present. Nothing here installs anything.
#
# Pure and dependency-injected: every detection runs through an injected callable
# or keyword probe (PATH scan / `.serena` marker walk), so the whole module is
# unit-testable with no real binaries, no network, and no global/ENV state.
module PowerTools
  module_function

  # True when QMD is present. Reuses QmdSync.detect (PATH probe), injectable.
  def qmd?(detector: QmdSync.method(:detect))
    !!detector.call
  end

  # True when Serena is present: a `.serena` directory exists in cwd or any
  # ancestor, OR `serena` is resolvable on PATH. Both probes are injectable so
  # tests do not depend on the host having Serena installed.
  def serena?(cwd:, path_probe: method(:which_serena), marker_finder: method(:serena_marker?))
    return true if marker_finder.call(cwd)
    !!path_probe.call
  end

  # True when `serena` is an executable on PATH. Mirrors QmdSync.which_qmd.
  def which_serena
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
      candidate = File.join(dir, "serena")
      File.file?(candidate) && File.executable?(candidate)
    end
  end

  # Walk up from cwd to the filesystem root, returning true if any level holds a
  # `.serena` directory.
  def serena_marker?(cwd)
    dir = File.expand_path(cwd)
    loop do
      return true if Dir.exist?(File.join(dir, ".serena"))
      parent = File.dirname(dir)
      break if parent == dir
      dir = parent
    end
    false
  end

  # Recommendation text for whichever tools are present, joined by newlines, or
  # nil when none are. One recommendation line per present tool.
  def mandate(cwd:, qmd_detector: QmdSync.method(:detect), serena_detector: nil)
    lines = []

    if qmd?(detector: qmd_detector)
      lines << "QMD is available: prefer `qmd search` / `qmd query` over the " \
               "`plastic-*` collections to check for existing or related intents " \
               "before treating work as new."
    end

    serena_present = serena_detector ? !!serena_detector.call : serena?(cwd: cwd)
    if serena_present
      lines << "Serena is available: prefer its symbolic tools (find_symbol / " \
               "get_symbols_overview / find_referencing_symbols) for code navigation."
    end

    return nil if lines.empty?
    lines.join("\n")
  end
end
