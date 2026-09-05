# encoding: UTF-8
# frozen_string_literal: true

require_relative "report_screen"

# DashboardScreen (intent 331d) - the presentation half of the dashboard
# screen. scripts/dashboard.rb's screen_fields sources every fact (Active, In
# delivery, Delivered, Roadmap, Sessions, Changed, the two capped row lists)
# through the same helpers report-screen and DaySummary already use, turning
# a missing source into "not recorded" or "none" before it ever reaches
# here; this module carries no data-sourcing logic of its own, only layout,
# exactly like ReportScreen.render_state and IntentScreen.render do for
# their own screens.
module DashboardScreen
  module_function

  TEMPLATE_PATH = File.expand_path("../../templates/dashboard-screen.md", __dir__)

  def render(fields, template: nil)
    out = (template || File.read(TEMPLATE_PATH)).dup
    out = out.gsub("{{scope}}", fields.fetch(:scope).to_s)
    out = out.gsub("{{active}}", fields.fetch(:active).to_s)
    out = out.gsub("{{in_delivery}}", fields.fetch(:in_delivery).to_s)
    out = out.gsub("{{delivered}}", fields.fetch(:delivered).to_s)
    out = out.gsub("{{roadmap}}", fields.fetch(:roadmap).to_s)
    out = out.gsub("{{sessions}}", fields.fetch(:sessions).to_s)
    out = out.gsub("{{changed}}", fields.fetch(:changed).to_s)
    out = out.gsub("{{where_we_are.rows}}", where_we_are_rows(fields.fetch(:where_we_are, [])))
    out = out.gsub("{{where_we_go_next.rows}}", where_we_go_next_rows(fields.fetch(:where_we_go_next, [])))
    ReportScreen.fit_screen(out.gsub(/\n{3,}/, "\n\n"))
  end

  def where_we_are_rows(rows)
    rows.map { |r| "| #{r[:graph_id]} | #{r[:intent]} | #{r[:stage]} | #{r[:progress]} | #{r[:lead]} |" }.join("\n")
  end

  def where_we_go_next_rows(rows)
    rows.map { |r| "| #{r[:rank]} | #{r[:graph_id]} | #{r[:intent]} | #{r[:reason]} |" }.join("\n")
  end
end
