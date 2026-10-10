# frozen_string_literal: true

module CommandReference
  # What one command is made of: its files, its workflows and the call it writes itself.
  Reach = Data.define(:kind, :files, :flows, :own_call) do
    def hook? = kind == :hook

    def reachable(file) = reaches.fetch(file, nil)

    def reaches = own_call ? { own_call.file => own_call.reachable } : {}

    def raising? = flows.any?(&:raising?)

    def endings(source, rescued)
      scans = files.map { |file| FileEndings.new(source, file, only: reachable(file)) }
      [*flows.flat_map(&:endings), *rescued, *file_endings(scans), *hook_endings(scans)]
    end

    def file_endings(scans) = hook? ? [] : scans.flat_map(&:call)

    def hook_endings(scans) = hook? ? [own_call.responds, *scans.flat_map(&:decisions)] : []

    def scanned_files = [*files, *flows.flat_map(&:files)].uniq
  end
end
