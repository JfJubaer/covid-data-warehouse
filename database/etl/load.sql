CREATE OR REPLACE PROCEDURE warehouse.etl_load(p_etl_run_id BIGINT)
LANGUAGE PLPGSQL
AS $$
DECLARE
    v_status TEXT;
    v_loaded BIGINT := 0;
    v_inserted BIGINT;
BEGIN
    SELECT status INTO v_status
    FROM warehouse.etl_runs
    WHERE etl_run_id = p_etl_run_id
    FOR UPDATE;
    IF NOT FOUND OR v_status <> 'running' THEN
        RAISE EXCEPTION 'ETL run % does not exist or is not running', p_etl_run_id;
    END IF;

    INSERT INTO warehouse.dim_date (full_date, day, month, month_name, quarter, year)
    SELECT DISTINCT
        dates.report_date,
        EXTRACT(DAY FROM dates.report_date)::SMALLINT,
        EXTRACT(MONTH FROM dates.report_date)::SMALLINT,
        to_char(dates.report_date, 'FMMonth'),
        EXTRACT(QUARTER FROM dates.report_date)::SMALLINT,
        EXTRACT(YEAR FROM dates.report_date)::INTEGER
    FROM (
        SELECT report_date FROM staging.stg_covid_cases
        WHERE etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_covid_cases'
                AND r.source_raw_id = staging.stg_covid_cases.source_raw_id
          )
        UNION
        SELECT report_date FROM staging.stg_hospitals
        WHERE etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_hospitals'
                AND r.source_raw_id = staging.stg_hospitals.source_raw_id
          )
        UNION
        SELECT report_date FROM staging.stg_vaccinations
        WHERE etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_vaccinations'
                AND r.source_raw_id = staging.stg_vaccinations.source_raw_id
          )
        UNION
        SELECT report_date FROM staging.stg_testing
        WHERE etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_testing'
                AND r.source_raw_id = staging.stg_testing.source_raw_id
          )
    ) AS dates
    WHERE dates.report_date IS NOT NULL
    ON CONFLICT (full_date) DO NOTHING;

    WITH source_locations AS (
        SELECT source_raw_id, report_date, country, division, district, population
        FROM staging.stg_covid_cases s
        WHERE etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_covid_cases'
                AND r.source_raw_id = s.source_raw_id
          )
        UNION ALL
        SELECT source_raw_id, report_date, country, division, district, population
        FROM staging.stg_hospitals s
        WHERE etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_hospitals'
                AND r.source_raw_id = s.source_raw_id
          )
        UNION ALL
        SELECT source_raw_id, report_date, country, division, district, population
        FROM staging.stg_vaccinations s
        WHERE etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_vaccinations'
                AND r.source_raw_id = s.source_raw_id
          )
        UNION ALL
        SELECT source_raw_id, report_date, country, division, district, population
        FROM staging.stg_testing s
        WHERE etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_testing'
                AND r.source_raw_id = s.source_raw_id
          )
    ),
    locations AS (
        SELECT DISTINCT ON (country, division, district)
            country, division, district, population
        FROM source_locations
        ORDER BY country, division, district, source_raw_id
    )
    INSERT INTO warehouse.dim_location (country, division, district, population)
    SELECT country, division, district, population
    FROM locations
    ON CONFLICT ON CONSTRAINT dim_location_natural_key
    DO UPDATE SET population = COALESCE(
        warehouse.dim_location.population,
        EXCLUDED.population
    );

    INSERT INTO warehouse.dim_hospital
        (hospital_name, hospital_type, hospital_capacity, icu_capacity)
    SELECT DISTINCT ON (lower(btrim(s.hospital_name)), COALESCE(lower(btrim(s.hospital_type)), ''))
        s.hospital_name, s.hospital_type, s.hospital_capacity, s.icu_capacity
    FROM staging.stg_hospitals AS s
    WHERE s.etl_run_id = p_etl_run_id
      AND NOT EXISTS (
          SELECT 1 FROM warehouse.rejected_records AS r
          WHERE r.etl_run_id = p_etl_run_id
            AND r.source_table = 'raw_hospitals'
            AND r.source_raw_id = s.source_raw_id
      )
    ORDER BY lower(btrim(s.hospital_name)),
             COALESCE(lower(btrim(s.hospital_type)), ''),
             s.source_raw_id
    ON CONFLICT (
        (lower(btrim(hospital_name))),
        (COALESCE(lower(btrim(hospital_type)), ''))
    )
    DO UPDATE SET
        hospital_capacity = COALESCE(
            warehouse.dim_hospital.hospital_capacity,
            EXCLUDED.hospital_capacity
        ),
        icu_capacity = COALESCE(
            warehouse.dim_hospital.icu_capacity,
            EXCLUDED.icu_capacity
        );

    INSERT INTO warehouse.dim_vaccine (vaccine_name, manufacturer)
    SELECT DISTINCT s.vaccine_name, s.manufacturer
    FROM staging.stg_vaccinations AS s
    WHERE s.etl_run_id = p_etl_run_id
      AND NOT EXISTS (
          SELECT 1 FROM warehouse.rejected_records AS r
          WHERE r.etl_run_id = p_etl_run_id
            AND r.source_table = 'raw_vaccinations'
            AND r.source_raw_id = s.source_raw_id
      )
    ON CONFLICT ON CONSTRAINT dim_vaccine_natural_key DO NOTHING;

    WITH case_ranked AS (
        SELECT s.*,
               row_number() OVER (
                   PARTITION BY s.report_date, s.country, s.division, s.district
                   ORDER BY s.source_raw_id
               ) AS duplicate_number
        FROM staging.stg_covid_cases AS s
        WHERE s.etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records AS r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_covid_cases'
                AND r.source_raw_id = s.source_raw_id
          )
    ),
    cases AS (
        SELECT report_date, country, division, district,
               new_cases, total_cases, deaths, recoveries, icu_patients
        FROM case_ranked
        WHERE duplicate_number = 1
    ),
    test_ranked AS (
        SELECT s.*,
               row_number() OVER (
                   PARTITION BY s.report_date, s.country, s.division, s.district, s.test_type
                   ORDER BY s.source_raw_id
               ) AS duplicate_number
        FROM staging.stg_testing AS s
        WHERE s.etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records AS r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_testing'
                AND r.source_raw_id = s.source_raw_id
          )
    ),
    tests AS (
        SELECT report_date, country, division, district, SUM(tests) AS tests
        FROM test_ranked
        WHERE duplicate_number = 1
        GROUP BY report_date, country, division, district
    ),
    vaccine_ranked AS (
        SELECT s.*,
               row_number() OVER (
                   PARTITION BY s.report_date, s.country, s.division, s.district,
                                lower(btrim(s.vaccine_name)),
                                COALESCE(lower(btrim(s.manufacturer)), '')
                   ORDER BY s.source_raw_id
               ) AS duplicate_number
        FROM staging.stg_vaccinations AS s
        WHERE s.etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records AS r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_vaccinations'
                AND r.source_raw_id = s.source_raw_id
          )
    ),
    vaccinations AS (
        SELECT report_date, country, division, district,
               SUM(vaccinations) AS vaccinations
        FROM vaccine_ranked
        WHERE duplicate_number = 1
        GROUP BY report_date, country, division, district
    ),
    location_days AS (
        SELECT report_date, country, division, district FROM cases
        UNION
        SELECT report_date, country, division, district FROM tests
        UNION
        SELECT report_date, country, division, district FROM vaccinations
    ),
    daily AS (
        SELECT k.report_date, k.country, k.division, k.district,
               c.new_cases, c.total_cases, c.deaths, c.recoveries,
               t.tests, v.vaccinations, c.icu_patients
        FROM location_days AS k
        LEFT JOIN cases AS c USING (report_date, country, division, district)
        LEFT JOIN tests AS t USING (report_date, country, division, district)
        LEFT JOIN vaccinations AS v USING (report_date, country, division, district)
    )
    INSERT INTO warehouse.fact_covid
        (date_id, location_id, hospital_id, vaccine_id, etl_run_id,
         new_cases, total_cases, deaths, recoveries, tests, vaccinations,
         icu_patients, occupied_beds)
    SELECT d.date_id, l.location_id, NULL, NULL, p_etl_run_id,
           daily.new_cases, daily.total_cases, daily.deaths, daily.recoveries,
           daily.tests, daily.vaccinations, daily.icu_patients, NULL
    FROM daily
    JOIN warehouse.dim_date AS d ON d.full_date = daily.report_date
    JOIN warehouse.dim_location AS l
      ON l.country = daily.country
     AND l.division = daily.division
     AND l.district = daily.district
    ON CONFLICT (date_id, location_id, hospital_id)
    DO UPDATE SET
        vaccine_id = EXCLUDED.vaccine_id,
        etl_run_id = EXCLUDED.etl_run_id,
        new_cases = EXCLUDED.new_cases,
        total_cases = EXCLUDED.total_cases,
        deaths = EXCLUDED.deaths,
        recoveries = EXCLUDED.recoveries,
        tests = EXCLUDED.tests,
        vaccinations = EXCLUDED.vaccinations,
        icu_patients = EXCLUDED.icu_patients,
        occupied_beds = EXCLUDED.occupied_beds;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_loaded := v_loaded + v_inserted;

    WITH hospital_ranked AS (
        SELECT s.*,
               row_number() OVER (
                   PARTITION BY s.report_date, s.country, s.division, s.district,
                                lower(btrim(s.hospital_name)),
                                COALESCE(lower(btrim(s.hospital_type)), '')
                   ORDER BY s.source_raw_id
               ) AS duplicate_number
        FROM staging.stg_hospitals AS s
        WHERE s.etl_run_id = p_etl_run_id
          AND NOT EXISTS (
              SELECT 1 FROM warehouse.rejected_records AS r
              WHERE r.etl_run_id = p_etl_run_id
                AND r.source_table = 'raw_hospitals'
                AND r.source_raw_id = s.source_raw_id
          )
    )
    INSERT INTO warehouse.fact_covid
        (date_id, location_id, hospital_id, vaccine_id, etl_run_id,
         icu_patients, occupied_beds)
    SELECT d.date_id, l.location_id, h.hospital_id, NULL, p_etl_run_id,
           s.icu_patients, s.occupied_beds
    FROM hospital_ranked AS s
    JOIN warehouse.dim_date AS d ON d.full_date = s.report_date
    JOIN warehouse.dim_location AS l
      ON l.country = s.country
     AND l.division = s.division
     AND l.district = s.district
    JOIN warehouse.dim_hospital AS h
      ON lower(btrim(h.hospital_name)) = lower(btrim(s.hospital_name))
     AND COALESCE(lower(btrim(h.hospital_type)), '')
         = COALESCE(lower(btrim(s.hospital_type)), '')
    WHERE s.duplicate_number = 1
    ON CONFLICT (date_id, location_id, hospital_id)
    DO UPDATE SET
        vaccine_id = EXCLUDED.vaccine_id,
        etl_run_id = EXCLUDED.etl_run_id,
        new_cases = EXCLUDED.new_cases,
        total_cases = EXCLUDED.total_cases,
        deaths = EXCLUDED.deaths,
        recoveries = EXCLUDED.recoveries,
        tests = EXCLUDED.tests,
        vaccinations = EXCLUDED.vaccinations,
        icu_patients = EXCLUDED.icu_patients,
        occupied_beds = EXCLUDED.occupied_beds;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_loaded := v_loaded + v_inserted;

    UPDATE warehouse.etl_runs
    SET rows_loaded = v_loaded,
        status = CASE WHEN rows_rejected > 0 THEN 'partial' ELSE 'succeeded' END,
        finished_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE etl_run_id = p_etl_run_id;
END;
$$;

CREATE OR REPLACE PROCEDURE warehouse.run_covid_etl(
    INOUT p_etl_run_id BIGINT DEFAULT NULL
)
LANGUAGE PLPGSQL
AS $$
DECLARE
    v_error TEXT;
BEGIN
    INSERT INTO warehouse.etl_runs (pipeline_name, status)
    VALUES ('covid_warehouse_sql_etl', 'running')
    RETURNING etl_run_id INTO p_etl_run_id;

    BEGIN
        CALL warehouse.etl_extract(p_etl_run_id);
        CALL warehouse.etl_transform(p_etl_run_id);
        CALL warehouse.etl_load(p_etl_run_id);
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
            UPDATE warehouse.etl_runs
            SET status = 'failed',
                finished_at = clock_timestamp(),
                error_message = v_error,
                updated_at = clock_timestamp()
            WHERE etl_run_id = p_etl_run_id;
    END;
END;
$$;
