# Quarto starter kit — Iowa Political Transparency redesign

Files to drop into `ia_transparency_project`, matching the HTML mockups (1a–2c).

## Install

1. `custom.scss` → `site/custom.scss`
2. `ui_helpers.R` → `R/legislature/ui_helpers.R`
3. In `site/_quarto.yml`:

```yaml
format:
  html:
    theme: [cosmo, custom.scss]   # was: cosmo
    css: styles.css
    toc: false                    # index pages read better full-width;
                                  # keep toc: true in template qmds if you like
    page-layout: full             # optional: use the empty right-rail space
```

4. Add `reactable` to renv if not present (it already ships via
   `gt::opt_interactive`, but the legislator table uses it directly):
   `renv::install("reactable")`

## Wiring the mockup components into your qmds

Source the helpers at the top of each qmd (after your existing `source(utils.R)`):

```r
source(here::here("R/legislature/ui_helpers.R"))
```

### Home — Quick Stats bullets → stat cards (mockup 1a)

```{{r}}
ui_stat_grid(
  ui_stat_card("Total Bills", format(n_bills, big.mark = ","),
               sprintf("%s House · %s Senate",
                       format(n_house_bills, big.mark = ","),
                       format(n_senate_bills, big.mark = ","))),
  ui_stat_card("Signed by Governor", n_signed,
               sprintf("%.1f%% of all bills introduced", 100 * n_signed / n_bills)),
  ui_stat_card("Awaiting Governor", n_passed_both, "Passed both chambers"),
  ui_stat_card("Legislators", nrow(active_people),
               sprintf("%d R · %d D across both chambers", n_R, n_D))
)
```

### Home — Bill Progress bullets → bar list (1a)

```{{r}}
stage_counts |>
  transmute(label = as.character(status), count = n) |>
  ui_bar_list(highlight = "Signed by Governor")
```

### Home / cards generally

Wrap any section in a card with a fenced div:

```markdown
::: {.ia-card}
## Recent activity
...gt table or list...
:::
```

### Legislation index — the two status gt tables → paired bars (2a)

```{{r}}
status_summary |>
  left_join(group_status_summary, by = c("status" = "group_status")) |>
  transmute(label = as.character(status), ind = count.x, grp = count.y) |>
  ui_paired_bars()
```

### Legislation index — bills-by-type gt table → bar list (2a)

```{{r}}
bill_types |>
  rename(label = bill_type) |>
  ui_bar_list()
```

### Recent bills tables — cleaned titles + status pills (1a / 2a)

In the data prep, replace raw titles:

```r
cleaned <- lapply(recent_bills$title, clean_bill_title)
recent_bills <- recent_bills |>
  mutate(
    short_title = sapply(cleaned, `[[`, "title"),
    title_meta  = sapply(cleaned, `[[`, "meta"),
    status_html = sapply(display_status, \(s) as.character(status_pill(s)))
  )
```

Then in gt: `fmt_markdown(columns = status_html)` — or drop gt for these
25-row lists and emit the rows directly with htmltools (grid rows like the
mockup). gt + `gt_theme_ia()` is the lower-effort path.

### Legislators index — gt tables → reactable with inline bars (2b)

```{{r}}
senators |> legislator_table()
```

(Same `senators` dataframe you already build — `with_party_pct` and
`participation_rate` stay as 0–1 proportions, don't `fmt_percent` them.)

### Legislator template — header + stat cards + vote pills (2c)

```{{r}}
ui_profile_header(
  name = person$name, party = person$party,
  role_label = if (person$role == "Sen") "Senator" else "Representative",
  district = person$district,
  notice = if (is_former) sprintf(
    "No longer serving — succeeded by <a href='%s.html'>%s (%s)</a> this session.",
    successor_file, successor_name, successor_party)
)

ui_stat_grid(
  ui_stat_card("Bills Sponsored", n_sponsored, sponsor_role_sub),
  ui_stat_card("Party Alignment", sprintf("%.1f%%", 100 * with_party_pct),
               sprintf("%d with party · %d against", n_with, n_against)),
  ui_stat_card("Participation", sprintf("%.1f%%", 100 * participation_rate),
               "Of eligible floor votes"),
  ui_stat_card("Floor Votes", votes_cast, "Cast this session")
)
```

Vote tables: add a column `vote_html = sapply(vote, \(v) as.character(vote_pill(v)))`
and render with `fmt_markdown`.

### Bill template — stepper + lobbyist bar (1b)

```{{r}}
stages <- c("Introduced", "Passed Subcommittee", "Passed Committee",
            "Passed One Chamber", "Passed Both Chambers", "Signed by Governor")
ui_stepper(stages, reached = match(bill_status, stages))

ui_share_bar(
  c(For = n_for, Against = n_against, Undecided = n_undecided),
  c(For = "#256a43", Against = "#A8433A", Undecided = "#cfccc2")
)
```

### Parliament charts (1a)

Keep ggparliament; just swap colors and drop chart titles (the card supplies
the heading):

```r
party_colours <- c("R" = "#A8433A", "D" = "#3F5B93")
```

### Leaflet maps

No changes needed — update `party_fill()` to the same two hexes for consistency.

## Notes

- htmltools tag objects render directly from a chunk when they're the last
  expression — no `results: asis` needed. For multiple components in one
  chunk, wrap in `tagList(...)`.
- The Bootstrap `.grid` / `.g-col-6` divs you already use still work for
  two-column layouts (funnel + composition side by side).
- Nav active-tab underline, link colors, body background all come from the
  SCSS — no per-page work.
