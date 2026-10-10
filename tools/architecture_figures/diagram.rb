# frozen_string_literal: true

require_relative "canvas"
require_relative "shapes"
require_relative "diagram/route"
require_relative "diagram/rows"
require_relative "diagram/collisions"

module ArchitectureFigures
  # A figure built from named boxes and arrows between their sides. See docs/contributing/ARCHITECTURE.md.
  class Diagram
    # The file name, size, title and description of one figure.
    Meta = Data.define(:file, :width, :height, :title, :desc)
    TYPES = { box: Shapes::Box, cylinder: Shapes::Cylinder, zone: Shapes::Zone }.freeze
    DEFAULTS = { box: { kind: nil, lines: [], tone: :line, mono: false }, cylinder: { lines: [], tone: :code }, zone: {} }.freeze

    def self.parse(table) = Rows.parse(table)

    def self.shape(attrs)
      type = attrs.fetch(:type, :box)
      TYPES.fetch(type).new(**DEFAULTS.fetch(type), **attrs.except(:type))
    end

    def initialize(meta, boxes, arrows, extras = [])
      @meta = meta
      @boxes = boxes.transform_values { |attrs| Diagram.shape(attrs) }
      @arrows = arrows
      @extras = extras
    end

    def self.merge(diagrams) = diagrams.map(&:files).reduce(:merge)

    def files = { @meta.file => to_svg }

    def collisions = Collisions.new(arrows: arrows, obstacles: obstacles).list

    def to_svg
      canvas = Canvas.new(@meta.file, @meta.width, @meta.height, @meta.title, @meta.desc)
      (zones + others + arrows + @extras).each { |shape| canvas.add(shape) }
      canvas.to_svg
    end

    private

    def obstacles
      cards = others.to_h { |shape| [shape.name, shape.bounds] }
      zones.each_with_object(cards) { |zone, found| found["the title of #{zone.name}"] = zone.title_bounds }
    end

    def zones =@boxes.values.grep(Shapes::Zone)

    def others = @boxes.values.reject { |shape| shape.is_a?(Shapes::Zone) }

    def arrows = @arrows.map { |from, to, note, dashed| Shapes::Arrow.new(points: route(from, to), note: note || [], dashed: dashed || false) }

    def end_of(spec)
      name, side, fraction = spec.match(/\A(\w+)\.(\w+)(?:@([\d.]+))?\z/).captures
      edge = side.to_sym
      [@boxes.fetch(name.to_sym).anchor(edge, (fraction || 0.5).to_f), edge]
    end

    def route(from, to)
      (start, out), (finish, into) = [end_of(from), end_of(to)]
      Route.new(start: start, finish: finish, out: out, into: into).points
    end
  end
end
