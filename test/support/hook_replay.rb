# encoding: UTF-8
# frozen_string_literal: true

# HookReplay (intent 331a, T1) - the hermetic port of resources/probes/
# replay_hook.rb, now promoted to a production lib (intent 331e) because
# doctor's `display_hook_paints` check needs the exact same replay mechanics
# to test the INSTALLED launcher for real, not just tests. This file is a
# thin delegating shim so every existing `require_relative "support/
# hook_replay"` call site keeps working unchanged: the module, its methods,
# and their behavior all come from scripts/lib/hook_replay.rb.
require_relative "../../scripts/lib/hook_replay"
