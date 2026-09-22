# encoding: UTF-8
# frozen_string_literal: true

require_relative "../screen_paint"

# Intent 331c (D7): the roadmap screen kinds. A new screen kind is a file, never a diff to
# screen_paint.rb (331a's registry, D6): registers `:roadmap_plan`, `:roadmap_state`, and
# `:roadmap_delivered`, openers that are strict subsets of the shipped intent/delivered openers
# (`## ▶ ... · roadmap · plan`, `## ▶ ... · roadmap`, `## ✔ ... · roadmap · delivered`), exactly
# as 331a's five shipped kinds already overlap each other. No `paint:` lambda is supplied: the
# palette stays IntentScreenAnsi's shared pipeline (the 318 ceiling) - screen_paint.rb's body is
# not touched by this file.
ScreenPaint.register(:roadmap_plan, opener: /\A## ▶ .+ · roadmap · plan\z/)
ScreenPaint.register(:roadmap_state, opener: /\A## ▶ .+ · roadmap\z/)
ScreenPaint.register(:roadmap_delivered, opener: /\A## ✔ .+ · roadmap · delivered\z/)
