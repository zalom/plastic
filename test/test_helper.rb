if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    skip "/test/"
    cover "{scripts,bin,tools}/**/*.rb"
  end
end

require "minitest/autorun"
require "fileutils"
require "tmpdir"
$LOAD_PATH.unshift File.expand_path("../scripts/lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../tools", __dir__)

module Plastic
  # The base class of every kernel test. Each test gets its own copy of a
  # home built once per process, the way Rails loads the schema once and
  # rolls each test back. A class picks a named home from test/fixtures/homes
  # with `fixtures`.
  #
  # The live command line's tests share this file, and its constants clash
  # with the kernel's. So the kernel and the helpers load when the first
  # kernel test class inherits from this one, not when the file loads.
  class TestCase < Minitest::Test
    HELPERS = File.expand_path("test_helpers", __dir__)

    def self.inherited(subclass)
      super
      TestCase.boot
    end

    def self.boot
      return if @booted

      @booted = true
      require "plastic"
      SQLite3::ForkSafety.suppress_warnings!
      require File.expand_path("fixtures/routines", __dir__)
      Dir[File.join(HELPERS, "*.rb")].each { |helper| require helper }
      include StoreHelper, CommandHelper, WorkflowHelper, DatabaseHelper
    end

    def self.fixtures(name = nil)
      @fixtures = name if name
      @fixtures || (superclass.respond_to?(:fixtures) ? superclass.fixtures : :empty)
    end

    def setup
      @template = Homes.template(self.class.fixtures)
      @home = @template.dir
      @plastic_home = File.join(@home, ".plastic")
      @template.begin
    end

    def teardown = @template.reset
  end
end
