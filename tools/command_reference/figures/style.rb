# frozen_string_literal: true

module CommandReference
  module Figures
    # The two sets of color tokens and the two font stacks.
    module Palette
      LIGHT = "--ink: #1f2530; --muted: #4f5866; --line: #7c8594; --paper: #e9e5dc; --card: #f4f1ea; " \
        "--code: #0d6b61; --code-bg: #d5e8e3; --agent: #9a5508; --agent-bg: #f1e2c7; " \
        "--refusal: #5b35b0; --refusal-bg: #e4dcf5; --failure: #a8261b; --failure-bg: #f4d9d4; --end: #2c4a7a; --end-bg: #d9e2f0;"
      DARK = "--ink: #e8e4da; --muted: #b3b9c3; --line: #8a93a2; --paper: #171a1f; --card: #20242b; " \
        "--code: #5cc4b4; --code-bg: #173a36; --agent: #e5a95a; --agent-bg: #3d2e17; " \
        "--refusal: #b59cf2; --refusal-bg: #2d2445; --failure: #f2958a; --failure-bg: #45211e; --end: #97b6e8; --end-bg: #1f2c42;"
      SANS = '"IBM Plex Sans", system-ui, -apple-system, "Segoe UI", sans-serif'
      MONO = '"IBM Plex Mono", ui-monospace, Menlo, Consolas, monospace'
    end

    # The CSS classes every drawing names; a standalone file spells the colors out.
    module Style
      CLASSES = <<~CSS
        .ground { fill: var(--paper); }
        .card { fill: var(--card); stroke: var(--line); stroke-width: 1; }
        .lane-code { fill: var(--code-bg); stroke: var(--code); stroke-width: 1.5; }
        .lane-agent { fill: var(--agent-bg); stroke: var(--agent); stroke-width: 1.5; }
        .stop-refusal { fill: var(--refusal-bg); stroke: var(--refusal); stroke-width: 1.2; }
        .stop-failure { fill: var(--failure-bg); stroke: var(--failure); stroke-width: 1.2; }
        .end { fill: var(--end-bg); stroke: var(--end); stroke-width: 1.2; }
        .wire { fill: none; stroke: var(--line); stroke-width: 1.4; }
        .wire-read { fill: none; stroke: var(--line); stroke-width: 1.4; stroke-dasharray: 5 3; }
        .wire-refusal { fill: none; stroke: var(--refusal); stroke-width: 1.2; stroke-dasharray: 4 3; }
        .wire-failure { fill: none; stroke: var(--failure); stroke-width: 1.2; stroke-dasharray: 4 3; }
        .head { fill: var(--line); }
        .t { fill: var(--ink); font: 12px #{Palette::SANS}; }
        .tb { fill: var(--ink); font: 600 13px #{Palette::SANS}; }
        .tm { fill: var(--ink); font: 11.5px #{Palette::MONO}; }
        .tag { font: 600 10px #{Palette::MONO}; letter-spacing: .06em; }
        .tag-code { fill: var(--code); } .tag-agent { fill: var(--agent); } .tag-refusal { fill: var(--refusal); }
        .tag-failure { fill: var(--failure); } .tag-end { fill: var(--end); } .tag-muted { fill: var(--muted); }
        .tm.tag-muted { font-size: 10.5px; }
        .db { fill: var(--end-bg); stroke: var(--end); stroke-width: 1.2; }
        .codebox { fill: var(--card); stroke: var(--line); stroke-width: 1; }
        .cx { fill: var(--ink); font: 12px #{Palette::MONO}; white-space: pre; }
        .cx-n { fill: var(--muted); font: 11px #{Palette::MONO}; }
        .cx-k { fill: var(--refusal); } .cx-s { fill: var(--agent); } .cx-y { fill: var(--code); }
        .cx-w { fill: var(--end); font-weight: 600; } .cx-t { fill: var(--failure); } .cx-c { fill: var(--muted); font-style: italic; }
        .badge { fill: var(--end); } .badge-t { fill: var(--paper); font: 600 11px #{Palette::MONO}; }
        .bracket { fill: none; stroke: var(--end); stroke-width: 1.4; }
        .term { fill: #16191e; stroke: var(--line); stroke-width: 1; }
        .term-t { fill: #e6e2d8; font: 12px #{Palette::MONO}; }
        .term-p { fill: #8fd18f; font: 12px #{Palette::MONO}; }
        .term-m { fill: #a3abb6; font: 12px #{Palette::MONO}; }
        .big { font: 700 36px #{Palette::MONO}; }
      CSS

      def self.spelled(tokens) = CLASSES.gsub(/var\((--[a-z-]+)\)/) { tokens[/#{Regexp.last_match(1)}: (#\h+)/, 1] }

      STANDALONE = "#{spelled(Palette::LIGHT)}\n@media (prefers-color-scheme: dark) {\n#{spelled(Palette::DARK)}}".freeze
    end
  end
end
