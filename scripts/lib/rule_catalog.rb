# encoding: UTF-8
# frozen_string_literal: true

# RuleCatalog - the one rule vocabulary in Plastic (intent 274), two curated named sets on two
# different axes so there is exactly one place to look up or register a rule name:
#
#   EXCLUDABLE_CHECKS - a doctor check `name` a per-store doctor-exclusions file may name. A
#   check name says WHICH DIAGNOSTIC FIRED. Two keys: savepoint_operational (274, spec D3) and
#   backfilled_complete (308). Most doctor checks have no exclusion mechanism at all; these two
#   are the ones whose gap can be a known, accepted fact on an old or migrated intent.
#
#   REVISION_RULES - the `[rule: <tag>]` vocabulary every revisions.md entry must carry
#   (scripts/lib/revisions_writer.rb). A tag says WHY an intent's files were structurally
#   edited. Most check names have no repair verb and most repair verbs are not checks, so this
#   is a genuinely separate axis, not an alias of EXCLUDABLE_CHECKS.
#
# REVISION_RULES is enforced by test only (test/rule_catalog_test.rb), never at
# RevisionsWriter runtime (spec D2): a receipt writer that refuses to write on an unrecognized
# tag is a guard that fails harder than the bug it would be catching, so append! keeps
# accepting any tag and the test catches an unregistered one before it ships.
#
# Zero requires (boot-safe): nothing here pulls in json/yaml/io, so this file can load from
# anywhere, including the SessionStart boot path, without cost.
#
# Packaging note (test/packaging_no_store_ids_test.rb): every token below is letter-leading,
# never digit-leading, so nothing here trips the Folgezettel-id-literal scan. Never put an
# intent id in this file.
module RuleCatalog
  module_function

  EXCLUDABLE_CHECKS = {
    "savepoint_operational" => "savepoint.md missing entirely, or missing its Done " \
                               "delivered|abandoned echo, on a terminal intent. Usually " \
                               "repairable via maintenance-run --tool rebuild-savepoint; " \
                               "excludable for the gaps 219 D6 forbids ever repairing.",
    "backfilled_complete" => "spec.md or plan.md missing or still the placeholder, or no real " \
                             "action file, on a terminal intent. Repairable via scaffold-intent " \
                             "backfill; excludable for an old intent whose record was never kept.",
  }.freeze

  # Measured from live store data across all eight stores, 2026-08-24 (spec D1).
  REVISION_RULES = [
    "links-projection",
    "broken-chain",
    "stray-file",
    "savepoint-operational-reconstruction",
    "unsanctioned-section",
    "missing-reciprocity",
    "misplaced-content",
    "missing-required-frontmatter",
    "savepoint-truthfulness",
    "restored-to-v1",
    "relocation",
    "graph-rebuild",
    "dangling-ref",
  ].freeze

  def excludable_check?(name)
    EXCLUDABLE_CHECKS.key?(name)
  end

  def revision_rule?(tag)
    REVISION_RULES.include?(tag)
  end
end
