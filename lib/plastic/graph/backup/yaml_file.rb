# frozen_string_literal: true

require "yaml"

module Plastic
  module Graph
    module Backup
      # Reads the mapping a YAML file holds. A missing file, an empty one, a plain string or text that does not parse is no record.
      module YamlFile
        def self.hash(file)
          found = YAML.safe_load_file(file) if File.file?(file)
          found.is_a?(Hash) ? found : {}
        rescue Psych::Exception
          {}
        end
      end
    end
  end
end
