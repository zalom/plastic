require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"
require_relative "../scripts/lib/bridge"

# Tests for session resolution, derived keys, write guards, intent-dir discovery,
# and /tmp bridge discovery added in intent 52 (session-id-less bridge).
class BridgeResolveTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("bridge-resolve-store")
    @intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    @saved_env = ENV["CLAUDE_SESSION_ID"]
  end

  def teardown
    FileUtils.rm_rf(@store)
    if @saved_env.nil?
      ENV.delete("CLAUDE_SESSION_ID")
    else
      ENV["CLAUDE_SESSION_ID"] = @saved_env
    end
  end

  # --- derive_key ------------------------------------------------------------

  def test_derive_key_is_deterministic_and_prefixed
    k1 = Bridge.derive_key(@store, "52")
    k2 = Bridge.derive_key(@store, "52")
    assert_equal k1, k2
    assert k1.start_with?("auto-")
    expected = "auto-" + Digest::SHA256.hexdigest("#{@store}/52")[0, 10]
    assert_equal expected, k1
  end

  def test_derive_key_differs_per_intent
    refute_equal Bridge.derive_key(@store, "52"), Bridge.derive_key(@store, "53")
  end

  # --- resolve_session -------------------------------------------------------

  def test_resolve_session_prefers_explicit
    ENV["CLAUDE_SESSION_ID"] = "from-env"
    assert_equal "explicit-id", Bridge.resolve_session("explicit-id", intent_id: "52", store: @store)
  end

  def test_resolve_session_falls_back_to_env
    ENV["CLAUDE_SESSION_ID"] = "from-env"
    assert_equal "from-env", Bridge.resolve_session(nil, intent_id: "52", store: @store)
  end

  def test_resolve_session_falls_back_to_derived_key
    ENV.delete("CLAUDE_SESSION_ID")
    assert_equal Bridge.derive_key(@store, "52"),
                 Bridge.resolve_session(nil, intent_id: "52", store: @store)
  end

  def test_resolve_session_treats_whitespace_as_empty
    ENV["CLAUDE_SESSION_ID"] = "   "
    assert_equal Bridge.derive_key(@store, "52"),
                 Bridge.resolve_session("  ", intent_id: "52", store: @store)
  end

  def test_resolve_session_never_empty
    ENV.delete("CLAUDE_SESSION_ID")
    refute_nil Bridge.resolve_session(nil, intent_id: "52", store: @store)
    refute_empty Bridge.resolve_session("", intent_id: "52", store: @store)
  end

  # --- write guard -----------------------------------------------------------

  def test_write_raises_on_empty_session
    assert_raises(ArgumentError) { Bridge.write(nil, {}) }
    assert_raises(ArgumentError) { Bridge.write("", {}) }
    assert_raises(ArgumentError) { Bridge.write("   ", {}) }
  end

  # --- intent_dir_for --------------------------------------------------------

  def test_intent_dir_for_finds_ancestor_store_dir
    file = File.join(@store, "52--demo", "spec.md")
    # The store dir name must match /store/<id>--<slug>. Build a realistic tree.
    real_store = File.join(@store, "store")
    intent = File.join(real_store, "52--demo")
    FileUtils.mkdir_p(File.join(intent, "actions"))
    target = File.join(intent, "actions", "x.md")
    assert_equal intent, Bridge.intent_dir_for(target)
  end

  def test_intent_dir_for_returns_nil_outside_store
    file = File.join(@store, "random", "file.rb")
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "x")
    assert_nil Bridge.intent_dir_for(file)
  end

  # --- bridge_valid? ---------------------------------------------------------

  def test_bridge_valid_true_for_well_formed
    assert Bridge.bridge_valid?({ "session" => "s", "intent" => { "id" => "52" } })
  end

  def test_bridge_valid_false_cases
    refute Bridge.bridge_valid?(nil)
    refute Bridge.bridge_valid?("string")
    refute Bridge.bridge_valid?({ "session" => "", "intent" => {} })
    refute Bridge.bridge_valid?({ "session" => "s" })
    refute Bridge.bridge_valid?({ "session" => "s", "intent" => "x" })
  end

  # --- discover_bridge -------------------------------------------------------

  def write_tmp_bridge(tmp, name, data)
    File.write(File.join(tmp, name), JSON.generate(data))
  end

  def valid_bridge(session:, store:, auto: false)
    {
      "session" => session,
      "intent" => { "id" => "52", "dir" => "52--demo", "store" => store, "name" => "demo" },
      "build" => { "auto" => auto },
    }
  end

  def test_discover_prefers_auto_bridge
    Dir.mktmpdir("tmp-bridges") do |tmp|
      write_tmp_bridge(tmp, "plastic-a.json", valid_bridge(session: "a", store: @store, auto: false))
      sleep 0.01
      write_tmp_bridge(tmp, "plastic-b.json", valid_bridge(session: "b", store: @store, auto: true))
      found = Bridge.discover_bridge(session: nil, cwd: @store, tmp: tmp)
      assert_equal "b", found["session"]
    end
  end

  def test_discover_skips_invalid_and_tmp_files
    Dir.mktmpdir("tmp-bridges") do |tmp|
      File.write(File.join(tmp, "plastic-bad.json"), "{ not json")
      File.write(File.join(tmp, "plastic-x.json.tmp"), JSON.generate(valid_bridge(session: "x", store: @store)))
      write_tmp_bridge(tmp, "plastic-good.json", valid_bridge(session: "good", store: @store))
      found = Bridge.discover_bridge(session: nil, cwd: @store, tmp: tmp)
      assert_equal "good", found["session"]
    end
  end

  def test_discover_prefers_cwd_matching_store
    Dir.mktmpdir("tmp-bridges") do |tmp|
      other_store = File.join(@store, "other")
      FileUtils.mkdir_p(other_store)
      write_tmp_bridge(tmp, "plastic-other.json", valid_bridge(session: "other", store: other_store, auto: true))
      sleep 0.01
      write_tmp_bridge(tmp, "plastic-mine.json", valid_bridge(session: "mine", store: @store, auto: true))
      found = Bridge.discover_bridge(session: nil, cwd: @store, tmp: tmp)
      assert_equal "mine", found["session"]
    end
  end

  def test_discover_returns_nil_when_no_candidates
    Dir.mktmpdir("tmp-bridges") do |tmp|
      assert_nil Bridge.discover_bridge(session: nil, cwd: @store, tmp: tmp)
    end
  end

  def test_discover_tie_breaks_by_newest_mtime
    Dir.mktmpdir("tmp-bridges") do |tmp|
      write_tmp_bridge(tmp, "plastic-old.json", valid_bridge(session: "old", store: @store, auto: true))
      sleep 0.02
      write_tmp_bridge(tmp, "plastic-new.json", valid_bridge(session: "new", store: @store, auto: true))
      found = Bridge.discover_bridge(session: nil, cwd: @store, tmp: tmp)
      assert_equal "new", found["session"]
    end
  end
end
