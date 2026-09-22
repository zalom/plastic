# encoding: UTF-8
# frozen_string_literal: true

require_relative "../screen_paint"

# The dashboard screen kind (intent 331d, D4). Its opener is a stricter
# subset of the already-registered :intent opener (screen_paint.rb:337,
# registered first), so ScreenPaint.opener_kind never actually answers
# :dashboard on a live paint call - that is deliberate (R2): :dashboard is
# tested on its OWN grammar (the OPENER constant below), never on
# opener_kind's answer, which cannot fail meaningfully here. No custom paint
# lambda (R3): every line of the screen classifies under the shared
# field-table/data-table grammar ScreenPaint.paint already carries.
module Screens
  module Dashboard
    OPENER = /\A## ▶ (?:global|project:[a-z0-9][a-z0-9_-]*) · dashboard\z/.freeze
  end
end

ScreenPaint.register(:dashboard, opener: Screens::Dashboard::OPENER)
