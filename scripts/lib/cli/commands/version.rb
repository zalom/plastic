# encoding: UTF-8
# frozen_string_literal: true

require "json"
require_relative "../command"

# `plastic version` - the version of the package this command came from, and the
# file it was read from. The VERSION file wins, because an installed copy
# carries one; the package manifest answers in a checkout, which has none.
module Plastic
  class CLI
    module Commands
      class Version < Command
        USAGE_LINE = "plastic version [--json]"

        SOURCES = ["VERSION", "package.json"].freeze

        def call
          path, number = found
          raise Failure, "no VERSION file and no package.json under #{package_root}" unless number

          @output.row("version", number)
          @output.row("source", path)
          @output.next_step("plastic status", because: "the command line works, so read the work next")
        end

        private

        def found
          SOURCES.each do |name|
            path = File.join(package_root, name)
            number = read(path)
            return [path, number] if number
          end
          [nil, nil]
        end

        def read(path)
          return nil unless File.file?(path)
          return File.read(path).strip unless path.end_with?(".json")

          number = JSON.parse(File.read(path))["version"]
          number&.to_s&.strip
        rescue JSON::ParserError
          nil
        end

        def package_root
          @package_root ||= @env["PLASTIC_PACKAGE_ROOT"] || File.expand_path("../../../..", __dir__)
        end
      end
    end
  end
end
