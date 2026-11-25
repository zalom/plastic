# frozen_string_literal: true

module CommandReference
  # Why a call moves from one workflow to the next, in the words of the outcomes that lead there.
  class Reasons
    def initialize(page)
      @page = page
      @flows = page.flows.to_h { |flow| [flow.key, flow] }
    end

    def of(edge) = edge.because(@flows)

    def into(key) = @page.edges.select { |edge| edge.to == key }.map { |edge| of(edge) }.uniq.join(" or ")
  end
end
