# frozen_string_literal: true

require_relative "../command"

module Plastic
  class CLI
    module Commands
      class Render < Command
        USAGE_LINE = "plastic render FILE"
        STYLE = File.expand_path("../../../../templates/render.css", __dir__)

        def call
          file = arguments.first or raise Usage, "FILE is the markdown file to render"
          raise Failure, "no file at #{file}" unless File.file?(file)

          require "rubygems"
          require "rdoc"
          body = RDoc::Markdown.parse(File.read(file, encoding: "UTF-8")).accept(RDoc::Markup::ToHtml.new)
          @output.raw("<!doctype html>\n<meta charset=\"utf-8\">\n<title>#{File.basename(file)}</title>\n" \
            "<style>\n#{File.read(STYLE)}</style>\n#{body}")
        end
      end
    end
  end
end
