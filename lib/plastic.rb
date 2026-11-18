# frozen_string_literal: true

require_relative "plastic/clock"
require_relative "plastic/inflector"

# The root of the kernel. Every other file sits in a folder named after its
# namespace, under plastic/. This file only requires the kernel files.
module Plastic
end
