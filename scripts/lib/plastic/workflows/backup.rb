# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Packs home.db and every store's three databases into one gzipped tar
    # under backups/, and writes the row that names it.
    class Backup < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :name, :files, :bytes

      step "write the archive", done: ->(context) { !context.name.nil? } do |context|
        row = context.work.backup
        context[:name] = row.fetch(:name)
        context[:files] = row.fetch(:files)
        context[:bytes] = row.fetch(:bytes)
      end

      read "say what was packed" do |context|
        files = context.files
        context.print("backup: #{context.name}, #{files} #{(files == 1) ? "database" : "databases"}, #{context.bytes} bytes")
      end

      outcome :done, offers: "plastic backup list", because: "backup %{name} is on disk"
    end
  end
end
