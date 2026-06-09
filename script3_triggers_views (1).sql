-- =============================================================================
-- OutbreakNet Pandemic Surveillance System
-- Script 3: Triggers, Functions & Views
-- =============================================================================

-- -----------------------------------------------------------------------------
-- SECTION A: HELPER FUNCTION — auto-update `updated_at` timestamps
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Attach to tables that have an updated_at column
CREATE TRIGGER trg_hospitals_updated_at
    BEFORE UPDATE ON Hospitals
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_patients_updated_at
    BEFORE UPDATE ON Patients
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_admissions_updated_at
    BEFORE UPDATE ON Hospital_Admissions
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_daily_stats_updated_at
    BEFORE UPDATE ON Daily_Statistics
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- =============================================================================
-- SECTION B: CORE TRIGGER — "The Pulse"
--   Fires AFTER a Hospital_Admissions row is UPDATED to admission_status = 'Deceased'
--   Actions:
--     1. Update Patients.current_status → 'Deceased'
--     2. Increment Daily_Statistics.new_deaths and total_deaths for the patient's city
--     3. Decrement Hospitals.icu_bed_occupancy IF the patient was in the ICU ward
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_handle_patient_death()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
DECLARE
    v_patient_city_id   INTEGER;
    v_stat_date         DATE;
    v_was_icu           BOOLEAN;
    v_rows_affected     INTEGER;
BEGIN
    -- -------------------------------------------------------------------------
    -- Guard: Only act when status transitions TO 'Deceased'
    -- -------------------------------------------------------------------------
    IF (NEW.admission_status = 'Deceased' AND OLD.admission_status <> 'Deceased') THEN

        -- Resolve the patient's home city and the effective statistics date
        SELECT city_id INTO v_patient_city_id
        FROM   Patients
        WHERE  patient_id = NEW.patient_id;

        -- Use discharge date if set, otherwise today
        v_stat_date := COALESCE(NEW.discharge_date, CURRENT_DATE);

        -- Was the patient in ICU?
        v_was_icu := (UPPER(COALESCE(NEW.ward, '')) = 'ICU');

        -- -----------------------------------------------------------------
        -- Step 1: Update patient status
        -- -----------------------------------------------------------------
        UPDATE Patients
        SET    current_status = 'Deceased',
               updated_at     = NOW()
        WHERE  patient_id = NEW.patient_id;

        -- -----------------------------------------------------------------
        -- Step 2: Upsert Daily_Statistics
        --   We use INSERT … ON CONFLICT to handle the case where a row for
        --   this city/date doesn't exist yet.
        -- -----------------------------------------------------------------
        INSERT INTO Daily_Statistics
            (city_id, stat_date, new_deaths, total_deaths,
             new_cases, new_recoveries, active_cases, total_cases, total_recoveries)
        VALUES
            (v_patient_city_id, v_stat_date, 1, 1,
             0, 0, 0, 0, 0)
        ON CONFLICT (city_id, stat_date) DO UPDATE
            SET new_deaths   = Daily_Statistics.new_deaths   + 1,
                total_deaths = Daily_Statistics.total_deaths + 1,
                updated_at   = NOW();

        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        IF v_rows_affected = 0 THEN
            RAISE WARNING 'fn_handle_patient_death: no Daily_Statistics row found/inserted for city_id=%, date=%',
                v_patient_city_id, v_stat_date;
        END IF;

        -- -----------------------------------------------------------------
        -- Step 3: Decrement ICU occupancy (only if patient was in ICU)
        -- -----------------------------------------------------------------
        IF v_was_icu THEN
            UPDATE Hospitals
            SET    icu_bed_occupancy = GREATEST(0, icu_bed_occupancy - 1),
                   updated_at        = NOW()
            WHERE  hospital_id = NEW.hospital_id;

            RAISE NOTICE 'ICU bed freed at hospital_id=% following death of patient_id=%',
                NEW.hospital_id, NEW.patient_id;
        END IF;

        RAISE NOTICE 'Death recorded: patient_id=%, hospital_id=%, city_id=%, date=%',
            NEW.patient_id, NEW.hospital_id, v_patient_city_id, v_stat_date;

    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_patient_death_cascade
    AFTER UPDATE OF admission_status
    ON Hospital_Admissions
    FOR EACH ROW
    EXECUTE FUNCTION fn_handle_patient_death();

COMMENT ON FUNCTION fn_handle_patient_death() IS
    'The "pulse" trigger. Atomically updates patient status, daily death stats,
     and ICU capacity when a patient is marked Deceased in Hospital_Admissions.';

-- =============================================================================
-- SECTION C: TRIGGER — New Admission → Increment ICU count
--   When a NEW admission is inserted with ward = 'ICU', increment occupancy.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_handle_new_icu_admission()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    IF UPPER(COALESCE(NEW.ward, '')) = 'ICU' THEN
        UPDATE Hospitals
        SET    icu_bed_occupancy = icu_bed_occupancy + 1,
               updated_at        = NOW()
        WHERE  hospital_id = NEW.hospital_id;

        -- Safety check: ensure we haven't exceeded capacity
        PERFORM 1
        FROM    Hospitals
        WHERE   hospital_id       = NEW.hospital_id
          AND   icu_bed_occupancy > icu_beds_total;

        IF FOUND THEN
            RAISE EXCEPTION
                'ICU capacity exceeded at hospital_id=%. Cannot admit patient_id=% to ICU.',
                NEW.hospital_id, NEW.patient_id;
        END IF;

        RAISE NOTICE 'ICU admission recorded: patient_id=% → hospital_id=%',
            NEW.patient_id, NEW.hospital_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_new_icu_admission
    AFTER INSERT
    ON Hospital_Admissions
    FOR EACH ROW
    EXECUTE FUNCTION fn_handle_new_icu_admission();

-- =============================================================================
-- SECTION D: TRIGGER — ICU Discharge → Free bed
--   When ward = 'ICU' and status changes to Discharged/Deceased (non-death path)
--   SECTION B handles Deceased; this handles Discharged from ICU.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_handle_icu_discharge()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    -- Fired when status moves from ICU → Discharged
    IF  OLD.admission_status = 'ICU'
    AND NEW.admission_status = 'Discharged'
    AND UPPER(COALESCE(OLD.ward, '')) = 'ICU'
    THEN
        UPDATE Hospitals
        SET    icu_bed_occupancy = GREATEST(0, icu_bed_occupancy - 1),
               updated_at        = NOW()
        WHERE  hospital_id = NEW.hospital_id;

        RAISE NOTICE 'ICU bed freed (discharge): patient_id=% from hospital_id=%',
            NEW.patient_id, NEW.hospital_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_icu_discharge
    AFTER UPDATE OF admission_status
    ON Hospital_Admissions
    FOR EACH ROW
    EXECUTE FUNCTION fn_handle_icu_discharge();

-- =============================================================================
-- SECTION E: TRIGGER — New Patient → Seed today's Daily_Statistics row
--   Ensures a stats row always exists when a patient is diagnosed.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_seed_daily_stats_on_new_patient()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    INSERT INTO Daily_Statistics
        (city_id, stat_date, new_cases, active_cases, total_cases,
         new_deaths, new_recoveries, total_deaths, total_recoveries)
    VALUES
        (NEW.city_id, NEW.diagnosis_date, 1, 1, 1, 0, 0, 0, 0)
    ON CONFLICT (city_id, stat_date) DO UPDATE
        SET new_cases    = Daily_Statistics.new_cases  + 1,
            active_cases = Daily_Statistics.active_cases + 1,
            total_cases  = Daily_Statistics.total_cases  + 1,
            updated_at   = NOW();

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_new_patient_stats
    AFTER INSERT
    ON Patients
    FOR EACH ROW
    EXECUTE FUNCTION fn_seed_daily_stats_on_new_patient();

-- =============================================================================
-- SECTION F: VIEW — Hotspot_Analysis_View
--   Calculates weekly growth rate for each city.
--   Growth Rate = ((cases_this_week - cases_last_week) / NULLIF(cases_last_week,0)) * 100
-- =============================================================================

CREATE OR REPLACE VIEW Hotspot_Analysis_View AS
WITH
-- Aggregate new cases per city per ISO week
weekly_cases AS (
    SELECT
        ds.city_id,
        c.city_name,
        c.province,
        c.population,
        DATE_TRUNC('week', ds.stat_date)::DATE          AS week_start,
        TO_CHAR(ds.stat_date, 'IYYY-IW')                AS iso_year_week,
        SUM(ds.new_cases)                               AS weekly_new_cases,
        SUM(ds.new_deaths)                              AS weekly_new_deaths,
        SUM(ds.new_recoveries)                          AS weekly_new_recoveries,
        MAX(ds.active_cases)                            AS peak_active_cases,
        SUM(ds.tests_conducted)                         AS weekly_tests,
        AVG(ds.positivity_rate)                         AS avg_positivity_rate,
        MAX(ds.icu_occupied)                            AS peak_icu_occupied
    FROM   Daily_Statistics ds
    JOIN   Cities c ON c.city_id = ds.city_id
    GROUP  BY ds.city_id, c.city_name, c.province, c.population,
              DATE_TRUNC('week', ds.stat_date), TO_CHAR(ds.stat_date, 'IYYY-IW')
),
-- Use LAG() to compare current week to prior week
weekly_with_lag AS (
    SELECT
        *,
        LAG(weekly_new_cases) OVER (
            PARTITION BY city_id
            ORDER BY     week_start
        )                                               AS prev_week_cases,
        LAG(weekly_new_deaths) OVER (
            PARTITION BY city_id
            ORDER BY     week_start
        )                                               AS prev_week_deaths
    FROM weekly_cases
)
SELECT
    city_id,
    city_name,
    province,
    population,
    iso_year_week,
    week_start,
    weekly_new_cases,
    weekly_new_deaths,
    weekly_new_recoveries,
    prev_week_cases,
    peak_active_cases,
    weekly_tests,
    ROUND(avg_positivity_rate, 2)                       AS avg_positivity_pct,
    peak_icu_occupied,

    -- Weekly Growth Rate (%)
    CASE
        WHEN prev_week_cases IS NULL OR prev_week_cases = 0
            THEN NULL  -- Cannot compute for first week or zero baseline
        ELSE
            ROUND(
                ((weekly_new_cases::NUMERIC - prev_week_cases) /
                  NULLIF(prev_week_cases, 0)) * 100.0,
                2
            )
    END                                                 AS weekly_growth_rate_pct,

    -- Case Fatality Rate for the week (%)
    ROUND(
        (weekly_new_deaths::NUMERIC / NULLIF(weekly_new_cases, 0)) * 100.0,
        2
    )                                                   AS weekly_cfr_pct,

    -- Cases per 100,000 population (incidence rate)
    ROUND(
        (weekly_new_cases::NUMERIC / NULLIF(population, 0)) * 100000,
        4
    )                                                   AS incidence_per_100k,

    -- Severity signal: is growth accelerating?
    CASE
        WHEN prev_week_cases IS NULL OR prev_week_cases = 0 THEN 'BASELINE'
        WHEN ((weekly_new_cases::NUMERIC - prev_week_cases) / NULLIF(prev_week_cases,0)) * 100 >= 50 THEN 'CRITICAL'
        WHEN ((weekly_new_cases::NUMERIC - prev_week_cases) / NULLIF(prev_week_cases,0)) * 100 >= 20 THEN 'WARNING'
        WHEN ((weekly_new_cases::NUMERIC - prev_week_cases) / NULLIF(prev_week_cases,0)) * 100 >= 0  THEN 'STABLE'
        ELSE 'DECLINING'
    END                                                 AS alert_level

FROM weekly_with_lag
ORDER BY city_id, week_start;

COMMENT ON VIEW Hotspot_Analysis_View IS
    'Dynamic weekly epidemiological summary per city.
     Computes growth rate, CFR, incidence, and alert level.
     Refreshes automatically — no materialisation needed at current data volume.';

-- =============================================================================
-- SECTION G: FUNCTION — fn_get_transmission_chain(p_target_patient_id INTEGER)
--   Returns the full ancestral path from any patient back to Patient Zero.
--   Exposed as a function so it can be called programmatically.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_transmission_chain(p_target_patient_id INTEGER)
RETURNS TABLE (
    depth               INTEGER,
    patient_id          INTEGER,
    full_name           TEXT,
    city_name           VARCHAR(100),
    diagnosis_date      DATE,
    source_patient_id   INTEGER,
    source_full_name    TEXT,
    transmission_date   DATE,
    transmission_mode   transmission_mode_enum,
    location_of_event   VARCHAR(200),
    confidence_score    NUMERIC(4,3),
    path_ids            INTEGER[]
)
LANGUAGE plpgsql STABLE AS
$$
BEGIN
    RETURN QUERY
    WITH RECURSIVE infection_tree AS (
        -- ---------------------------------------------------------------
        -- Anchor: Start at the requested patient
        -- ---------------------------------------------------------------
        SELECT
            0                           AS depth,
            p.patient_id,
            (p.first_name || ' ' || p.last_name)::TEXT AS full_name,
            c.city_name,
            p.diagnosis_date,
            tc.source_patient_id,
            NULL::TEXT                  AS source_full_name,
            tc.transmission_date,
            tc.transmission_mode,
            tc.location_of_event,
            tc.confidence_score,
            ARRAY[p.patient_id]         AS path_ids
        FROM   Patients p
        JOIN   Cities   c  ON c.city_id = p.city_id
        LEFT   JOIN Transmission_Chain tc
               ON  tc.target_patient_id = p.patient_id
               AND tc.is_confirmed      = TRUE
        WHERE  p.patient_id = p_target_patient_id

        UNION ALL

        -- ---------------------------------------------------------------
        -- Recursive step: Walk UP the chain toward the source
        -- ---------------------------------------------------------------
        SELECT
            it.depth + 1,
            src_p.patient_id,
            (src_p.first_name || ' ' || src_p.last_name)::TEXT,
            src_c.city_name,
            src_p.diagnosis_date,
            tc.source_patient_id,
            (prev_p.first_name || ' ' || prev_p.last_name)::TEXT,
            tc.transmission_date,
            tc.transmission_mode,
            tc.location_of_event,
            tc.confidence_score,
            it.path_ids || src_p.patient_id
        FROM   infection_tree          it
        JOIN   Transmission_Chain      tc
               ON  tc.target_patient_id = it.patient_id
               AND tc.is_confirmed      = TRUE
               AND tc.source_patient_id IS NOT NULL       -- stop at root
        JOIN   Patients   src_p   ON src_p.patient_id = tc.source_patient_id
        JOIN   Cities     src_c   ON src_c.city_id    = src_p.city_id
        JOIN   Patients   prev_p  ON prev_p.patient_id = it.patient_id
        -- Cycle guard: never revisit a patient already in the path
        WHERE  NOT (src_p.patient_id = ANY(it.path_ids))
    )
    SELECT
        it.depth,
        it.patient_id,
        it.full_name,
        it.city_name,
        it.diagnosis_date,
        it.source_patient_id,
        it.source_full_name,
        it.transmission_date,
        it.transmission_mode,
        it.location_of_event,
        it.confidence_score,
        it.path_ids
    FROM   infection_tree it
    ORDER  BY it.depth DESC;   -- Patient Zero first, target last
END;
$$;

COMMENT ON FUNCTION fn_get_transmission_chain(INTEGER) IS
    'Recursive CTE walk: traces any patient upward through the Transmission_Chain
     to Patient Zero. Returns one row per hop, ordered root-to-leaf.';

-- =============================================================================
-- SECTION H: VIEW — v_transmission_stats
--   Quick summary: who infected how many people (superspreader detection)
-- =============================================================================

CREATE OR REPLACE VIEW v_transmission_stats AS
SELECT
    p.patient_id,
    p.first_name || ' ' || p.last_name      AS patient_name,
    c.city_name,
    p.diagnosis_date,
    p.current_status,
    v.variant_name,
    COUNT(tc.transmission_id)               AS total_infected,
    ROUND(AVG(tc.confidence_score), 3)      AS avg_confidence,
    STRING_AGG(DISTINCT tc.transmission_mode::TEXT, ', ')
                                            AS transmission_modes_used
FROM   Patients p
JOIN   Cities   c  ON c.city_id    = p.city_id
LEFT   JOIN Variants v ON v.variant_id = p.variant_id
LEFT   JOIN Transmission_Chain tc
       ON  tc.source_patient_id = p.patient_id
       AND tc.is_confirmed      = TRUE
GROUP  BY p.patient_id, p.first_name, p.last_name,
          c.city_name, p.diagnosis_date, p.current_status, v.variant_name
ORDER  BY total_infected DESC, p.diagnosis_date;

COMMENT ON VIEW v_transmission_stats IS
    'Per-patient transmission count — use to identify superspreaders.';

-- =============================================================================
-- SECTION I: VIEW — v_hospital_capacity_dashboard
-- =============================================================================

CREATE OR REPLACE VIEW v_hospital_capacity_dashboard AS
SELECT
    h.hospital_id,
    h.hospital_name,
    c.city_name,
    h.total_beds,
    h.icu_beds_total,
    h.icu_bed_occupancy,
    h.icu_beds_total - h.icu_bed_occupancy  AS icu_beds_available,
    ROUND(
        (h.icu_bed_occupancy::NUMERIC / NULLIF(h.icu_beds_total, 0)) * 100,
        1
    )                                       AS icu_utilisation_pct,
    h.ventilators,
    COUNT(ha.admission_id) FILTER
        (WHERE ha.admission_status IN ('Admitted','ICU'))
                                            AS current_inpatients,
    COUNT(ha.admission_id) FILTER
        (WHERE ha.admission_status = 'ICU') AS current_icu_patients,
    CASE
        WHEN (h.icu_bed_occupancy::NUMERIC / NULLIF(h.icu_beds_total,0)) >= 0.90
            THEN 'CRITICAL'
        WHEN (h.icu_bed_occupancy::NUMERIC / NULLIF(h.icu_beds_total,0)) >= 0.70
            THEN 'HIGH'
        WHEN (h.icu_bed_occupancy::NUMERIC / NULLIF(h.icu_beds_total,0)) >= 0.50
            THEN 'MODERATE'
        ELSE 'NORMAL'
    END                                     AS capacity_alert
FROM   Hospitals          h
JOIN   Cities             c  ON c.city_id    = h.hospital_id
LEFT   JOIN Hospital_Admissions ha ON ha.hospital_id = h.hospital_id
GROUP  BY h.hospital_id, h.hospital_name, c.city_name,
          h.total_beds, h.icu_beds_total, h.icu_bed_occupancy, h.ventilators;

-- =============================================================================
-- END OF SCRIPT 3
-- =============================================================================
