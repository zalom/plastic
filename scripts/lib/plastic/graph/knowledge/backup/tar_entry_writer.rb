# frozen_string_literal: true

require_relative "../backup"
require "rubygems/package"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Writes one tar entry, falling back to a GNU long-name header when the
        # name does not fit a USTAR header's 100-byte name or 155-byte prefix.
        class TarEntryWriter
          LONG_LINK_NAME = "././@LongLink"

          def initialize(tar, gz)
            @tar = tar
            @gz = gz
          end

          def add(name, bytes)
            @tar.add_file_simple(name, 0o644, bytes.bytesize) { |io| io.write(bytes) }
          rescue Gem::Package::TooLongFileName
            add_long(name, bytes)
          end

          private

          def add_long(name, bytes)
            write_header(name: LONG_LINK_NAME, size: name.bytesize + 1, typeflag: "L")
            write_padded("#{name}\0")
            write_header(name: name[0, 100], size: bytes.bytesize, typeflag: "0")
            write_padded(bytes)
          end

          def write_header(**fields)
            @gz.write(Gem::Package::TarHeader.new(mode: 0o644, prefix: "", mtime: 0, **fields).to_s)
          end

          def write_padded(bytes)
            @gz.write(bytes)
            remainder = (512 - (bytes.bytesize % 512)) % 512
            @gz.write("\0" * remainder)
          end
        end
      end
    end
  end
end
