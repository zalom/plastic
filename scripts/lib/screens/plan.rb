# encoding: UTF-8
# frozen_string_literal: true

require_relative "../screen_paint"

# Intent 331b (D2/D4): the plan screen's grammar - "## ▶ {id} · {name} ·
# plan" - registers through 331a's kind registry, a file under
# scripts/lib/screens/ rather than a diff to screen_paint.rb. F1 (spec.md):
# opener_kind answers the FIRST registered match, and :intent's own opener
# (/\A## [▶✔] .+ · /) already matches this title, so this kind's opener is
# never actually reached - it still names the kind's home and its true
# grammar, and that is fine, because paint: nil is what D4's "with the state
# palette" asks for anyway: the shared pipeline branches on LINE SHAPE, never
# on kind, and no shipped kind carries its own palette. Narrowing :intent's
# opener from this file to reach a :plan-specific paint lambda is exactly
# the forbidden loophole spec.md's F1 names - it would silently un-paint the
# intent and state screens for every other caller, so it never happens here.
ScreenPaint.register(:plan, opener: /\A## ▶ .+ · plan\z/, paint: nil)
