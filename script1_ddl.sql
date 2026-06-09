-- =============================================================================
-- OutbreakNet Pandemic Surveillance System
-- Script 1: DDL — Schema Definition
-- Author  : Senior Database Engineer
-- DBMS    : PostgreSQL 15+
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. HOUSEKEEPING
-- -----------------------------------------------------------------------------
SET client_min_messages = WARNING;

DROP TABLE IF EXISTS
    Daily_Statistics,
    Transmission_Chain,
    Hospital_Admissions,
    Patient_Symptoms,
    Symptoms,
    Patients,
    Variants,
    Hospitals,
    Cities
CASCADE;

DROP TYPE IF EXISTS
    patient_status_enum,
    admission_status_enum,
    severity_enum,
    transmission_mode_enum
CASCADE;

-- -----------------------------------------------------------------------------
-- 1. ENUMERATIONS  (domain-constrained categorical columns)
-- -----------------------------------------------------------------------------

CREATE TYPE patient_status_enum    AS ENUM ('Active', 'Recovered', 'Deceased', 'Quarantined');
CREATE TYPE admission_status_enum  AS ENUM ('Admitted', 'Discharged', 'ICU', 'Deceased');
CREATE TYPE severity_enum          AS ENUM ('Mild', 'Moderate', 'Severe', 'Critical');
CREATE TYPE transmission_mode_enum AS ENUM ('Direct_Contact', 'Airborne', 'Fomite', 'Unknown');

-- -----------------------------------------------------------------------------
-- 2. CITIES
-- -----------------------------------------------------------------------------

CREATE TABLE Cities (
    city_id          SERIAL          PRIMARY KEY,
    city_name        VARCHAR(100)    NOT NULL,
    country          VARCHAR(100)    NOT NULL DEFAULT 'Pakistan',
    province         VARCHAR(100),
    population       INTEGER         NOT NULL CHECK (population > 0),
    area_sq_km       NUMERIC(10, 2)  CHECK (area_sq_km > 0),
    -- Derived: population density — stored for query efficiency
    pop_density      NUMERIC(10, 2)  GENERATED ALWAYS AS
                         (population / NULLIF(area_sq_km, 0)) STORED,
    latitude         NUMERIC(9, 6),
    longitude        NUMERIC(9, 6),
    created_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_city_name_country UNIQUE (city_name, country)
);

COMMENT ON TABLE  Cities IS 'Reference table for all monitored metropolitan areas.';
COMMENT ON COLUMN Cities.pop_density IS 'Auto-computed: residents per km². High density correlates with faster R₀.';

-- -----------------------------------------------------------------------------
-- 3. HOSPITALS
-- -----------------------------------------------------------------------------

CREATE TABLE Hospitals (
    hospital_id         SERIAL          PRIMARY KEY,
    hospital_name       VARCHAR(200)    NOT NULL,
    city_id             INTEGER         NOT NULL  REFERENCES Cities(city_id) ON DELETE RESTRICT,
    address             TEXT,
    total_beds          INTEGER         NOT NULL  CHECK (total_beds >= 0),
    icu_beds_total      INTEGER         NOT NULL  CHECK (icu_beds_total >= 0),
    icu_bed_occupancy   INTEGER         NOT NULL  DEFAULT 0
                            CHECK (icu_bed_occupancy >= 0),
    ventilators         INTEGER         DEFAULT 0 CHECK (ventilators >= 0),
    is_designated_covid BOOLEAN         NOT NULL  DEFAULT FALSE,
    contact_number      VARCHAR(20),
    created_at          TIMESTAMPTZ     NOT NULL  DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL  DEFAULT NOW(),

    CONSTRAINT chk_icu_occupancy_cap
        CHECK (icu_bed_occupancy <= icu_beds_total),
    CONSTRAINT chk_icu_subset_of_total
        CHECK (icu_beds_total <= total_beds)
);

COMMENT ON TABLE  Hospitals IS 'Facility registry including real-time ICU capacity tracking.';
COMMENT ON COLUMN Hospitals.icu_bed_occupancy IS 'Maintained automatically by triggers on Hospital_Admissions.';

-- -----------------------------------------------------------------------------
-- 4. VARIANTS
-- -----------------------------------------------------------------------------

CREATE TABLE Variants (
    variant_id          SERIAL          PRIMARY KEY,
    variant_name        VARCHAR(100)    NOT NULL UNIQUE,
    who_label           VARCHAR(50),                   -- e.g. 'Omicron', 'Delta'
    lineage             VARCHAR(50),                   -- e.g. 'B.1.1.529'
    first_detected_date DATE,
    origin_country      VARCHAR(100),
    estimated_r0_min    NUMERIC(4, 2)   CHECK (estimated_r0_min >= 0),
    estimated_r0_max    NUMERIC(4, 2)   CHECK (estimated_r0_max >= 0),
    is_variant_of_concern BOOLEAN       NOT NULL DEFAULT FALSE,
    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_r0_range CHECK (estimated_r0_max >= estimated_r0_min)
);

COMMENT ON TABLE Variants IS 'Pathogen variant catalogue with epidemiological metadata.';

-- -----------------------------------------------------------------------------
-- 5. PATIENTS
-- -----------------------------------------------------------------------------

CREATE TABLE Patients (
    patient_id          SERIAL                  PRIMARY KEY,
    national_id         VARCHAR(20)             NOT NULL UNIQUE,  -- CNIC / passport
    first_name          VARCHAR(100)            NOT NULL,
    last_name           VARCHAR(100)            NOT NULL,
    date_of_birth       DATE                    NOT NULL,
    gender              CHAR(1)                 NOT NULL CHECK (gender IN ('M','F','O')),
    city_id             INTEGER                 NOT NULL REFERENCES Cities(city_id) ON DELETE RESTRICT,
    address             TEXT,
    phone               VARCHAR(20),
    email               VARCHAR(150),
    blood_type          VARCHAR(5)              CHECK (blood_type IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    -- Epidemiological fields
    diagnosis_date      DATE                    NOT NULL,
    variant_id          INTEGER                 REFERENCES Variants(variant_id) ON DELETE SET NULL,
    current_status      patient_status_enum     NOT NULL DEFAULT 'Active',
    is_vaccinated       BOOLEAN                 NOT NULL DEFAULT FALSE,
    vaccination_doses   SMALLINT                DEFAULT 0 CHECK (vaccination_doses BETWEEN 0 AND 5),
    comorbidities       TEXT[],                 -- e.g. ARRAY['Diabetes','Hypertension']
    notes               TEXT,
    created_at          TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ             NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_dob_past         CHECK (date_of_birth < CURRENT_DATE),
    CONSTRAINT chk_diagnosis_after_birth CHECK (diagnosis_date >= date_of_birth)
);

COMMENT ON TABLE  Patients IS 'Core entity. Every confirmed case is a row here.';
COMMENT ON COLUMN Patients.comorbidities IS 'PostgreSQL array — enables ANY(comorbidities) filtering.';

-- Age computed view helper (not stored to avoid staleness)
CREATE OR REPLACE VIEW v_patient_age AS
    SELECT patient_id,
           EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_of_birth))::INTEGER AS age_years
    FROM   Patients;

-- -----------------------------------------------------------------------------
-- 6. SYMPTOMS
-- -----------------------------------------------------------------------------

CREATE TABLE Symptoms (
    symptom_id      SERIAL          PRIMARY KEY,
    symptom_name    VARCHAR(100)    NOT NULL UNIQUE,
    icd10_code      VARCHAR(10),                    -- WHO ICD-10 code
    category        VARCHAR(50),                    -- e.g. 'Respiratory', 'Neurological'
    severity_weight NUMERIC(3, 2)   DEFAULT 1.00    -- for composite severity scoring
                        CHECK (severity_weight BETWEEN 0.1 AND 5.0),
    description     TEXT,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE Symptoms IS 'Controlled vocabulary for all reportable symptoms.';

-- -----------------------------------------------------------------------------
-- 7. PATIENT_SYMPTOMS  (Junction / Bridge Table)
-- -----------------------------------------------------------------------------

CREATE TABLE Patient_Symptoms (
    patient_symptom_id  SERIAL              PRIMARY KEY,
    patient_id          INTEGER             NOT NULL REFERENCES Patients(patient_id)  ON DELETE CASCADE,
    symptom_id          INTEGER             NOT NULL REFERENCES Symptoms(symptom_id)  ON DELETE RESTRICT,
    onset_date          DATE                NOT NULL,
    resolution_date     DATE,
    severity            severity_enum       NOT NULL DEFAULT 'Mild',
    notes               TEXT,
    recorded_at         TIMESTAMPTZ         NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_patient_symptom_onset UNIQUE (patient_id, symptom_id, onset_date),
    CONSTRAINT chk_resolution_after_onset
        CHECK (resolution_date IS NULL OR resolution_date >= onset_date)
);

COMMENT ON TABLE Patient_Symptoms IS 'M:N bridge between patients and symptoms with temporal tracking.';

-- -----------------------------------------------------------------------------
-- 8. HOSPITAL_ADMISSIONS
-- -----------------------------------------------------------------------------

CREATE TABLE Hospital_Admissions (
    admission_id        SERIAL              PRIMARY KEY,
    patient_id          INTEGER             NOT NULL REFERENCES Patients(patient_id)   ON DELETE RESTRICT,
    hospital_id         INTEGER             NOT NULL REFERENCES Hospitals(hospital_id) ON DELETE RESTRICT,
    admission_date      DATE                NOT NULL,
    discharge_date      DATE,
    admission_status    admission_status_enum NOT NULL DEFAULT 'Admitted',
    ward                VARCHAR(50),        -- e.g. 'ICU', 'General', 'Isolation'
    attending_physician VARCHAR(200),
    severity_on_entry   severity_enum,
    notes               TEXT,
    created_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_discharge_after_admission
        CHECK (discharge_date IS NULL OR discharge_date >= admission_date),
    -- A patient can only have one active (non-discharged) admission at a time
    CONSTRAINT uq_active_admission
        UNIQUE NULLS NOT DISTINCT (patient_id, discharge_date)
);

COMMENT ON TABLE  Hospital_Admissions IS 'Each row is one inpatient stay. Trigger fires on status → Deceased.';
COMMENT ON COLUMN Hospital_Admissions.admission_status IS
    'Trigger on UPDATE fires when this transitions to ''Deceased'' to update stats & free ICU bed.';

-- -----------------------------------------------------------------------------
-- 9. TRANSMISSION_CHAIN  (Self-Referencing — the "Killer Feature")
-- -----------------------------------------------------------------------------

CREATE TABLE Transmission_Chain (
    transmission_id     SERIAL                  PRIMARY KEY,
    source_patient_id   INTEGER                 REFERENCES Patients(patient_id) ON DELETE SET NULL,
                        -- NULL = community/unknown source (i.e., Patient Zero candidates)
    target_patient_id   INTEGER                 NOT NULL REFERENCES Patients(patient_id) ON DELETE CASCADE,
    transmission_date   DATE                    NOT NULL,
    transmission_mode   transmission_mode_enum  NOT NULL DEFAULT 'Unknown',
    location_of_event   VARCHAR(200),           -- free-text: 'Wedding Hall, Lahore'
    city_id             INTEGER                 REFERENCES Cities(city_id) ON DELETE SET NULL,
    confidence_score    NUMERIC(4, 3)           DEFAULT 0.500
                            CHECK (confidence_score BETWEEN 0.000 AND 1.000),
    contact_duration_hrs NUMERIC(5, 2)          CHECK (contact_duration_hrs > 0),
    is_confirmed        BOOLEAN                 NOT NULL DEFAULT FALSE,
    notes               TEXT,
    created_at          TIMESTAMPTZ             NOT NULL DEFAULT NOW(),

    -- Prevent self-transmission
    CONSTRAINT chk_no_self_transmission
        CHECK (source_patient_id IS DISTINCT FROM target_patient_id),
    -- A target can only have one confirmed primary source
    CONSTRAINT uq_confirmed_source
        UNIQUE NULLS NOT DISTINCT (target_patient_id, is_confirmed)
);

COMMENT ON TABLE  Transmission_Chain IS
    'Directed graph edges: source→target. NULL source_patient_id = index/unknown case.
     Recursive CTEs traverse this table to find Patient Zero.';
COMMENT ON COLUMN Transmission_Chain.source_patient_id IS
    'Self-referencing FK to Patients. NULL denotes a root node (Patient Zero candidate).';

-- -----------------------------------------------------------------------------
-- 10. DAILY_STATISTICS
-- -----------------------------------------------------------------------------

CREATE TABLE Daily_Statistics (
    stat_id             SERIAL          PRIMARY KEY,
    city_id             INTEGER         NOT NULL REFERENCES Cities(city_id) ON DELETE CASCADE,
    stat_date           DATE            NOT NULL,
    new_cases           INTEGER         NOT NULL DEFAULT 0 CHECK (new_cases >= 0),
    new_deaths          INTEGER         NOT NULL DEFAULT 0 CHECK (new_deaths >= 0),
    new_recoveries      INTEGER         NOT NULL DEFAULT 0 CHECK (new_recoveries >= 0),
    active_cases        INTEGER         NOT NULL DEFAULT 0 CHECK (active_cases >= 0),
    total_cases         INTEGER         NOT NULL DEFAULT 0 CHECK (total_cases >= 0),
    total_deaths        INTEGER         NOT NULL DEFAULT 0 CHECK (total_deaths >= 0),
    total_recoveries    INTEGER         NOT NULL DEFAULT 0 CHECK (total_recoveries >= 0),
    tests_conducted     INTEGER         DEFAULT 0           CHECK (tests_conducted >= 0),
    positivity_rate     NUMERIC(5, 2)   CHECK (positivity_rate BETWEEN 0 AND 100),
    hospitalized        INTEGER         DEFAULT 0           CHECK (hospitalized >= 0),
    icu_occupied        INTEGER         DEFAULT 0           CHECK (icu_occupied >= 0),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_city_date UNIQUE (city_id, stat_date)
);

COMMENT ON TABLE Daily_Statistics IS
    'Aggregated daily snapshot per city. Incremented atomically by triggers, never by direct DML in application layer.';

-- -----------------------------------------------------------------------------
-- 11. INDEXES  (Performance-critical paths)
-- -----------------------------------------------------------------------------

-- Patient lookups
CREATE INDEX idx_patients_city        ON Patients(city_id);
CREATE INDEX idx_patients_status      ON Patients(current_status);
CREATE INDEX idx_patients_variant     ON Patients(variant_id);
CREATE INDEX idx_patients_diagnosis   ON Patients(diagnosis_date DESC);

-- Transmission graph traversal (the recursive CTE hot path)
CREATE INDEX idx_tc_source            ON Transmission_Chain(source_patient_id);
CREATE INDEX idx_tc_target            ON Transmission_Chain(target_patient_id);
CREATE INDEX idx_tc_date              ON Transmission_Chain(transmission_date DESC);

-- Daily statistics range scans
CREATE INDEX idx_ds_city_date         ON Daily_Statistics(city_id, stat_date DESC);
CREATE INDEX idx_ds_date              ON Daily_Statistics(stat_date DESC);

-- Hospital admissions
CREATE INDEX idx_ha_patient           ON Hospital_Admissions(patient_id);
CREATE INDEX idx_ha_hospital          ON Hospital_Admissions(hospital_id);
CREATE INDEX idx_ha_status            ON Hospital_Admissions(admission_status);
CREATE INDEX idx_ha_dates             ON Hospital_Admissions(admission_date, discharge_date);

-- Patient symptoms
CREATE INDEX idx_ps_patient           ON Patient_Symptoms(patient_id);
CREATE INDEX idx_ps_symptom           ON Patient_Symptoms(symptom_id);

-- Cities
CREATE INDEX idx_cities_country       ON Cities(country);

-- =============================================================================
-- END OF SCRIPT 1
-- =============================================================================
