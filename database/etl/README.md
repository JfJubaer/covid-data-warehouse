# SQL COVID-19 ETL

The pipeline runs entirely in PostgreSQL. It reads the append-only raw tables,
copies original CSV headers and values into staging, parses and validates rows,
records every rejected row, and loads dimensions and facts.

## Install and run in pgAdmin

1. Connect pgAdmin to the `covid_warehouse` database. If the schemas have not
   been initialized yet, execute `database/schema.sql` first.
2. Execute `database/etl/extract.sql`, then `transform.sql`, then `load.sql`.
   These install or update the staging compatibility columns, validation
   helpers, and procedures; they do not execute a data load.
3. Import source CSVs into their matching `raw_data` tables before running
   the pipeline. Each raw record must have `source_headers` and `source_values`
   arrays in matching column order; preserve all cells as text.
4. Execute `database/etl/run.sql`. Its single `CALL warehouse.run_covid_etl`
   runs extract, transform, and load in one PostgreSQL transaction and returns
   the new execution ID.
5. Substitute the returned ID in the following query to inspect the run:

   ```sql
   SELECT etl_run_id, status, started_at, finished_at,
          rows_extracted, rows_duplicates, rows_cleaned,
          rows_rejected, rows_loaded, error_message
   FROM warehouse.etl_runs
   WHERE etl_run_id = 1;
   ```

`rows_loaded` counts location-day and hospital-day fact rows inserted or
upserted; dimension rows are not included. `partial` means the pipeline
completed but sent one or more invalid or duplicate records to
`warehouse.rejected_records`. `failed` means the stage work was rolled back;
the run record retains the error. Raw rows are never updated or deleted.

## Stage behavior

- **Extract — `extract.sql`:** inserts each raw ID and its unchanged header and
  value arrays into the corresponding staging table. The unique
  `(etl_run_id, source_raw_id)` keys make extraction safe to repeat.
- **Transform — `transform.sql`:** validates dates in ISO, day/month/year,
  abbreviated-month, and day-abbreviated-month formats; parses integer fields;
  trims text; standardizes division/district aliases; rejects missing required
  identifiers, invalid dates/numbers, negative measures, and duplicate
  business keys. Rejected rows keep their original headers and values in JSON.
  Blank optional measures become SQL `NULL`, not fabricated zeroes.
- **Load — `load.sql`:** upserts date, location, hospital, and vaccine
  dimensions, then writes one location-level row per date and one row per
  hospital/date into `warehouse.fact_covid`. The location row combines cases,
  tests, and product-aggregated vaccination doses. Hospital occupancy and ICU
  patients are stored on hospital rows, with ICU capacity in `dim_hospital`.
  Location-wide measures are not copied onto hospital rows.

The three stage procedures can be called individually for controlled
troubleshooting, but use `warehouse.run_covid_etl(NULL)` for a managed,
atomic run with execution statistics.
