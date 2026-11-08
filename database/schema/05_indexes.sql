CREATE INDEX IF NOT EXISTS rejected_records_etl_run_idx
    ON warehouse.rejected_records (etl_run_id);
CREATE INDEX IF NOT EXISTS rejected_records_source_idx
    ON warehouse.rejected_records (source_table, source_raw_id);

CREATE INDEX IF NOT EXISTS fact_covid_location_date_idx
    ON warehouse.fact_covid (location_id, date_id);
CREATE INDEX IF NOT EXISTS fact_covid_hospital_date_idx
    ON warehouse.fact_covid (hospital_id, date_id);
CREATE INDEX IF NOT EXISTS fact_covid_vaccine_date_idx
    ON warehouse.fact_covid (vaccine_id, date_id);
CREATE INDEX IF NOT EXISTS fact_covid_etl_run_idx
    ON warehouse.fact_covid (etl_run_id);

CREATE INDEX IF NOT EXISTS stg_covid_cases_run_date_idx
    ON staging.stg_covid_cases (etl_run_id, report_date);
CREATE INDEX IF NOT EXISTS stg_hospitals_run_idx
    ON staging.stg_hospitals (etl_run_id);
CREATE INDEX IF NOT EXISTS stg_vaccinations_run_date_idx
    ON staging.stg_vaccinations (etl_run_id, report_date);
CREATE INDEX IF NOT EXISTS stg_testing_run_date_idx
    ON staging.stg_testing (etl_run_id, report_date);
