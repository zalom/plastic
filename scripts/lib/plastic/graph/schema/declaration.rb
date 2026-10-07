# frozen_string_literal: true

module Plastic
  module Graph
    module SchemaCatalog
      # One table declared in one line: its key columns, a bar, then each
      # column as name:type, where a bare name is TEXT.
      module Declaration
        def self.parse(line)
          key, columns = line.split("|").map(&:split)
          [key.map(&:to_sym), columns.to_h { |column| typed(column) }]
        end

        def self.typed(column)
          name, type = column.split(":")
          [name.to_sym, (type || "text").to_sym]
        end
      end
    end
  end
end
