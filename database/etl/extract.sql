-- ETL installation: schema-compatible staging columns, run metrics, and helpers.
ALTER TABLE warehouse.etl_runs
    ADD COLUMN IF NOT EXISTS rows_extracted BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS rows_duplicates BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS rows_cleaned BIGINT NOT NULL DEFAULT 0;

ALTER TABLE staging.stg_covid_cases
    ADD COLUMN IF NOT EXISTS source_headers TEXT[],
    ADD COLUMN IF NOT EXISTS source_values TEXT[];

ALTER TABLE staging.stg_hospitals
    ADD COLUMN IF NOT EXISTS source_headers TEXT[],
    ADD COLUMN IF NOT EXISTS source_values TEXT[],
    ADD COLUMN IF NOT EXISTS icu_capacity BIGINT,
    ADD COLUMN IF NOT EXISTS occupied_beds BIGINT;

ALTER TABLE staging.stg_vaccinations
    ADD COLUMN IF NOT EXISTS source_headers TEXT[],
    ADD COLUMN IF NOT EXISTS source_values TEXT[],
    ADD COLUMN IF NOT EXISTS people_vaccinated BIGINT,
    ADD COLUMN IF NOT EXISTS people_fully_vaccinated BIGINT;

ALTER TABLE staging.stg_testing
    ADD COLUMN IF NOT EXISTS source_headers TEXT[],
    ADD COLUMN IF NOT EXISTS source_values TEXT[],
    ADD COLUMN IF NOT EXISTS test_type TEXT,
    ADD COLUMN IF NOT EXISTS tests_positive BIGINT,
    ADD COLUMN IF NOT EXISTS tests_negative BIGINT,
    ADD COLUMN IF NOT EXISTS tests_invalid BIGINT;

ALTER TABLE warehouse.dim_hospital
    ADD COLUMN IF NOT EXISTS icu_capacity BIGINT
        CHECK (icu_capacity IS NULL OR icu_capacity >= 0);

CREATE UNIQUE INDEX IF NOT EXISTS dim_hospital_natural_key
    ON warehouse.dim_hospital (
        (lower(btrim(hospital_name))),
        (COALESCE(lower(btrim(hospital_type)), ''))
    );

CREATE UNIQUE INDEX IF NOT EXISTS rejected_records_run_source_reason
    ON warehouse.rejected_records
        (etl_run_id, source_table, source_raw_id, rejection_reason)
    WHERE source_raw_id IS NOT NULL;

CREATE OR REPLACE FUNCTION warehouse.csv_value(
    p_headers TEXT[],
    p_values TEXT[],
    p_aliases TEXT[]
)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT p_values[h.ordinality::INTEGER]
    FROM unnest(COALESCE(p_aliases, ARRAY[]::TEXT[]))
        WITH ORDINALITY AS a(alias, alias_order)
    JOIN unnest(COALESCE(p_headers, ARRAY[]::TEXT[]))
        WITH ORDINALITY AS h(header, ordinality)
      ON regexp_replace(lower(btrim(h.header)), '[^a-z0-9]', '', 'g')
       = regexp_replace(lower(btrim(a.alias)), '[^a-z0-9]', '', 'g')
    WHERE h.ordinality <= CARDINALITY(COALESCE(p_values, ARRAY[]::TEXT[]))
    ORDER BY a.alias_order, h.ordinality
    LIMIT 1
$$;

CREATE OR REPLACE FUNCTION warehouse.source_field(
    p_headers TEXT[],
    p_values TEXT[],
    p_field TEXT
)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT warehouse.csv_value(
        p_headers,
        p_values,
        CASE p_field
            WHEN 'report_date' THEN ARRAY['report_date', 'date', 'reporting_date']
            WHEN 'country' THEN ARRAY['country', 'country_name', 'country_region']
            WHEN 'division' THEN ARRAY['division', 'state', 'province']
            WHEN 'district' THEN ARRAY['district', 'county', 'city']
            WHEN 'population' THEN ARRAY['population', 'population_total']
            WHEN 'new_cases' THEN ARRAY['new_cases', 'newcases', 'cases']
            WHEN 'total_cases' THEN ARRAY['total_cases', 'totalcases', 'cumulative_cases']
            WHEN 'deaths' THEN ARRAY['deaths', 'death']
            WHEN 'recoveries' THEN ARRAY['recoveries', 'recovered']
            WHEN 'icu_patients' THEN ARRAY['icu_patients', 'icu_patient', 'icu']
            WHEN 'hospital_name' THEN ARRAY['hospital_name', 'facility_name', 'facility']
            WHEN 'hospital_type' THEN ARRAY['hospital_type', 'facility_type', 'type']
            WHEN 'hospital_capacity' THEN ARRAY['hospital_capacity', 'bed_capacity', 'capacity']
            WHEN 'icu_capacity' THEN ARRAY['icu_capacity', 'icu_beds']
            WHEN 'occupied_beds' THEN ARRAY['occupied_beds', 'beds_occupied']
            WHEN 'vaccine_name' THEN ARRAY['vaccine_name', 'vaccine', 'product']
            WHEN 'manufacturer' THEN ARRAY['manufacturer', 'vaccine_manufacturer']
            WHEN 'vaccinations' THEN ARRAY['vaccinations', 'doses_administered', 'daily_doses']
            WHEN 'people_vaccinated' THEN ARRAY['people_vaccinated', 'people_vaccinated_total']
            WHEN 'people_fully_vaccinated' THEN ARRAY['people_fully_vaccinated', 'fully_vaccinated']
            WHEN 'test_type' THEN ARRAY['test_type', 'test_method', 'method']
            WHEN 'tests' THEN ARRAY['tests', 'total_tests', 'test_count']
            WHEN 'tests_positive' THEN ARRAY['tests_positive', 'positive_tests']
            WHEN 'tests_negative' THEN ARRAY['tests_negative', 'negative_tests']
            WHEN 'tests_invalid' THEN ARRAY['tests_invalid', 'invalid_tests']
            ELSE ARRAY[p_field]
        END
    )
$$;

CREATE OR REPLACE FUNCTION warehouse.try_csv_bigint(p_value TEXT)
RETURNS BIGINT
LANGUAGE PLPGSQL
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
    v_value TEXT := btrim(p_value);
BEGIN
    IF v_value IS NULL OR v_value = '' THEN
        RETURN NULL;
    END IF;
    IF v_value !~ '^[+-]?[0-9]+$' THEN
        RETURN NULL;
    END IF;
    RETURN v_value::BIGINT;
EXCEPTION
    WHEN numeric_value_out_of_range THEN
        RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION warehouse.try_csv_date(p_value TEXT)
RETURNS DATE
LANGUAGE PLPGSQL
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
    v_value TEXT := btrim(p_value);
    v_date DATE;
BEGIN
    IF v_value IS NULL OR v_value = '' THEN
        RETURN NULL;
    ELSIF v_value ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
        v_date := to_date(v_value, 'FXYYYY-MM-DD');
        IF to_char(v_date, 'YYYY-MM-DD') = v_value THEN
            RETURN v_date;
        END IF;
    ELSIF v_value ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN
        v_date := to_date(v_value, 'FXDD/MM/YYYY');
        IF to_char(v_date, 'DD/MM/YYYY') = v_value THEN
            RETURN v_date;
        END IF;
    ELSIF v_value ~ '^[A-Za-z]{3} [0-9]{2}, [0-9]{4}$' THEN
        v_date := to_date(v_value, 'Mon DD, YYYY');
        IF lower(to_char(v_date, 'Mon DD, YYYY')) = lower(v_value) THEN
            RETURN v_date;
        END IF;
    ELSIF v_value ~ '^[0-9]{2}-[A-Za-z]{3}-[0-9]{4}$' THEN
        v_date := to_date(v_value, 'DD-Mon-YYYY');
        IF lower(to_char(v_date, 'DD-Mon-YYYY')) = lower(v_value) THEN
            RETURN v_date;
        END IF;
    END IF;
    RETURN NULL;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION warehouse.normalize_division(p_value TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE regexp_replace(lower(btrim(p_value)), '[^a-z0-9]', '', 'g')
        WHEN 'chittagong' THEN 'Chattogram'
        WHEN 'chattogram' THEN 'Chattogram'
        WHEN 'barisal' THEN 'Barishal'
        WHEN 'barishal' THEN 'Barishal'
        ELSE initcap(regexp_replace(btrim(p_value), '\s+', ' ', 'g'))
    END
$$;

CREATE OR REPLACE FUNCTION warehouse.normalize_district(p_value TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE regexp_replace(lower(btrim(p_value)), '[^a-z0-9]', '', 'g')
        WHEN 'coxsBazar' THEN 'Cox''s Bazar'
        WHEN 'coxsbazar' THEN 'Cox''s Bazar'
        ELSE initcap(regexp_replace(btrim(p_value), '\s+', ' ', 'g'))
    END
$$;

CREATE OR REPLACE FUNCTION warehouse.source_rejection_reason(
    p_source TEXT,
    p_headers TEXT[],
    p_values TEXT[]
)
RETURNS TEXT
LANGUAGE PLPGSQL
IMMUTABLE
AS $$
DECLARE
    v_reason TEXT := '';
    v_value TEXT;
    v_number BIGINT;
    v_field TEXT;
    v_fields TEXT[];
    v_required_name TEXT;
    v_date TEXT := warehouse.source_field(p_headers, p_values, 'report_date');
    v_test_type TEXT;
BEGIN
    IF NULLIF(btrim(v_date), '') IS NULL THEN
        v_reason := concat_ws('; ', NULLIF(v_reason, ''), 'Missing report_date');
    ELSIF warehouse.try_csv_date(v_date) IS NULL THEN
        v_reason := concat_ws('; ', NULLIF(v_reason, ''), 'Invalid report_date format');
    END IF;

    IF NULLIF(btrim(warehouse.source_field(p_headers, p_values, 'country')), '') IS NULL THEN
        v_reason := concat_ws('; ', NULLIF(v_reason, ''), 'Missing country');
    END IF;
    IF NULLIF(btrim(warehouse.source_field(p_headers, p_values, 'division')), '') IS NULL THEN
        v_reason := concat_ws('; ', NULLIF(v_reason, ''), 'Missing division');
    END IF;
    IF NULLIF(btrim(warehouse.source_field(p_headers, p_values, 'district')), '') IS NULL THEN
        v_reason := concat_ws('; ', NULLIF(v_reason, ''), 'Missing district');
    END IF;

    IF p_source = 'raw_hospitals' THEN
        v_required_name := warehouse.source_field(p_headers, p_values, 'hospital_name');
        IF NULLIF(btrim(v_required_name), '') IS NULL THEN
            v_reason := concat_ws('; ', NULLIF(v_reason, ''), 'Missing hospital_name');
        END IF;
        v_fields := ARRAY[
            'population', 'hospital_capacity', 'icu_capacity',
            'occupied_beds', 'icu_patients'
        ];
    ELSIF p_source = 'raw_vaccinations' THEN
        v_required_name := warehouse.source_field(p_headers, p_values, 'vaccine_name');
        IF NULLIF(btrim(v_required_name), '') IS NULL THEN
            v_reason := concat_ws('; ', NULLIF(v_reason, ''), 'Missing vaccine_name');
        END IF;
        v_fields := ARRAY[
            'population', 'vaccinations',
            'people_vaccinated', 'people_fully_vaccinated'
        ];
    ELSIF p_source = 'raw_testing' THEN
        v_test_type := regexp_replace(
            upper(btrim(warehouse.source_field(p_headers, p_values, 'test_type'))),
            '[^A-Z0-9]', '', 'g'
        );
        IF v_test_type NOT IN ('PCR', 'ANTIGEN') OR v_test_type IS NULL THEN
            v_reason := concat_ws('; ', NULLIF(v_reason, ''), 'Missing or unsupported test_type');
        END IF;
        v_fields := ARRAY[
            'population', 'tests', 'tests_positive', 'tests_negative', 'tests_invalid'
        ];
    ELSE
        v_fields := ARRAY[
            'population', 'new_cases', 'total_cases', 'deaths',
            'recoveries', 'icu_patients'
        ];
    END IF;

    FOREACH v_field IN ARRAY v_fields LOOP
        v_value := warehouse.source_field(p_headers, p_values, v_field);
        IF NULLIF(btrim(v_value), '') IS NOT NULL THEN
            v_number := warehouse.try_csv_bigint(v_value);
            IF v_number IS NULL THEN
                v_reason := concat_ws(
                    '; ', NULLIF(v_reason, ''),
                    format('Invalid numeric value for %s', v_field)
                );
            ELSIF v_number < 0 THEN
                v_reason := concat_ws(
                    '; ', NULLIF(v_reason, ''),
                    format('Negative value for %s', v_field)
                );
            END IF;
        END IF;
    END LOOP;

    RETURN NULLIF(v_reason, '');
END;
$$;

CREATE OR REPLACE PROCEDURE warehouse.etl_extract(p_etl_run_id BIGINT)
LANGUAGE PLPGSQL
AS $$
DECLARE
    v_status TEXT;
    v_rows BIGINT := 0;
    v_inserted BIGINT;
BEGIN
    SELECT status INTO v_status
    FROM warehouse.etl_runs
    WHERE etl_run_id = p_etl_run_id
    FOR UPDATE;
    IF NOT FOUND OR v_status <> 'running' THEN
        RAISE EXCEPTION 'ETL run % does not exist or is not running', p_etl_run_id;
    END IF;

    INSERT INTO staging.stg_covid_cases
        (etl_run_id, source_raw_id, source_headers, source_values)
    SELECT p_etl_run_id, raw_id, source_headers, source_values
    FROM raw_data.raw_covid_cases
    ON CONFLICT (etl_run_id, source_raw_id) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_rows := v_rows + v_inserted;

    INSERT INTO staging.stg_hospitals
        (etl_run_id, source_raw_id, source_headers, source_values)
    SELECT p_etl_run_id, raw_id, source_headers, source_values
    FROM raw_data.raw_hospitals
    ON CONFLICT (etl_run_id, source_raw_id) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_rows := v_rows + v_inserted;

    INSERT INTO staging.stg_vaccinations
        (etl_run_id, source_raw_id, source_headers, source_values)
    SELECT p_etl_run_id, raw_id, source_headers, source_values
    FROM raw_data.raw_vaccinations
    ON CONFLICT (etl_run_id, source_raw_id) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_rows := v_rows + v_inserted;

    INSERT INTO staging.stg_testing
        (etl_run_id, source_raw_id, source_headers, source_values)
    SELECT p_etl_run_id, raw_id, source_headers, source_values
    FROM raw_data.raw_testing
    ON CONFLICT (etl_run_id, source_raw_id) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_rows := v_rows + v_inserted;

    UPDATE warehouse.etl_runs
    SET rows_extracted = rows_extracted + v_rows,
        rows_read = rows_read + v_rows,
        updated_at = clock_timestamp()
    WHERE etl_run_id = p_etl_run_id;
END;
$$;
