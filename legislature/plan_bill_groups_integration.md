# Plan: Integrate Bill Groups into Legislation Pages

## Overview

Add group status information to show users the overall progress of related legislation, not just the individual bill's status.

## Data Source

`data/bill_groups.rds` contains:
- `bill` — bill number
- `status` — individual bill status (Introduced → Signed by Governor)
- `status_level` — numeric (1-6)
- `bill_group_id` — group identifier
- `group_size` — number of bills in the group
- `group_members` — list of all related bills
- `group_status` — furthest status reached by any bill in the group
- `lead_bill` — which bill achieved the group status

---

## Changes to `site/legislation/index.qmd`

### 1. Load bill groups data

Add to the data loading chunk:

```r
bill_groups <- read_rds(here::here("data/bill_groups.rds"))
```

### 2. Add "Group Status" column to tables

For the "All Legislation" table and the House/Senate Files tables, join with `bill_groups` and add a `group_status` column.

**Modified columns:**
- Keep existing: `bill_link`, `title`, `chamber`, `sponsor_name`, `status_desc`, `last_action_date`
- Add: `group_status` — shows the group's furthest progress

**Example join:**
```r
all_bills <- bills |>
  left_join(primary_sponsors, by = "bill_id") |>
  left_join(
    bill_groups |> select(bill, group_status, group_size, lead_bill),
    by = c("bill_number" = "bill")
  ) |>
  mutate(
    bill_link = format_bill_link(bill_number),
    # Show group status with indicator if different from individual
    group_status_display = case_when(
      group_size == 1 ~ group_status,
      group_status == status ~ group_status,
      TRUE ~ paste0(group_status, "*")
    )
  )
```

### 3. Add footnote explaining group status

Below the "All Legislation" table header, add:

```markdown
*Group Status shows the furthest progress of any related bill. An asterisk (*) indicates the group has progressed further than this individual bill.*
```

### 4. Optional: Add "Group Status Summary" section

After the existing "Status Summary" table, add a new summary showing group status distribution:

```r
group_status_summary <- bill_groups |>
  count(group_status, name = "count") |>
  arrange(match(group_status, c("Introduced", "Passed Subcommittee", "Passed Committee",
                                 "Passed One Chamber", "Passed Both Chambers", "Signed by Governor")))

gt(group_status_summary) |>
  cols_label(group_status = "Group Status", count = "Count") |>
  tab_header(title = "Bills by Group Status")
```

---

## Changes to `site/templates/bill_template.qmd`

### 1. Load bill groups data

Add to the data loading chunk:

```r
bill_groups <- read_rds(here::here("data/bill_groups.rds"))
bill_group_info <- bill_groups |> filter(bill == params$bill_num)
```

### 2. Add "Related Legislation" section

Add a new section after Sponsors (before the tabset), showing:

**If bill has related bills (group_size > 1):**

```markdown
## Related Legislation

This bill is part of a group of **{group_size}** related bills.
The group's furthest progress is **{group_status}**, achieved by [{lead_bill}](lead_bill.html).

### Related Bills
[Table showing: bill_link, title, status for each bill in group_members]
```

**If bill has no related bills:**

```markdown
## Related Legislation

No related bills identified.
```

### 3. Update Status display

Change the existing status line from:

```markdown
*Status: *
```

To show both individual and group status:

```r
cat(paste0("**Status:** ", bill_group_info$status, "\n\n"))

if (bill_group_info$group_size > 1 && bill_group_info$status != bill_group_info$group_status) {
  cat(paste0("**Group Status:** ", bill_group_info$group_status,
             " (via [", bill_group_info$lead_bill, "](", bill_group_info$lead_bill, ".html))\n\n"))
}
```

### 4. Related Bills table structure

```r
if (bill_group_info$group_size > 1) {
  related_bills_list <- unlist(bill_group_info$group_members)

  # Get info for related bills
  related_df <- bill_groups |>
    filter(bill %in% related_bills_list, bill != params$bill_num) |>
    left_join(
      bills_csv |> select(bill_number, title),
      by = c("bill" = "bill_number")
    ) |>
    mutate(bill_link = format_bill_link(bill, "")) |>
    select(bill_link, title, status) |>
    arrange(desc(status_level))

  gt(related_df) |>
    cols_label(bill_link = "Bill", title = "Title", status = "Status") |>
    fmt_markdown(columns = bill_link)
}
```

---

## Implementation Order

1. **Update `legislation/index.qmd`**
   - Load bill_groups.rds
   - Add group_status column to All Legislation table
   - Add group_status column to House Files table
   - Add group_status column to Senate Files table
   - Add footnote explaining asterisk notation
   - (Optional) Add Group Status Summary section

2. **Update `templates/bill_template.qmd`**
   - Load bill_groups.rds
   - Add Related Legislation section with table
   - Update status display to show both individual and group status

3. **Test with `test_render()`**

---

## Column Width Adjustments

For `legislation/index.qmd` tables, adjust widths to accommodate the new column:

```r
cols_width(
  bill_link ~ px(70),
  title ~ px(280),
  chamber ~ px(60),
  sponsor_name ~ px(120),
  status_desc ~ px(90),
  group_status ~ px(110),
  last_action_date ~ px(90)
)
```

---

## Graceful Degradation

If `bill_groups.rds` doesn't exist (user hasn't run the scraper yet), the pages should still render. Add a check:

```r
bill_groups_path <- here::here("data/bill_groups.rds")
if (file.exists(bill_groups_path)) {
  bill_groups <- read_rds(bill_groups_path)
} else {
  # Create empty placeholder
  bill_groups <- tibble(
    bill = character(),
    group_status = character(),
    group_size = integer(),
    lead_bill = character(),
    group_members = list()
  )
}
```
