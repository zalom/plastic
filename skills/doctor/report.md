# Plastic Doctor Report

<!-- =======================================================================
  AGENT INSTRUCTIONS -- How to fill this template
  =========================================================================
  1. Run the doctor script. It outputs JSON with check results.
  2. Replace every {{placeholder}} below with the corresponding JSON value.
  3. For the category sections: the template shows ONE example section.
     Repeat that pattern for each unique category in the checks array.
     The six known categories and their display names are:
       global_store       -> "Global Store"
       conventions        -> "Conventions"
       agent_registration -> "Agent Registration"
       core_files         -> "Core Files"
       project_stores     -> "Project Stores"
       deprecations       -> "Deprecations"
  4. For each check within a category, emit one line with the status icon
     and the check message. If the check has non-empty details, list them
     as indented sub-items.
  5. The "Fixable Issues" section should ONLY appear if at least one check
     has fixable=true AND status is not "pass". Omit the entire section
     otherwise.
  6. Status icons (plain text, no emoji):
       pass -> [PASS]
       warn -> [WARN]
       fail -> [FAIL]
  7. The overall status icon in the header uses the same mapping.
  8. After filling, remove all HTML comments -- they are instructions only.
  ======================================================================= -->

## {{overall_status_icon}} Overall: {{status}} -- Plastic v{{version}}

Checked at: {{timestamp}}

### Summary

{{pass}} passed, {{warn}} warnings, {{fail}} failed -- {{total}} checks total

---

<!-- =====================================================================
  CATEGORY SECTIONS
  ======================================================================
  Repeat the block below ONCE PER CATEGORY present in the checks array.
  Group checks by their "category" field. Use the display name mapping
  above for the heading. Within each category, list every check as a
  single line: status icon + message. If a check has non-empty "details",
  list each detail as an indented bullet beneath.

  Example category section (for agent_registration with two checks):
  ===================================================================== -->

### Agent Registration

- [PASS] Claude Code adapter registered
- [FAIL] 2 hook scripts not executable
  - ~/.claude/hooks/plastic-session-start
  - ~/.claude/hooks/plastic-gate-check

<!-- =====================================================================
  Repeat the above pattern for each category found in the checks array.
  Only include categories that have at least one check.
  Order categories as they appear in the checks array.
  ===================================================================== -->

---

<!-- =====================================================================
  FIXABLE ISSUES SECTION
  ======================================================================
  Include this section ONLY if one or more checks have fixable=true AND
  status is "warn" or "fail". If no fixable issues exist, omit everything
  from the "Fixable Issues" heading through the end of the horizontal
  rule that follows the table.

  For each fixable check that is not "pass", emit one table row:
    | status_icon | check_message | fix_hint |
  ===================================================================== -->

### Fixable Issues

| Status | Issue | Fix |
|--------|-------|-----|
| [FAIL] | 2 hook scripts not executable | chmod +x on the listed files |

<!-- =====================================================================
  Repeat one row per fixable non-pass check.
  ===================================================================== -->

---

<!-- =====================================================================
  FOOTER -- always include this line exactly as written.
  ===================================================================== -->

Run `plastic doctor --fix` to auto-fix all fixable issues, or ask me to fix them now.
