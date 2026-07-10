# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

require_relative "../scripts/doctor"

# Intent 110 - the section_structure and graph_i4_danglers doctor checks must
# route to the sanctioned 107 remedy: dispatch plastic-store-curating to relocate
# the item into the intent's revisions.md via move-and-record. doctor.rb stays
# read-only (emits fix_hint only). Hermetic temp homes, no eval, no ENV seam.
class DoctorRevisionsRemedyTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-revisions-remedy")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def global_store = File.join(@home, "store")

  def write_index(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# Index\n\n## Active\n\n## Future\n\n## Clusters\n\n" \
                     "## Abandoned\n\n## Completed\n\n## Relocated\n(none)\n")
  end

  def write_intent(id, sources: [], chain: [], extra_section: nil)
    dir = File.join(global_store, "#{id}--slug")
    FileUtils.mkdir_p(dir)
    fm = +"---\nid: \"#{id}\"\nintent: t\n"
    fm << "sources: #{sources.inspect}\nchain: #{chain.inspect}\n"
    fm << "created: 2026-06-01\nauthor: t\ntags: [t]\n---\n\n"
    fm << "## Intent\nb\n\n## Context\nc\n\n## Outcome\no\n\n## Insights\ni\n\n## Links\n- x\n"
    fm << "\n## #{extra_section}\nz\n" if extra_section
    File.write(File.join(dir, "#{id}--slug.md"), fm)
  end

  def doctor = Doctor.new(plastic_home: @home)

  def convention_check(name, scopes: nil)
    doctor.check_conventions(scopes: scopes).find { |c| c[:name] == name }
  end

  # An unsanctioned ## section makes section_structure a fixable warn whose
  # fix_hint names the curator + revisions.md move-and-record remedy.
  def test_unsanctioned_section_yields_curator_revisions_fix_hint
    write_index(File.join(@home, "INDEX.md"))
    write_intent("11", extra_section: "Scratchpad")

    check = convention_check("section_structure")
    refute_nil check
    assert_equal "warn", check[:status]
    assert_equal true, check[:fixable]
    assert check[:fix_hint], "expected a fix_hint on the section_structure warn"
    assert_includes check[:fix_hint], "revisions.md"
    assert_includes check[:fix_hint], "plastic-store-curating"
  end

  # A dangling chain/sources edge makes graph_i4_danglers a warn whose fix_hint
  # names the curator + revisions.md move-and-record remedy.
  def test_dangling_chain_ref_yields_curator_revisions_fix_hint
    write_index(File.join(@home, "INDEX.md"))
    write_intent("11", chain: ["999"]) # 999 does not exist -> dangler

    check = convention_check("graph_i4_danglers")
    refute_nil check
    assert_equal "warn", check[:status]
    assert_equal true, check[:fixable]
    assert check[:fix_hint], "expected a fix_hint on the graph_i4_danglers warn"
    assert_includes check[:fix_hint], "revisions.md"
    assert_includes check[:fix_hint], "plastic-store-curating"
  end

  # A clean store keeps both checks green (no false positives from the fixtures).
  def test_clean_store_keeps_checks_green
    write_index(File.join(@home, "INDEX.md"))
    write_intent("11", sources: [], chain: [])

    assert_equal "pass", convention_check("section_structure")[:status]
    assert_equal "pass", convention_check("graph_i4_danglers")[:status]
  end
end
