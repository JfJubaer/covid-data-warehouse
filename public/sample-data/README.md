# Synthetic Bangladesh COVID-19 sample data

These four CSVs are fabricated demonstration data, not actual historical
COVID-19 statistics. They cover 45 illustrative dates, January 1 through
February 14, 2025, and eight Bangladesh division/district pairs. Hospital
names, vaccine brands, populations, and every measurement are synthetic.

## Files and columns

### `covid_cases.csv` — 363 data rows

| Column | Description |
| --- | --- |
| `report_date` | Illustrative report date; formats vary between rows. |
| `country` | Country label. |
| `division` | Division label. |
| `district` | District label; some rows contain inconsistent spelling or extra spaces. |
| `population` | Fabricated district population estimate. |
| `new_cases` | Fabricated new cases reported for the date. |
| `total_cases` | Fabricated cumulative cases for the district. |
| `deaths` | Fabricated cumulative deaths. |
| `recoveries` | Fabricated cumulative recoveries. |
| `icu_patients` | Fabricated patients in intensive care. |

### `hospital_data.csv` — 542 data rows

| Column | Description |
| --- | --- |
| `report_date` | Illustrative report date; formats vary between rows. |
| `country` | Country label. |
| `division` | Division label. |
| `district` | District label; some rows contain inconsistent spelling or extra spaces. |
| `population` | Fabricated district population estimate. |
| `hospital_name` | Fabricated hospital name. |
| `hospital_type` | Fabricated facility category, such as public or private. |
| `hospital_capacity` | Fabricated total hospital bed capacity. |
| `icu_capacity` | Fabricated intensive-care bed capacity. |
| `occupied_beds` | Fabricated occupied hospital beds. |
| `icu_patients` | Fabricated intensive-care patients. |

### `vaccination_data.csv` — 1,083 data rows

Each row describes one vaccine product in one district on one date. Vaccine
brands and manufacturers are fictional. Product-specific counts must not be
mistaken for a deduplicated location-wide total.

| Column | Description |
| --- | --- |
| `report_date` | Illustrative report date; formats vary between rows. |
| `country` | Country label. |
| `division` | Division label. |
| `district` | District label; some rows contain inconsistent spelling or extra spaces. |
| `population` | Fabricated district population estimate. |
| `vaccine_name` | Fabricated vaccine product name. |
| `manufacturer` | Fabricated manufacturer name. |
| `vaccinations` | Fabricated doses administered for this product on the date. |
| `people_vaccinated` | Fabricated cumulative product-specific first-dose count. |
| `people_fully_vaccinated` | Fabricated cumulative product-specific full-course count. |

### `testing_data.csv` — 723 data rows

| Column | Description |
| --- | --- |
| `report_date` | Illustrative report date; formats vary between rows. |
| `country` | Country label. |
| `division` | Division label. |
| `district` | District label; some rows contain inconsistent spelling or extra spaces. |
| `population` | Fabricated district population estimate. |
| `test_type` | Test method: PCR or antigen. |
| `tests` | Fabricated tests conducted. |
| `tests_positive` | Fabricated positive test results. |
| `tests_negative` | Fabricated negative test results. |
| `tests_invalid` | Fabricated invalid test results. |

## Intentional data-quality examples

The datasets include exact duplicate rows, missing cells, invalid or negative
numeric values, four date formats (`YYYY-MM-DD`, `DD/MM/YYYY`, `Mon DD, YYYY`,
and `DD-Mon-YYYY`), inconsistent `Cox's Bazar`/`Coxs Bazar` spelling, and
leading or trailing spaces in selected text values. Keep these values intact
in the raw layer and handle them during staging/cleaning.

## Importing to the PostgreSQL raw tables

The raw tables use the project's generic CSV landing format: each source row
is stored with its source filename and row number, the CSV header in
`source_headers`, and the corresponding unmodified CSV cell strings in
`source_values`. The first CSV line is the header; the first data row has
`source_row_number = 2`. Preserve empty cells as empty strings (or a consistent
raw null representation) and do not parse dates or numbers on raw import.
Insert into the corresponding table:

| CSV | Raw table |
| --- | --- |
| `covid_cases.csv` | `raw_data.raw_covid_cases` |
| `hospital_data.csv` | `raw_data.raw_hospitals` |
| `vaccination_data.csv` | `raw_data.raw_vaccinations` |
| `testing_data.csv` | `raw_data.raw_testing` |

Because the raw tables store header/value arrays rather than one database
column per CSV field, import with a CSV loader that maps each header row and
data row into `source_headers` and `source_values`; a direct `COPY` into the
raw table's columns is not compatible with this schema. Keep the CSV files
unchanged as the source artifacts.
