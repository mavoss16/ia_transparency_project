# R/campaign_finance/04_build_database.R
#
# Ingests cleaned Parquet files into a DuckDB database and creates pre-computed
# summary views used by Quarto rendering.
#
# Depends on: 02_clean_normalize.R (required); 02a_clean_normalize_federal.R (optional)
# Input:  data/campaign_finance/processed/*.parquet
# Output: data/campaign_finance/campaign_finance.duckdb
#
# State summary views (always created):
#   committee_summary  — one row per committee (totals, donor counts)
#   committee_donor    — one row per committee × donor (top donors table)
#   committee_year     — one row per committee × year × donor_type (charts)
#   donor_summary      — one row per donor_key (donor profile totals)
#   donor_committee    — one row per donor × committee (recipient breakdown)
#   donor_year         — one row per donor × year × party (charts)
#
# FEC federal views (created only if fec_*.parquet files exist):
#   fec_committee_summary  — one row per CMTE_ID (Iowa candidate committees)
#   fec_committee_donor    — one row per CMTE_ID × fec_donor_key
#   fec_committee_year     — one row per CMTE_ID × year × donor_type
#   fec_donor_summary      — one row per fec_donor_key
#   fec_donor_committee    — one row per fec_donor_key × CMTE_ID
#   fec_donor_year         — one row per fec_donor_key × year × party
#
# Money columns in the state views are split by transaction_class, because the
# IECDB "contributions received" feed mixes cash gifts (CON), in-kind gifts
# (INK) and loans received (LOANREC):
#
#   total_contributions  cash given
#   total_in_kind        goods and services given
#   total_loans          borrowed, repayable — not a gift
#   total_donated        contributions + in_kind (everything actually given)
#
# There is deliberately no unqualified `total` / `total_raised` / `total_given`
# column: an ambiguous name is what let loans be counted as donations in the
# first place, so callers now have to name the money they mean.
#
# The committees table is produced by 02_clean_normalize.R, which already merges
# the registered CSV (~1,600 rows) with the API lookup from step 01 (~7,900 rows).
# Party, office, and election fields are fully resolved there; no secondary join
# is needed here.

library(duckdb)
library(DBI)
library(here)

processed_dir <- here("data/campaign_finance/processed")
db_path       <- here("data/campaign_finance/campaign_finance.duckdb")

# Verify processed files exist before doing anything destructive
required_files <- c("contributions.parquet", "expenditures.parquet", "committees.parquet")
missing <- required_files[!file.exists(file.path(processed_dir, required_files))]
if (length(missing) > 0) {
  stop("Missing processed files (run 02_clean_normalize.R first): ",
       paste(missing, collapse = ", "))
}

# Rebuild from scratch each time — summaries are fully derived
if (file.exists(db_path)) {
  message("Removing existing database for full rebuild...")
  file.remove(db_path)
}

con <- dbConnect(duckdb(), db_path)
message("Connected: ", db_path)

# Use forward slashes — DuckDB requires them even on Windows
parquet_path <- function(name) {
  gsub("\\\\", "/", file.path(processed_dir, paste0(name, ".parquet")))
}

# ── Base tables ───────────────────────────────────────────────────────────────

message("Loading base tables from Parquet...")

dbExecute(con, sprintf(
  "CREATE TABLE contributions AS SELECT * FROM read_parquet('%s')",
  parquet_path("contributions")
))
n_contrib <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM contributions")$n
message(sprintf("  contributions: %s rows", formatC(n_contrib, format = "d", big.mark = ",")))

dbExecute(con, sprintf(
  "CREATE TABLE expenditures AS SELECT * FROM read_parquet('%s')",
  parquet_path("expenditures")
))
n_exp <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM expenditures")$n
message(sprintf("  expenditures:  %s rows", formatC(n_exp, format = "d", big.mark = ",")))

dbExecute(con, sprintf(
  "CREATE TABLE committees AS SELECT * FROM read_parquet('%s')",
  parquet_path("committees")
))
n_comm <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM committees")$n
message(sprintf("  committees:    %s rows", formatC(n_comm, format = "d", big.mark = ",")))

# ── Indexes ───────────────────────────────────────────────────────────────────

message("Creating indexes...")

dbExecute(con, "CREATE INDEX idx_contrib_committee  ON contributions(committee_code)")
dbExecute(con, "CREATE INDEX idx_contrib_donor_key  ON contributions(donor_key)")
dbExecute(con, "CREATE INDEX idx_contrib_year       ON contributions(year)")
dbExecute(con, "CREATE INDEX idx_contrib_type       ON contributions(donor_type)")
dbExecute(con, "CREATE INDEX idx_contrib_class      ON contributions(transaction_class)")
dbExecute(con, "CREATE INDEX idx_exp_committee      ON expenditures(committee_code)")
dbExecute(con, "CREATE INDEX idx_exp_year           ON expenditures(year)")
dbExecute(con, "CREATE INDEX idx_committees_code    ON committees(committee_code)")

# ── Summary views ─────────────────────────────────────────────────────────────

message("Creating summary views...")

# 1. committee_summary ─────────────────────────────────────────────────────────
# One row per committee. Used for the recipient page header stats block.
dbExecute(con, "
  CREATE VIEW committee_summary AS
  SELECT
    c.committee_code,
    COALESCE(m.committee_name, c.committee_name) AS committee_name,
    COALESCE(m.committee_type, c.committee_type) AS committee_type,
    m.party,
    m.office_sought,
    m.district,
    m.election_year,
    m.candidate_name,
    COUNT(*)                    AS n_transactions,
    SUM(CASE WHEN c.transaction_class = 'contribution' THEN 1 ELSE 0 END) AS n_contributions,
    SUM(CASE WHEN c.transaction_class = 'in_kind'      THEN 1 ELSE 0 END) AS n_in_kind,
    SUM(CASE WHEN c.transaction_class = 'loan'         THEN 1 ELSE 0 END) AS n_loans,
    -- Unitemized/unidentified rows are real money (so they stay in the money
    -- columns) but they are not donors, so they are not counted here. Neither
    -- is a lender: money that has to be paid back was not given.
    COUNT(DISTINCT CASE WHEN c.donor_attribution = 'itemized'
                         AND c.transaction_class <> 'loan'
                        THEN c.donor_key END) AS n_unique_donors,
    SUM(CASE WHEN c.transaction_class = 'contribution'
             THEN c.contribution_amount ELSE 0 END) AS total_contributions,
    SUM(CASE WHEN c.transaction_class = 'in_kind'
             THEN c.contribution_amount ELSE 0 END) AS total_in_kind,
    SUM(CASE WHEN c.transaction_class = 'loan'
             THEN c.contribution_amount ELSE 0 END) AS total_loans,
    SUM(CASE WHEN c.transaction_class <> 'loan'
             THEN c.contribution_amount ELSE 0 END) AS total_donated,
    -- Average of an actual cash gift; in-kind and loans would distort it.
    AVG(CASE WHEN c.transaction_class = 'contribution'
             THEN c.contribution_amount END)        AS avg_contribution,
    MIN(c.date)                 AS first_contribution,
    MAX(c.date)                 AS last_contribution
  FROM contributions c
  LEFT JOIN committees m ON c.committee_code = m.committee_code
  GROUP BY ALL
")

# 2. committee_donor ───────────────────────────────────────────────────────────
# One row per committee × donor. Used for the top-donors tables on recipient pages.
# Restricted to itemized rows so unitemized lump sums and unidentified filings
# don't rank alongside real donors.
#
# Lenders are NOT filtered out here — a committee financed by a candidate loan
# should still show that on its page. They are kept in their own column instead,
# so a ranking by total_donated leaves them where they belong (at $0 given)
# without hiding the money.
dbExecute(con, "
  CREATE VIEW committee_donor AS
  SELECT
    committee_code,
    committee_name,
    donor_key,
    donor_display,
    donor_type,
    clean_city                   AS city,
    norm_state                   AS state,
    COUNT(*)                     AS transactions,
    SUM(CASE WHEN transaction_class = 'contribution'
             THEN contribution_amount ELSE 0 END) AS total_contributions,
    SUM(CASE WHEN transaction_class = 'in_kind'
             THEN contribution_amount ELSE 0 END) AS total_in_kind,
    SUM(CASE WHEN transaction_class = 'loan'
             THEN contribution_amount ELSE 0 END) AS total_loans,
    SUM(CASE WHEN transaction_class <> 'loan'
             THEN contribution_amount ELSE 0 END) AS total_donated,
    MIN(date)                    AS first_date,
    MAX(date)                    AS last_date
  FROM contributions
  WHERE donor_attribution = 'itemized'
  GROUP BY ALL
")

# 3. committee_year ────────────────────────────────────────────────────────────
# One row per committee × year × donor_type. Used for the over-time charts.
dbExecute(con, "
  CREATE VIEW committee_year AS
  SELECT
    committee_code,
    committee_name,
    year,
    donor_type,
    COUNT(*)                      AS n_transactions,
    COUNT(DISTINCT CASE WHEN donor_attribution = 'itemized'
                         AND transaction_class <> 'loan'
                        THEN donor_key END) AS n_unique_donors,
    SUM(CASE WHEN transaction_class = 'contribution'
             THEN contribution_amount ELSE 0 END) AS total_contributions,
    SUM(CASE WHEN transaction_class = 'in_kind'
             THEN contribution_amount ELSE 0 END) AS total_in_kind,
    SUM(CASE WHEN transaction_class = 'loan'
             THEN contribution_amount ELSE 0 END) AS total_loans,
    SUM(CASE WHEN transaction_class <> 'loan'
             THEN contribution_amount ELSE 0 END) AS total_donated
  FROM contributions
  GROUP BY ALL
")

# 4. donor_summary ────────────────────────────────────────────────────────────
# One row per donor_key. Used for the donor page header stats block.
# MAX() on text fields surfaces the most-common variant (good enough pre-step-03).
# Views 4-6 are donor-facing and therefore itemized-only: a donor page or a
# largest-donors ranking must never present a bookkeeping row as a person.
dbExecute(con, "
  CREATE VIEW donor_summary AS
  SELECT
    donor_key,
    donor_type,
    MAX(donor_display)            AS donor_display,
    MAX(norm_last)                AS norm_last,
    MAX(norm_first)               AS norm_first,
    MAX(norm_org)                 AS norm_org,
    MAX(clean_city)               AS city,
    MAX(norm_state)               AS state,
    COUNT(*)                      AS n_transactions,
    COUNT(DISTINCT committee_code) AS n_committees,
    SUM(CASE WHEN transaction_class = 'contribution'
             THEN contribution_amount ELSE 0 END) AS total_contributions,
    SUM(CASE WHEN transaction_class = 'in_kind'
             THEN contribution_amount ELSE 0 END) AS total_in_kind,
    SUM(CASE WHEN transaction_class = 'loan'
             THEN contribution_amount ELSE 0 END) AS total_loans,
    SUM(CASE WHEN transaction_class <> 'loan'
             THEN contribution_amount ELSE 0 END) AS total_donated,
    AVG(CASE WHEN transaction_class = 'contribution'
             THEN contribution_amount END)        AS avg_contribution,
    MIN(date)                     AS first_contribution,
    MAX(date)                     AS last_contribution
  FROM contributions
  WHERE donor_attribution = 'itemized'
  GROUP BY donor_key, donor_type
")

# 5. donor_committee ──────────────────────────────────────────────────────────
# One row per donor × committee. Used for the "Recipients" tab on donor pages.
dbExecute(con, "
  CREATE VIEW donor_committee AS
  SELECT
    c.donor_key,
    c.donor_display,
    c.donor_type,
    c.committee_code,
    COALESCE(m.committee_name, c.committee_name) AS committee_name,
    COALESCE(m.committee_type, c.committee_type) AS committee_type,
    m.party,
    m.office_sought,
    m.district,
    m.election_year,
    m.candidate_name,
    COUNT(*)                   AS transactions,
    SUM(CASE WHEN c.transaction_class = 'contribution'
             THEN c.contribution_amount ELSE 0 END) AS total_contributions,
    SUM(CASE WHEN c.transaction_class = 'in_kind'
             THEN c.contribution_amount ELSE 0 END) AS total_in_kind,
    SUM(CASE WHEN c.transaction_class = 'loan'
             THEN c.contribution_amount ELSE 0 END) AS total_loans,
    SUM(CASE WHEN c.transaction_class <> 'loan'
             THEN c.contribution_amount ELSE 0 END) AS total_donated,
    MIN(c.date)                AS first_date,
    MAX(c.date)                AS last_date
  FROM contributions c
  LEFT JOIN committees m ON c.committee_code = m.committee_code
  WHERE c.donor_attribution = 'itemized'
  GROUP BY ALL
")

# 6. donor_year ───────────────────────────────────────────────────────────────
# One row per donor × year × party. Used for over-time + party-breakdown charts.
dbExecute(con, "
  CREATE VIEW donor_year AS
  SELECT
    c.donor_key,
    c.donor_type,
    c.year,
    COALESCE(m.party, '(Unknown)') AS party,
    COUNT(*)                        AS n_transactions,
    SUM(CASE WHEN c.transaction_class = 'contribution'
             THEN c.contribution_amount ELSE 0 END) AS total_contributions,
    SUM(CASE WHEN c.transaction_class = 'in_kind'
             THEN c.contribution_amount ELSE 0 END) AS total_in_kind,
    SUM(CASE WHEN c.transaction_class = 'loan'
             THEN c.contribution_amount ELSE 0 END) AS total_loans,
    SUM(CASE WHEN c.transaction_class <> 'loan'
             THEN c.contribution_amount ELSE 0 END) AS total_donated
  FROM contributions c
  LEFT JOIN committees m ON c.committee_code = m.committee_code
  WHERE c.donor_attribution = 'itemized'
  GROUP BY ALL
")

message("  6 summary views created.")

# ── Verification ──────────────────────────────────────────────────────────────

message("\nVerification:")

checks <- list(
  list(view = "committee_summary", label = "unique committees with contributions"),
  list(view = "donor_summary",     label = "unique donor keys (exact match only; see step 03)"),
  list(view = "committee_donor",   label = "committee × donor pairs"),
  list(view = "donor_committee",   label = "donor × committee pairs"),
  list(view = "committee_year",    label = "committee × year × type rows"),
  list(view = "donor_year",        label = "donor × year × party rows")
)

# Report party coverage across contributing committees
party_coverage <- dbGetQuery(con, "
  SELECT
    COUNT(DISTINCT c.committee_code)                                          AS contrib_committees,
    COUNT(DISTINCT CASE WHEN m.party IS NOT NULL THEN c.committee_code END)  AS with_party
  FROM contributions c
  LEFT JOIN committees m ON c.committee_code = m.committee_code
")
message(sprintf(
  "  Party coverage: %s/%s contributing committees (%.0f%%)",
  formatC(party_coverage$with_party,        format = "d", big.mark = ","),
  formatC(party_coverage$contrib_committees, format = "d", big.mark = ","),
  100 * party_coverage$with_party / pmax(party_coverage$contrib_committees, 1)
))

for (chk in checks) {
  n <- dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", chk$view))$n
  message(sprintf("  %-22s  %s  %s", chk$view,
                  formatC(n, format = "d", big.mark = ",", width = 10),
                  chk$label))
}

by_class <- dbGetQuery(con, "
  SELECT transaction_class,
         COUNT(*)                 AS n,
         SUM(contribution_amount) AS amount
  FROM contributions
  GROUP BY transaction_class
  ORDER BY amount DESC
")
message("\n  Money received, by class (only the first is a cash donation):")
for (i in seq_len(nrow(by_class))) {
  message(sprintf(
    "    %-14s %12s transactions   $%s",
    by_class$transaction_class[i],
    formatC(by_class$n[i], format = "d", big.mark = ","),
    formatC(by_class$amount[i], format = "f", digits = 2, big.mark = ",")
  ))
}
message(sprintf(
  "    %-14s %12s                $%s",
  "TOTAL", "",
  formatC(sum(by_class$amount), format = "f", digits = 2, big.mark = ",")
))

# ── FEC tables and views (optional — skipped if parquets not yet built) ───────

fec_files <- c("fec_contributions.parquet", "fec_committees.parquet")
fec_ready <- all(file.exists(file.path(processed_dir, fec_files)))

if (!fec_ready) {
  message("\nFEC parquets not found — skipping federal tables.")
  message("Run R/campaign_finance/02a_clean_normalize_federal.R to build them.")
} else {
  message("\n── FEC federal data ────────────────────────────────────────────────────────")

  # Base tables
  dbExecute(con, sprintf(
    "CREATE TABLE fec_contributions AS SELECT * FROM read_parquet('%s')",
    parquet_path("fec_contributions")
  ))
  n_fec <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM fec_contributions")$n
  message(sprintf("  fec_contributions: %s rows", formatC(n_fec, format = "d", big.mark = ",")))

  dbExecute(con, sprintf(
    "CREATE TABLE fec_committees AS SELECT * FROM read_parquet('%s')",
    parquet_path("fec_committees")
  ))
  n_fec_comm <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM fec_committees")$n
  message(sprintf("  fec_committees:    %s rows", formatC(n_fec_comm, format = "d", big.mark = ",")))

  # Indexes
  dbExecute(con, "CREATE INDEX idx_fec_CMTE_ID     ON fec_contributions(CMTE_ID)")
  dbExecute(con, "CREATE INDEX idx_fec_donor_key   ON fec_contributions(fec_donor_key)")
  dbExecute(con, "CREATE INDEX idx_fec_year        ON fec_contributions(year)")
  dbExecute(con, "CREATE INDEX idx_fec_donor_type  ON fec_contributions(donor_type)")
  dbExecute(con, "CREATE INDEX idx_fec_comm_CMTE   ON fec_committees(CMTE_ID)")

  # Summary views — parallel to the state views
  message("Creating FEC summary views...")

  # fec_committee_summary: one row per CMTE_ID (Iowa donor perspective)
  dbExecute(con, "
    CREATE VIEW fec_committee_summary AS
    SELECT
      c.CMTE_ID,
      COALESCE(m.committee_name, c.CMTE_ID)  AS committee_name,
      m.party,
      m.office,
      m.CAND_OFFICE_ST                        AS office_state,
      m.CAND_OFFICE_DISTRICT                  AS office_district,
      m.CAND_ELECTION_YR                      AS election_year,
      m.candidate_name,
      m.CMTE_TP,
      COUNT(*)                                AS n_transactions,
      COUNT(DISTINCT c.fec_donor_key)         AS n_unique_donors,
      SUM(c.contribution_amount)              AS total_raised,
      AVG(c.contribution_amount)              AS avg_contribution,
      MIN(c.date)                             AS first_contribution,
      MAX(c.date)                             AS last_contribution
    FROM fec_contributions c
    LEFT JOIN fec_committees m ON c.CMTE_ID = m.CMTE_ID
    GROUP BY ALL
  ")

  # fec_committee_donor: one row per committee × donor
  dbExecute(con, "
    CREATE VIEW fec_committee_donor AS
    SELECT
      CMTE_ID,
      fec_donor_key,
      donor_display,
      donor_type,
      norm_city                     AS city,
      norm_state                    AS state,
      COUNT(*)                      AS transactions,
      SUM(contribution_amount)      AS total,
      MIN(date)                     AS first_date,
      MAX(date)                     AS last_date
    FROM fec_contributions
    GROUP BY ALL
  ")

  # fec_committee_year: one row per committee × year × donor_type
  dbExecute(con, "
    CREATE VIEW fec_committee_year AS
    SELECT
      CMTE_ID,
      year,
      donor_type,
      COUNT(*)                      AS n_transactions,
      COUNT(DISTINCT fec_donor_key) AS n_unique_donors,
      SUM(contribution_amount)      AS total
    FROM fec_contributions
    GROUP BY ALL
  ")

  # fec_donor_summary: one row per fec_donor_key
  dbExecute(con, "
    CREATE VIEW fec_donor_summary AS
    SELECT
      fec_donor_key,
      donor_type,
      MAX(donor_display)              AS donor_display,
      MAX(norm_last)                  AS norm_last,
      MAX(norm_first)                 AS norm_first,
      MAX(norm_org)                   AS norm_org,
      MAX(norm_city)                  AS city,
      MAX(norm_state)                 AS state,
      COUNT(*)                        AS n_transactions,
      COUNT(DISTINCT CMTE_ID)         AS n_committees,
      SUM(contribution_amount)        AS total_given,
      AVG(contribution_amount)        AS avg_contribution,
      MIN(date)                       AS first_contribution,
      MAX(date)                       AS last_contribution
    FROM fec_contributions
    GROUP BY fec_donor_key, donor_type
  ")

  # fec_donor_committee: one row per donor × committee
  dbExecute(con, "
    CREATE VIEW fec_donor_committee AS
    SELECT
      c.fec_donor_key,
      c.donor_display,
      c.donor_type,
      c.CMTE_ID,
      COALESCE(m.committee_name, c.CMTE_ID)  AS committee_name,
      m.party,
      m.office,
      m.CAND_OFFICE_ST                        AS office_state,
      m.CAND_OFFICE_DISTRICT                  AS office_district,
      m.CAND_ELECTION_YR                      AS election_year,
      m.candidate_name,
      m.CMTE_TP,
      COUNT(*)                                AS transactions,
      SUM(c.contribution_amount)              AS total,
      MIN(c.date)                             AS first_date,
      MAX(c.date)                             AS last_date
    FROM fec_contributions c
    LEFT JOIN fec_committees m ON c.CMTE_ID = m.CMTE_ID
    GROUP BY ALL
  ")

  # fec_donor_year: one row per donor × year × party
  dbExecute(con, "
    CREATE VIEW fec_donor_year AS
    SELECT
      c.fec_donor_key,
      c.donor_type,
      c.year,
      c.cycle,
      COALESCE(m.party, '(Unknown)')  AS party,
      COUNT(*)                        AS n_transactions,
      SUM(c.contribution_amount)      AS total
    FROM fec_contributions c
    LEFT JOIN fec_committees m ON c.CMTE_ID = m.CMTE_ID
    GROUP BY ALL
  ")

  message("  6 FEC summary views created.")

  fec_total <- dbGetQuery(
    con, "SELECT SUM(contribution_amount) AS t FROM fec_contributions"
  )$t
  message(sprintf(
    "\n  Total FEC (Iowa donor) contributions in database: $%s",
    formatC(fec_total, format = "f", digits = 2, big.mark = ",")
  ))
}

dbDisconnect(con)
message(sprintf("\nDatabase ready: %s", db_path))
