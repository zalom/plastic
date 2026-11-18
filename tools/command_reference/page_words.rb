# frozen_string_literal: true

module CommandReference
  # The words one page lacks, one line each, every line led by the page's words.
  class PageWords
    def initialize(page)
      @page = page
      @flows = page.flows
    end

    def lines = [*flow_lines, *ChangeWords.new(@page, @flows).lines].map { |line| "#{@page.words}: #{line}" }

    private

    def flow_lines = [*several(SummaryLack), *several(OutcomeLack), *lacks(GateLack), *lacks(StepLack), *lacks(EndLack)].map(&:line)

    def several(lack) = (@flows.size > 1) ? lacks(lack) : []

    def lacks(lack) = lack.among(@flows).select(&:lacking?)
  end
end
