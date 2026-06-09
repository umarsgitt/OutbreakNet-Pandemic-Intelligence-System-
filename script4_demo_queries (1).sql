-- =============================================================================
-- OutbreakNet Pandemic Surveillance System
-- Script 4: Demonstration Queries
-- Purpose : Showcase recursive tracing, hotspot analysis, triggers, and
--           advanced analytical capabilities for project evaluation.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 1: TRIGGER DEMONSTRATION
--   Update Patient #15 (Faisal Sheikh) to 'Deceased' via Hospital_Admissions.
--   After running, verify:
--     • Patients.current_status → 'Deceased'
--     • Daily_Statistics.new_deaths incremented for Karachi on 2024-01-23
--     • Hospitals.icu_bed_occupancy decremented for Aga Khan (hospital_id=3)
-- ─────────────────────────────────────────────────────────────────────────────

-- Step 1: Snapshot BEFORE
SELECT 'BEFORE' AS snapshot, current_status FROM Patients WHERE patient_id = 15;
SELECT 'BEFORE' AS snapshot, total_deaths, new_deaths FROM Daily_Statistics
WHERE  city_id = 2 AND stat_date = '2024-01-23';
SELECT 'BEFORE' AS snapshot, icu_bed_occupancy FROM Hospitals WHERE hospital_id = 3;

-- Step 2: Fire the trigger
UPDATE Hospital_Admissions
SET    admission_status = 'Deceased',
       discharge_date   = '2024-01-23'
WHERE  patient_id  = 15
  AND  hospital_id = 3;

-- Step 3: Snapshot AFTER  (all three rows should reflect the changes)
SELECT 'AFTER' AS snapshot, current_status FROM Patients WHERE patient_id = 15;
SELECT 'AFTER' AS snapshot, total_deaths, new_deaths FROM Daily_Statistics
WHERE  city_id = 2 AND stat_date = '2024-01-23';
SELECT 'AFTER' AS snapshot, icu_bed_occupancy FROM Hospitals WHERE hospital_id = 3;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 2: RECURSIVE PATIENT ZERO TRACE — via the wrapper function
--   Trace Patient #35 (Muneeb Durrani, Generation 4) back to Patient Zero.
--   Expected path depth: 4 hops  (P35 ← P24 ← P4 ← P1)
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    depth                                       AS hop,
    patient_id,
    full_name,
    city_name,
    diagnosis_date,
    source_full_name                            AS infected_by,
    transmission_date,
    transmission_mode,
    location_of_event,
    ROUND(confidence_score * 100, 1) || '%'     AS confidence,
    path_ids                                    AS full_path_array
FROM fn_get_transmission_chain(35)
ORDER BY depth DESC;   -- root (Patient Zero) appears first


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 3: RECURSIVE CTE — Full Outbreak Tree (Descendants of Patient Zero)
--   Propagates DOWNWARD from P1 to show every infected individual
--   and their generation number. Classic BFS traversal.
-- ─────────────────────────────────────────────────────────────────────────────

WITH RECURSIVE outbreak_tree AS (

    -- Anchor: Patient Zero (root nodes — no confirmed source)
    SELECT
        p.patient_id,
        (p.first_name || ' ' || p.last_name)       AS full_name,
        p.current_status,
        p.diagnosis_date,
        c.city_name,
        0                                           AS generation,
        ARRAY[p.patient_id]                         AS visited,
        p.patient_id::TEXT                          AS ancestry_path
    FROM   Patients            p
    JOIN   Cities              c  ON c.city_id = p.city_id
    LEFT   JOIN Transmission_Chain tc
           ON  tc.target_patient_id = p.patient_id
           AND tc.is_confirmed      = TRUE
    WHERE  tc.target_patient_id IS NULL  -- no incoming edge = root node

    UNION ALL

    -- Recursive: expand to all direct downstream cases
    SELECT
        target_p.patient_id,
        (target_p.first_name || ' ' || target_p.last_name),
        target_p.current_status,
        target_p.diagnosis_date,
        target_c.city_name,
        ot.generation + 1,
        ot.visited || target_p.patient_id,
        ot.ancestry_path || ' → ' || target_p.patient_id::TEXT
    FROM   outbreak_tree         ot
    JOIN   Transmission_Chain    tc
           ON  tc.source_patient_id = ot.patient_id
           AND tc.is_confirmed      = TRUE
    JOIN   Patients  target_p   ON target_p.patient_id = tc.target_patient_id
    JOIN   Cities    target_c   ON target_c.city_id    = target_p.city_id
    WHERE  NOT (target_p.patient_id = ANY(ot.visited))   -- cycle guard
)
SELECT
    generation,
    patient_id,
    full_name,
    current_status,
    diagnosis_date,
    city_name,
    ancestry_path
FROM  outbreak_tree
ORDER BY generation, patient_id;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 4: SUPERSPREADER IDENTIFICATION
--   Which patients directly infected the most people?
--   Annotates with variant and outcome.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    ts.patient_id,
    ts.patient_name,
    ts.city_name,
    ts.variant_name,
    ts.total_infected                               AS direct_infections,
    ts.transmission_modes_used,
    ROUND(ts.avg_confidence * 100, 1) || '%'        AS avg_confidence,
    ts.current_status,
    -- R-number contribution (patient's personal effective R)
    CASE
        WHEN ts.total_infected >= 4 THEN '🔴 Superspreader'
        WHEN ts.total_infected >= 2 THEN '🟡 High Spreader'
        WHEN ts.total_infected  = 1 THEN '🟢 Single Transfer'
        ELSE                             '⚪ Dead End'
    END                                             AS spreader_classification
FROM v_transmission_stats ts
WHERE ts.total_infected > 0
ORDER BY ts.total_infected DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 5: HOTSPOT ANALYSIS VIEW — Full Weekly Breakdown
--   Shows every city's weekly metrics including growth rate and alert level.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    city_name,
    province,
    iso_year_week,
    weekly_new_cases,
    prev_week_cases,
    weekly_growth_rate_pct          || '%'  AS weekly_growth_rate,
    weekly_cfr_pct                  || '%'  AS case_fatality_rate,
    incidence_per_100k,
    avg_positivity_pct              || '%'  AS avg_positivity,
    weekly_tests,
    alert_level
FROM  Hotspot_Analysis_View
ORDER BY week_start DESC, weekly_new_cases DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 6: CRITICAL HOTSPOT RANKING
--   Returns only cities in WARNING or CRITICAL state, sorted by growth rate.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    city_name,
    iso_year_week,
    weekly_new_cases,
    weekly_growth_rate_pct || '%'   AS growth_rate,
    incidence_per_100k,
    alert_level
FROM  Hotspot_Analysis_View
WHERE alert_level IN ('CRITICAL', 'WARNING')
ORDER BY weekly_growth_rate_pct DESC NULLS LAST;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 7: SYMPTOM BURDEN ANALYSIS
--   Ranks symptoms by frequency and average severity across all patients.
--   Useful for clinical triage protocol calibration.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    s.symptom_name,
    s.category,
    s.icd10_code,
    COUNT(ps.patient_symptom_id)                        AS total_reported_cases,
    ROUND(COUNT(ps.patient_symptom_id)::NUMERIC /
          (SELECT COUNT(*) FROM Patients) * 100, 1)     AS prevalence_pct,
    MODE()  WITHIN GROUP (ORDER BY ps.severity::TEXT)   AS most_common_severity,
    COUNT(*) FILTER (WHERE ps.severity = 'Critical')    AS critical_count,
    COUNT(*) FILTER (WHERE ps.severity = 'Severe')      AS severe_count,
    AVG(ps.resolution_date - ps.onset_date)             AS avg_duration_days
FROM   Symptoms        s
JOIN   Patient_Symptoms ps ON ps.symptom_id = s.symptom_id
GROUP  BY s.symptom_id, s.symptom_name, s.category, s.icd10_code
ORDER  BY total_reported_cases DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 8: VACCINATION EFFICACY SIGNAL
--   Compares ICU admission rates and mortality between vaccinated
--   and unvaccinated patients.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    p.is_vaccinated,
    p.vaccination_doses,
    COUNT(DISTINCT p.patient_id)                            AS total_patients,
    COUNT(DISTINCT ha.admission_id)                         AS total_admissions,
    COUNT(DISTINCT ha.admission_id) FILTER
        (WHERE ha.ward = 'ICU')                             AS icu_admissions,
    COUNT(DISTINCT p.patient_id) FILTER
        (WHERE p.current_status = 'Deceased')               AS deaths,
    ROUND(
        COUNT(DISTINCT p.patient_id) FILTER
            (WHERE p.current_status = 'Deceased')::NUMERIC
        / NULLIF(COUNT(DISTINCT p.patient_id), 0) * 100,
        2
    )                                                       AS mortality_rate_pct,
    ROUND(
        COUNT(DISTINCT ha.admission_id) FILTER
            (WHERE ha.ward = 'ICU')::NUMERIC
        / NULLIF(COUNT(DISTINCT ha.admission_id), 0) * 100,
        2
    )                                                       AS icu_admission_rate_pct
FROM   Patients            p
LEFT   JOIN Hospital_Admissions ha ON ha.patient_id = p.patient_id
GROUP  BY p.is_vaccinated, p.vaccination_doses
ORDER  BY p.is_vaccinated DESC, p.vaccination_doses;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 9: VARIANT SPREAD VELOCITY
--   How fast is each variant spreading? Compare average gap between
--   source diagnosis_date and target diagnosis_date.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    v.variant_name,
    v.who_label,
    v.estimated_r0_min || '–' || v.estimated_r0_max    AS r0_range,
    COUNT(tc.transmission_id)                           AS transmission_events,
    COUNT(DISTINCT tc.source_patient_id)                AS unique_source_patients,
    ROUND(AVG(
        tc.transmission_date - src_p.diagnosis_date
    ), 1)                                               AS avg_generation_time_days,
    ROUND(AVG(tc.confidence_score), 3)                  AS avg_confidence,
    STRING_AGG(DISTINCT tc.transmission_mode::TEXT, ', ')
                                                        AS modes_observed
FROM   Variants            v
JOIN   Patients            tgt_p  ON tgt_p.variant_id     = v.variant_id
JOIN   Transmission_Chain  tc     ON tc.target_patient_id  = tgt_p.patient_id
JOIN   Patients            src_p  ON src_p.patient_id      = tc.source_patient_id
WHERE  tc.is_confirmed = TRUE
GROUP  BY v.variant_id, v.variant_name, v.who_label, v.estimated_r0_min, v.estimated_r0_max
ORDER  BY transmission_events DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 10: COMORBIDITY RISK MATRIX
--   Identifies which comorbidities are most associated with severe outcomes
--   (ICU admission or death).
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    UNNEST(p.comorbidities)                             AS comorbidity,
    COUNT(DISTINCT p.patient_id)                        AS affected_patients,
    COUNT(DISTINCT p.patient_id) FILTER
        (WHERE p.current_status = 'Deceased')           AS deceased,
    COUNT(DISTINCT ha.admission_id) FILTER
        (WHERE ha.ward = 'ICU')                         AS icu_admissions,
    ROUND(
        COUNT(DISTINCT p.patient_id) FILTER
            (WHERE p.current_status = 'Deceased')::NUMERIC
        / NULLIF(COUNT(DISTINCT p.patient_id), 0) * 100,
        1
    )                                                   AS mortality_rate_pct
FROM   Patients p
LEFT   JOIN Hospital_Admissions ha ON ha.patient_id = p.patient_id
WHERE  p.comorbidities IS NOT NULL
GROUP  BY comorbidity
ORDER  BY mortality_rate_pct DESC NULLS LAST, icu_admissions DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 11: GEOGRAPHIC SPREAD TIMELINE
--   Shows the chronological order in which cities were hit and their
--   cumulative case trajectories — useful for mapping spread direction.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    c.city_name,
    MIN(ds.stat_date) FILTER (WHERE ds.new_cases > 0)  AS first_case_date,
    MAX(ds.total_cases)                                 AS peak_total_cases,
    MAX(ds.total_deaths)                                AS total_deaths,
    ROUND(
        MAX(ds.total_deaths)::NUMERIC /
        NULLIF(MAX(ds.total_cases), 0) * 100, 2
    )                                                   AS overall_cfr_pct,
    MAX(ds.positivity_rate)                             AS peak_positivity_pct,
    MAX(ds.icu_occupied)                                AS peak_icu_load
FROM   Daily_Statistics ds
JOIN   Cities           c ON c.city_id = ds.city_id
GROUP  BY c.city_id, c.city_name
ORDER  BY first_case_date NULLS LAST;


-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO 12: CONTACT NETWORK DEPTH SUMMARY
--   For each patient, shows their generation number within the outbreak tree
--   (computed via recursive CTE inline) and their downstream spread count.
-- ─────────────────────────────────────────────────────────────────────────────

WITH RECURSIVE gen_map AS (
    -- Roots
    SELECT
        p.patient_id,
        0 AS generation,
        ARRAY[p.patient_id] AS visited
    FROM   Patients p
    LEFT   JOIN Transmission_Chain tc
           ON  tc.target_patient_id = p.patient_id AND tc.is_confirmed = TRUE
    WHERE  tc.target_patient_id IS NULL

    UNION ALL

    SELECT
        tc.target_patient_id,
        gm.generation + 1,
        gm.visited || tc.target_patient_id
    FROM   gen_map gm
    JOIN   Transmission_Chain tc
           ON  tc.source_patient_id = gm.patient_id AND tc.is_confirmed = TRUE
    WHERE  NOT (tc.target_patient_id = ANY(gm.visited))
)
SELECT
    gm.generation,
    p.patient_id,
    p.first_name || ' ' || p.last_name          AS patient_name,
    c.city_name,
    p.current_status,
    v.variant_name,
    COUNT(tc_out.transmission_id)               AS direct_infections,
    ROUND(COUNT(tc_out.transmission_id)::NUMERIC /
        NULLIF((SELECT COUNT(*) FROM Patients), 0) * 100, 2)
                                                AS pct_of_total_outbreak
FROM   gen_map               gm
JOIN   Patients              p     ON p.patient_id     = gm.patient_id
JOIN   Cities                c     ON c.city_id        = p.city_id
LEFT   JOIN Variants         v     ON v.variant_id     = p.variant_id
LEFT   JOIN Transmission_Chain tc_out
       ON  tc_out.source_patient_id = gm.patient_id
       AND tc_out.is_confirmed      = TRUE
GROUP  BY gm.generation, p.patient_id, p.first_name, p.last_name,
          c.city_name, p.current_status, v.variant_name
ORDER  BY gm.generation, direct_infections DESC;

-- =============================================================================
-- END OF SCRIPT 4
-- =============================================================================
