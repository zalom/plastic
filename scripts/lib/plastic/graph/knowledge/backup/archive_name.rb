# frozen_string_literal: true

require_relative "../backup"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # The first free archive name for this second under backups/, so two
        # backups in the same second never share a name.
        module ArchiveName
          module_function

          def for(home)
            prefix = "plastic-#{Time.now.strftime("%Y%m%d-%H%M%S")}"
            "#{prefix}#{available_suffix(home, prefix)}.tar.gz"
          end

          def available_suffix(home, prefix)
            names = Dir.glob(File.join(home, "backups", "#{prefix}*.tar.gz")).map { |path| File.basename(path) }
            suffix_for((0..).find { |number| !names.include?("#{prefix}#{suffix_for(number)}.tar.gz") })
          end

          def suffix_for(number) = number.zero? ? "" : "-#{number}"
        end
      end
    end
  end
end
