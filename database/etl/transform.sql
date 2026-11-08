CREATE OR REPLACE PROCEDURE warehouse.etl_transform(p_etl_run_id BIGINT)
LANGUAGE PLPGSQL
AS $$
DECLARE
    v_status TEXT;
    v_invalid BIGINT;
    v_duplicates BIGINT;
    v_rejected BIGINT;
    v_extracted BIGINT;
BEGIN
    SELECT status INTO v_status
    FROM warehouse.etl_runs
    WHERE etl_run_id = p_etl_run_id
    FOR UPDATE;
    IF NOT FOUND OR v_status <> 'running' THEN
        RAISE EXCEPTION 'ETL run % does not exist or is not running', p_etl_run_id;
    END IF;

    UPDATE staging.stg_covid_cases AS s
    SET report_date = warehouse.try_csv_date(
            warehouse.source_field(s.source_headers, s.source_values, 'report_date')
        ),
        country = NULLIF(initcap(btrim(
            warehouse.source_field(s.source_headers, s.source_values, 'country')
        )), ''),
        division = NULLIF(warehouse.normalize_division(
            warehouse.source_field(s.source_headers, s.source_values, 'division')
        ), ''),
        district = NULLIF(warehouse.normalize_district(
            warehouse.source_field(s.source_headers, s.source_values, 'district')
        ), ''),
        population = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'population')),
        new_cases = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'new_cases')),
        total_cases = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'total_cases')),
        deaths = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'deaths')),
        recoveries = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'recoveries')),
        icu_patients = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'icu_patients'))
    WHERE s.etl_run_id = p_etl_run_id;

    UPDATE staging.stg_hospitals AS s
    SET report_date = warehouse.try_csv_date(
            warehouse.source_field(s.source_headers, s.source_values, 'report_date')
        ),
        country = NULLIF(initcap(btrim(
            warehouse.source_field(s.source_headers, s.source_values, 'country')
        )), ''),
        division = NULLIF(warehouse.normalize_division(
            warehouse.source_field(s.source_headers, s.source_values, 'division')
        ), ''),
        district = NULLIF(warehouse.normalize_district(
            warehouse.source_field(s.source_headers, s.source_values, 'district')
        ), ''),
        population = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'population')),
        hospital_name = NULLIF(btrim(warehouse.source_field(s.source_headers, s.source_values, 'hospital_name')), ''),
        hospital_type = NULLIF(initcap(btrim(warehouse.source_field(s.source_headers, s.source_values, 'hospital_type'))), ''),
        hospital_capacity = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'hospital_capacity')),
        icu_capacity = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'icu_capacity')),
        occupied_beds = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'occupied_beds')),
        icu_patients = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'icu_patients'))
    WHERE s.etl_run_id = p_etl_run_id;

    UPDATE staging.stg_vaccinations AS s
    SET report_date = warehouse.try_csv_date(
            warehouse.source_field(s.source_headers, s.source_values, 'report_date')
        ),
        country = NULLIF(initcap(btrim(
            warehouse.source_field(s.source_headers, s.source_values, 'country')
        )), ''),
        division = NULLIF(warehouse.normalize_division(
            warehouse.source_field(s.source_headers, s.source_values, 'division')
        ), ''),
        district = NULLIF(warehouse.normalize_district(
            warehouse.source_field(s.source_headers, s.source_values, 'district')
        ), ''),
        population = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'population')),
        vaccine_name = NULLIF(btrim(warehouse.source_field(s.source_headers, s.source_values, 'vaccine_name')), ''),
        manufacturer = NULLIF(btrim(warehouse.source_field(s.source_headers, s.source_values, 'manufacturer')), ''),
        vaccinations = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'vaccinations')),
        people_vaccinated = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'people_vaccinated')),
        people_fully_vaccinated = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'people_fully_vaccinated'))
    WHERE s.etl_run_id = p_etl_run_id;

    UPDATE staging.stg_testing AS s
    SET report_date = warehouse.try_csv_date(
            warehouse.source_field(s.source_headers, s.source_values, 'report_date')
        ),
        country = NULLIF(initcap(btrim(
            warehouse.source_field(s.source_headers, s.source_values, 'country')
        )), ''),
        division = NULLIF(warehouse.normalize_division(
            warehouse.source_field(s.source_headers, s.source_values, 'division')
        ), ''),
        district = NULLIF(warehouse.normalize_district(
            warehouse.source_field(s.source_headers, s.source_values, 'district')
        ), ''),
        population = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'population')),
        test_type = CASE regexp_replace(
            upper(btrim(warehouse.source_field(s.source_headers, s.source_values, 'test_type'))),
            '[^A-Z0-9]', '', 'g'
        )
            WHEN 'PCR' THEN 'PCR'
            WHEN 'ANTIGEN' THEN 'Antigen'
            ELSE NULL
        END,
        tests = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'tests')),
        tests_positive = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'tests_positive')),
        tests_negative = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'tests_negative')),
        tests_invalid = warehouse.try_csv_bigint(warehouse.source_field(s.source_headers, s.source_values, 'tests_invalid'))
    WHERE s.etl_run_id = p_etl_run_id;

    INSERT INTO warehouse.rejected_records
        (etl_run_id, source_table, source_raw_id, source_file,
         source_row_number, rejection_reason, rejected_values)
    SELECT p_etl_run_id, 'raw_covid_cases', s.source_raw_id, r.source_file,
           r.source_row_number, reason.rejection_reason,
           jsonb_build_object('headers', s.source_headers, 'values', s.source_values)
    FROM staging.stg_covid_cases AS s
    JOIN raw_data.raw_covid_cases AS r ON r.raw_id = s.source_raw_id
    CROSS JOIN LATERAL (
        SELECT warehouse.source_rejection_reason(
            'raw_covid_cases', s.source_headers, s.source_values
        ) AS rejection_reason
    ) AS reason
    WHERE s.etl_run_id = p_etl_run_id
      AND reason.rejection_reason IS NOT NULL
    ON CONFLICT (etl_run_id, source_table, source_raw_id, rejection_reason)
        WHERE source_raw_id IS NOT NULL
        DO NOTHING;

    INSERT INTO warehouse.rejected_records
        (etl_run_id, source_table, source_raw_id, source_file,
         source_row_number, rejection_reason, rejected_values)
    SELECT p_etl_run_id, 'raw_hospitals', s.source_raw_id, r.source_file,
           r.source_row_number, reason.rejection_reason,
           jsonb_build_object('headers', s.source_headers, 'values', s.source_values)
    FROM staging.stg_hospitals AS s
    JOIN raw_data.raw_hospitals AS r ON r.raw_id = s.source_raw_id
    CROSS JOIN LATERAL (
        SELECT warehouse.source_rejection_reason(
            'raw_hospitals', s.source_headers, s.source_values
        ) AS rejection_reason
    ) AS reason
    WHERE s.etl_run_id = p_etl_run_id
      AND reason.rejection_reason IS NOT NULL
    ON CONFLICT (etl_run_id, source_table, source_raw_id, rejection_reason)
        WHERE source_raw_id IS NOT NULL
        DO NOTHING;

    INSERT INTO warehouse.rejected_records
        (etl_run_id, source_table, source_raw_id, source_file,
         source_row_number, rejection_reason, rejected_values)
    SELECT p_etl_run_id, 'raw_vaccinations', s.source_raw_id, r.source_file,
           r.source_row_number, reason.rejection_reason,
           jsonb_build_object('headers', s.source_headers, 'values', s.source_values)
    FROM staging.stg_vaccinations AS s
    JOIN raw_data.raw_vaccinations AS r ON r.raw_id = s.source_raw_id
    CROSS JOIN LATERAL (
        SELECT warehouse.source_rejection_reason(
            'raw_vaccinations', s.source_headers, s.source_values
        ) AS rejection_reason
    ) AS reason
    WHERE s.etl_run_id = p_etl_run_id
      AND reason.rejection_reason IS NOT NULL
    ON CONFLICT (etl_run_id, source_table, source_raw_id, rejection_reason)
        WHERE source_raw_id IS NOT NULL
        DO NOTHING;

    INSERT INTO warehouse.rejected_records
        (etl_run_id, source_table, source_raw_id, source_file,
         source_row_number, rejection_reason, rejected_values)
    SELECT p_etl_run_id, 'raw_testing', s.source_raw_id, r.source_file,
           r.source_row_number, reason.rejection_reason,
           jsonb_build_object('headers', s.source_headers, 'values', s.source_values)
    FROM staging.stg_testing AS s
    JOIN raw_data.raw_testing AS r ON r.raw_id = s.source_raw_id
    CROSS JOIN LATERAL (
        SELECT warehouse.source_rejection_reason(
            'raw_testing', s.source_headers, s.source_values
        ) AS rejection_reason
    ) AS reason
    WHERE s.etl_run_id = p_etl_run_id
      AND reason.rejection_reason IS NOT NULL
    ON CONFLICT (etl_run_id, source_table, source_raw_id, rejection_reason)
        WHERE source_raw_id IS NOT NULL
        DO NOTHING;

    WITH ranked AS (
        SELECT s.source_raw_id,
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
    )
    INSERT INTO warehouse.rejected_records
        (etl_run_id, source_table, source_raw_id, source_file,
         source_row_number, rejection_reason, rejected_values)
    SELECT p_etl_run_id, 'raw_covid_cases', ranked.source_raw_id,
           raw.source_file, raw.source_row_number,
           'Duplicate business key: report_date, country, division, district',
           jsonb_build_object('headers', raw.source_headers, 'values', raw.source_values)
    FROM ranked
    JOIN raw_data.raw_covid_cases AS raw ON raw.raw_id = ranked.source_raw_id
    WHERE ranked.duplicate_number > 1
    ON CONFLICT (etl_run_id, source_table, source_raw_id, rejection_reason)
        WHERE source_raw_id IS NOT NULL
        DO NOTHING;

    WITH ranked AS (
        SELECT s.source_raw_id,
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
    INSERT INTO warehouse.rejected_records
        (etl_run_id, source_table, source_raw_id, source_file,
         source_row_number, rejection_reason, rejected_values)
    SELECT p_etl_run_id, 'raw_hospitals', ranked.source_raw_id,
           raw.source_file, raw.source_row_number,
           'Duplicate business key: report_date, location, hospital_name, hospital_type',
           jsonb_build_object('headers', raw.source_headers, 'values', raw.source_values)
    FROM ranked
    JOIN raw_data.raw_hospitals AS raw ON raw.raw_id = ranked.source_raw_id
    WHERE ranked.duplicate_number > 1
    ON CONFLICT (etl_run_id, source_table, source_raw_id, rejection_reason)
        WHERE source_raw_id IS NOT NULL
        DO NOTHING;

    WITH ranked AS (
        SELECT s.source_raw_id,
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
    )
    INSERT INTO warehouse.rejected_records
        (etl_run_id, source_table, source_raw_id, source_file,
         source_row_number, rejection_reason, rejected_values)
    SELECT p_etl_run_id, 'raw_vaccinations', ranked.source_raw_id,
           raw.source_file, raw.source_row_number,
           'Duplicate business key: report_date, location, vaccine_name, manufacturer',
           jsonb_build_object('headers', raw.source_headers, 'values', raw.source_values)
    FROM ranked
    JOIN raw_data.raw_vaccinations AS raw ON raw.raw_id = ranked.source_raw_id
    WHERE ranked.duplicate_number > 1
    ON CONFLICT (etl_run_id, source_table, source_raw_id, rejection_reason)
        WHERE source_raw_id IS NOT NULL
        DO NOTHING;

    WITH ranked AS (
        SELECT s.source_raw_id,
               row_number() OVER (
                   PARTITION BY s.report_date, s.country, s.division, s.district,
                                s.test_type
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
    )
    INSERT INTO warehouse.rejected_records
        (etl_run_id, source_table, source_raw_id, source_file,
         source_row_number, rejection_reason, rejected_values)
    SELECT p_etl_run_id, 'raw_testing', ranked.source_raw_id,
           raw.source_file, raw.source_row_number,
           'Duplicate business key: report_date, location, test_type',
           jsonb_build_object('headers', raw.source_headers, 'values', raw.source_values)
    FROM ranked
    JOIN raw_data.raw_testing AS raw ON raw.raw_id = ranked.source_raw_id
    WHERE ranked.duplicate_number > 1
    ON CONFLICT (etl_run_id, source_table, source_raw_id, rejection_reason)
        WHERE source_raw_id IS NOT NULL
        DO NOTHING;

    SELECT COUNT(*) INTO v_extracted
    FROM (
        SELECT source_raw_id FROM staging.stg_covid_cases WHERE etl_run_id = p_etl_run_id
        UNION ALL
        SELECT source_raw_id FROM staging.stg_hospitals WHERE etl_run_id = p_etl_run_id
        UNION ALL
        SELECT source_raw_id FROM staging.stg_vaccinations WHERE etl_run_id = p_etl_run_id
        UNION ALL
        SELECT source_raw_id FROM staging.stg_testing WHERE etl_run_id = p_etl_run_id
    ) AS all_extracted;

    SELECT COUNT(*) INTO v_invalid
    FROM warehouse.rejected_records
    WHERE etl_run_id = p_etl_run_id
      AND rejection_reason NOT LIKE 'Duplicate business key:%';

    SELECT COUNT(*) INTO v_duplicates
    FROM warehouse.rejected_records
    WHERE etl_run_id = p_etl_run_id
      AND rejection_reason LIKE 'Duplicate business key:%';

    SELECT COUNT(*) INTO v_rejected
    FROM warehouse.rejected_records
    WHERE etl_run_id = p_etl_run_id;

    UPDATE warehouse.etl_runs
    SET rows_extracted = v_extracted,
        rows_read = v_extracted,
        rows_duplicates = v_duplicates,
        rows_rejected = v_rejected,
        rows_cleaned = v_extracted - v_rejected,
        updated_at = clock_timestamp()
    WHERE etl_run_id = p_etl_run_id;
END;
$$;
