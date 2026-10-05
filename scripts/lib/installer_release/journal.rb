# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "home_snapshot"
require_relative "pointer"

module InstallerRelease
  # What an activation needs to undo itself: the pointer targets, the
  # installed releases and a snapshot of the managed home. The state file
  # is written last, so a journal without one recorded nothing to restore.
  # A journal left behind by a stopped installer is restored by the next.
  class Journal
    POINTERS = %w[active previous].freeze

    def initialize(home, releases, paths)
      @home = home
      @releases = releases
      @root = File.join(home, "activation")
      @snapshot = HomeSnapshot.new(File.join(root, "home"), paths)
    end

    def open
      discard
      state = { "pointers" => POINTERS.to_h { |name| [name, pointer(name).target] }, "releases" => releases.versions,
                "home" => snapshot.take }
      write_state(state)
    end

    def restore
      state = read_state
      undo(state) if state
      discard
    end

    def recover = File.directory?(root) && restore

    def discard = FileUtils.rm_rf(root)

    private

    attr_reader :home, :releases, :root, :snapshot

    def state_path = File.join(root, "state.json")

    def pointer(name) = Pointer.new(File.join(home, name))

    def write_state(state)
      File.write("#{state_path}.new", JSON.generate(state))
      File.rename("#{state_path}.new", state_path)
    end

    def read_state = File.file?(state_path) ? JSON.parse(File.read(state_path)) : nil

    def undo(state)
      snapshot.put_back(state.fetch("home"))
      state.fetch("pointers").each { |name, target| reset_pointer(name, target) }
      (releases.versions - state.fetch("releases")).each { |version| FileUtils.rm_rf(releases.path(version)) }
    end

    def reset_pointer(name, target)
      target ? pointer(name).point_to(target) : FileUtils.rm_f(File.join(home, name))
    end
  end
end
