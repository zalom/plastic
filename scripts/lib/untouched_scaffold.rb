# frozen_string_literal: true

require_relative "savepoint"
require_relative "backfill_intent"

# Finds an intent that is still exactly what new-intent created, so
# end-intent can refuse to close it as delivered.
#
# The rule is narrow so older intents still close. An intent is untouched
# only when all of these hold:
#
#   - spec.md, plan.md, checklist.md and outcome.md exist and are still
#     unedited placeholders, with no ticked checklist item;
#   - there is no action, node or graph file;
#   - savepoint.md holds only What lines;
#   - the code worktree, if there is one, has no changes.
#
# An older intent with missing files is never untouched.
module UntouchedScaffold
  module_function

  LIFECYCLE = %w[spec.md plan.md checklist.md outcome.md].freeze
  SCAFFOLD_LINE = /\A\S+\s+What\s/
  TICKED_ITEM = /^\s*- \[[xX]\] /

  def reason(intent_dir, templates: {}, worktree_changed: ->(_dir) { false })
    return nil unless placeholders_untouched?(intent_dir, templates)
    return nil if Savepoint.has_real_action?(intent_dir)
    return nil if File.exist?(File.join(intent_dir, "graph.md"))
    return nil unless scaffold_savepoint?(File.join(intent_dir, "savepoint.md"))
    return nil if worktree_changed.call(intent_dir)

    "spec.md, plan.md, checklist.md and outcome.md are still placeholders, " \
      "no action, node or graph was written, the savepoint records no work, " \
      "and the code worktree has no changes"
  end

  def placeholders_untouched?(intent_dir, templates)
    paths = LIFECYCLE.map { |rel| File.join(intent_dir, rel) }
    return false unless paths.all? { |path| File.exist?(path) && !Savepoint.stage_file_present?(path) }
    return false if File.read(File.join(intent_dir, "checklist.md")).match?(TICKED_ITEM)

    BackfillIntent.classify(intent_dir, templates: templates)[:edited].empty?
  end

  def scaffold_savepoint?(path)
    return false unless File.exist?(path)

    File.readlines(path).reject { |line| line.strip.empty? }.all? { |line| line.match?(SCAFFOLD_LINE) }
  end
end
