# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require_relative "archive"
require_relative "https_fetch"
require_relative "ruby_archive"
require_relative "ruby_choice"
require_relative "ruby_stage"

module InstallerRelease
  # The pinned Rubies under <share>/rubies, one read-only folder each. A Ruby
  # is downloaded once, checked by size, SHA-256 and archive entries, started,
  # marked with its SHA-256, and only then renamed into place and made
  # read-only.
  class Rubies
    MARKER = ".plastic-ruby"
    LIMITS = Archive::Limits.new(bytes: 1024 * 1024 * 1024, entries: 50_000)
    GHCR = { "Authorization" => "Bearer QQ==" }.freeze
    SMOKE = 'require "openssl"; require "zlib"; require "psych"; print RUBY_VERSION'
    RUN = ->(ruby) { Open3.capture2e(ruby, "--disable-gems", "-rrbconfig", "-e", SMOKE).first }

    def self.remove(path)
      FileUtils.chmod_R("u+w", path, force: true)
      FileUtils.rm_rf(path)
    end

    def initialize(share, fetch: HttpsFetch.new, run: RUN)
      @root = File.join(share, "rubies")
      @fetch = fetch
      @run = run
    end

    def provide(pin)
      RubyFolder.of(root, pin).ruby { |folder| install(pin, folder) }
    end

    private

    attr_reader :root, :fetch, :run

    def install(pin, folder)
      raise VerificationError, "#{folder} holds another Ruby; remove that folder and run this again" if File.exist?(folder)

      FileUtils.mkdir_p(root)
      stage = Dir.mktmpdir(".stage-", root)
      RubyStage.new(stage, pin, run).unpack(download(pin, File.join(stage, "ruby.tar.gz")), folder)
    ensure
      self.class.remove(stage) if stage
    end

    def download(pin, path)
      url = pin.fetch("url")
      fetch.download(url, path, url.start_with?("https://ghcr.io/") ? GHCR : {})
      RubyArchive.new(path, pin).check
      path
    end
  end

  # The folder of one pinned Ruby, which holds that Ruby once its marker
  # names the pinned SHA-256.
  RubyFolder = Data.define(:path, :sha256) do
    def self.of(root, pin) = new(File.join(root, pin.fetch("key")), pin.fetch("sha256"))

    def ruby
      yield path unless marked?
      Ruby.new(File.join(path, "bin", "ruby"))
    end

    def marked?
      marker = File.join(path, Rubies::MARKER)
      File.file?(marker) && File.read(marker) == "#{sha256}\n"
    end
  end
end
