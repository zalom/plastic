if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    skip "/test/"
    cover "{scripts,bin,tools}/**/*.rb"
  end
end

require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../scripts/lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../tools", __dir__)
