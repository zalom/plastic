# frozen_string_literal: true

require "fileutils"
require_relative "../schema"
require_relative "snapshot"
require_relative "store_files"
require_relative "database_copy"

module Plastic
  module Graph
    class DisposableCopy
      # The files of one home and one store, copied under another path, and
      # what the copy looked like when it was made. Every copied file gets
      # the epoch as its time, so a file written in the copy shows as changed
      # even when its bytes did not.
      class StoreTree
        EPOCH = Time.at(0)
        HOME_FILES = %w[origin_id config.yml projects.yml].freeze

        def initialize(home, copy, slug)
          @home = home
          @copy = copy
          @slug = slug
          @baseline = nil
        end

        def populate
          copy_all(StoreFiles.new(@home, @copy, @slug).tap(&:refuse_folder_links))
          @baseline = state
          self
        end

        def changes = Snapshot.differences(@baseline, state).map { |verb, rel| [verb, File.join(@home, rel)] }

        def self.copy_file(source, target)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(source, target)
          File.utime(EPOCH, EPOCH, target)
        end

        private

        def copy_all(files)
          FileUtils.mkdir_p(@copy)
          copy_home_files
          files.call
          DatabaseCopy.new(@home, @copy, @slug).call
        end

        def copy_home_files
          HOME_FILES.each do |name|
            source = File.join(@home, name)
            StoreTree.copy_file(source, File.join(@copy, name)) if File.file?(source)
          end
        end

        def state = Snapshot.of(@copy)
      end
    end
  end
end
