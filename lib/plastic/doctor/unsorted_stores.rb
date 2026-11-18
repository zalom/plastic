# frozen_string_literal: true

require_relative "check"
require_relative "../errors"
require_relative "../scope"
require_relative "../graph/knowledge/store_folder"
require_relative "../graph/knowledge/resources/sort_plan"

module Plastic
  module Doctor
    # Whether the files of one store sit in the resources layout. It reads the folder and writes nothing; the
    # repair is the command that sorts them.
    class UnsortedStores
      def self.checks(scope)
        slugs = [Scope::GLOBAL, *scope.projects.keys].uniq
        slugs.filter_map { |slug| new(scope.plastic_home, slug).check }
      end

      def initialize(home, slug)
        @slug = slug
        @folder = Graph::Knowledge::StoreFolder.new(File.join(home, "stores", slug))
      end

      def check
        return unless File.directory?(@folder.root)

        judged
      rescue Refused => error
        finding(error.message)
      end

      private

      def judged
        count = Graph::Knowledge::Resources::SortPlan.new(@folder).moves.size
        count.zero? ? Check.ok(label, "every file is in the resources layout") : finding("#{count} files are outside the resources layout")
      end

      def finding(text) = Check.finding(label, text, "plastic resources sort --store #{@slug}")

      def label = "resources #{@slug}:"
    end
  end
end
