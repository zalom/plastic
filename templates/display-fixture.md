<!-- Doctor's display self-test fixture (intent 331e). Replayed through the
     installed MessageDisplay hook by `display_hook_paints` to prove painting
     still works; this is NOT a report-screen scaffold (no {{...}} mustache
     placeholders) and ships no data of its own. -->

## ▶ 331e · Doctor display check

| | | |
| --- | --- | --- |
| **Store**     | project:plastic                | the plastic project store |
| **Status**    | Active                          | listed under ## Active in INDEX.md |
| **Stage**     | Exec                            | What, Why, How, Exec delivered; the work is open |
| **Progress**  | ██████████░░░░░░░░░░ 3 / 6      | 3 steps open |

**Steps**

| Step | Status | What |
| --- | --- | --- |
| S1 | done | Tests red |
| S2 | done | check_display_registration in doctor_core.rb |
| S3 | open | The three full-run checks in doctor.rb |
