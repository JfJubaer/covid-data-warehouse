-- Install extract.sql, transform.sql, and load.sql once, in that order.
-- A single CALL runs all three stages atomically. The returned value is the
-- execution ID; use it to inspect the corresponding warehouse.etl_runs row.
CALL warehouse.run_covid_etl(NULL);
