-- ============================================================
-- Hospital Readmission & SDOH Analytics
-- SQL Query Library (PostgreSQL)
-- ============================================================

-- ============================================================
-- 1. COHORT DEFINITION & READMISSION FLAGS
-- ============================================================

-- 1.1 Index admissions only (exclude readmissions from denominator)
WITH index_admissions AS (
    SELECT *
    FROM admissions
    WHERE is_readmission = 'No'
),
-- 1.2 Flag 30-day readmissions
readmission_flags AS (
    SELECT
        a1.admission_id AS index_admission_id,
        a1.patient_id,
        a1.admission_date AS index_admission_date,
        a1.discharge_date AS index_discharge_date,
        a1.los_days,
        a1.primary_drg_code,
        a1.department,
        a1.discharge_disposition,
        CASE WHEN a1.readmitted_30day = 'Yes' THEN 1 ELSE 0 END AS readmitted_30day_flag,
        CASE WHEN a1.readmitted_90day = 'Yes' THEN 1 ELSE 0 END AS readmitted_90day_flag
    FROM index_admissions a1
)
SELECT * FROM readmission_flags;


-- 1.3 Overall 30-day readmission rate
SELECT
    COUNT(*) AS total_index_admissions,
    SUM(CASE WHEN readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmitted_30day_count,
    ROUND(
        100.0 * SUM(CASE WHEN readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS readmission_rate_30day_pct,
    SUM(CASE WHEN readmitted_90day = 'Yes' THEN 1 ELSE 0 END) AS readmitted_90day_count,
    ROUND(
        100.0 * SUM(CASE WHEN readmitted_90day = 'Yes' THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS readmission_rate_90day_pct
FROM admissions
WHERE is_readmission = 'No';


-- ============================================================
-- 2. READMISSION RATES BY PATIENT CHARACTERISTICS
-- ============================================================

-- 2.1 Readmission rate by primary diagnosis
SELECT
    p.primary_diagnosis_category,
    COUNT(DISTINCT a.patient_id) AS patient_count,
    COUNT(a.admission_id) AS total_admissions,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions_30d,
    ROUND(
        100.0 * SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(a.admission_id),
        2
    ) AS readmission_rate_pct,
    ROUND(AVG(a.los_days)::NUMERIC, 1) AS avg_los_days
FROM admissions a
JOIN patients p ON a.patient_id = p.patient_id
WHERE a.is_readmission = 'No'
GROUP BY p.primary_diagnosis_category
ORDER BY readmission_rate_pct DESC;


-- 2.2 Readmission rate by age group
SELECT
    CASE
        WHEN p.age < 50 THEN '< 50'
        WHEN p.age BETWEEN 50 AND 64 THEN '50–64'
        WHEN p.age BETWEEN 65 AND 74 THEN '65–74'
        WHEN p.age BETWEEN 75 AND 84 THEN '75–84'
        ELSE '85+'
    END AS age_group,
    COUNT(DISTINCT a.patient_id) AS patients,
    COUNT(a.admission_id) AS admissions,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions,
    ROUND(
        100.0 * SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(a.admission_id),
        2
    ) AS readmission_rate_pct,
    ROUND(AVG(p.charlson_comorbidity_index)::NUMERIC, 2) AS avg_charlson_index
FROM admissions a
JOIN patients p ON a.patient_id = p.patient_id
WHERE a.is_readmission = 'No'
GROUP BY age_group
ORDER BY age_group;


-- 2.3 Readmission rate by insurance type
SELECT
    p.insurance_type,
    COUNT(DISTINCT a.patient_id) AS patients,
    COUNT(a.admission_id) AS admissions,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions_30d,
    ROUND(
        100.0 * SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(a.admission_id),
        2
    ) AS readmission_rate_pct,
    ROUND(AVG(a.los_days)::NUMERIC, 1) AS avg_los_days
FROM admissions a
JOIN patients p ON a.patient_id = p.patient_id
WHERE a.is_readmission = 'No'
GROUP BY p.insurance_type
ORDER BY readmission_rate_pct DESC;


-- ============================================================
-- 3. SDOH IMPACT ON READMISSION
-- ============================================================

-- 3.1 Readmission rate by housing stability
SELECT
    s.housing_stability,
    COUNT(DISTINCT a.patient_id) AS patients,
    COUNT(a.admission_id) AS admissions,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions_30d,
    ROUND(
        100.0 * SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(a.admission_id),
        2
    ) AS readmission_rate_pct,
    ROUND(AVG(s.area_deprivation_index)::NUMERIC, 1) AS avg_adi,
    ROUND(AVG(s.social_support_score)::NUMERIC, 2) AS avg_social_support
FROM admissions a
JOIN patients p ON a.patient_id = p.patient_id
JOIN sdoh_indicators s ON a.patient_id = s.patient_id
WHERE a.is_readmission = 'No'
GROUP BY s.housing_stability
ORDER BY readmission_rate_pct DESC;


-- 3.2 Readmission rate by food security status
SELECT
    s.food_security_status,
    COUNT(DISTINCT a.patient_id) AS patients,
    COUNT(a.admission_id) AS admissions,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions_30d,
    ROUND(
        100.0 * SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(a.admission_id),
        2
    ) AS readmission_rate_pct
FROM admissions a
JOIN sdoh_indicators s ON a.patient_id = s.patient_id
WHERE a.is_readmission = 'No'
GROUP BY s.food_security_status
ORDER BY readmission_rate_pct DESC;


-- 3.3 Composite SDOH risk score vs readmission
SELECT
    CASE
        WHEN s.sdoh_risk_score <= 2 THEN 'Low (1–2)'
        WHEN s.sdoh_risk_score BETWEEN 3 AND 5 THEN 'Moderate (3–5)'
        WHEN s.sdoh_risk_score BETWEEN 6 AND 8 THEN 'High (6–8)'
        ELSE 'Very High (9–10)'
    END AS sdoh_risk_tier,
    COUNT(DISTINCT a.patient_id) AS patients,
    COUNT(a.admission_id) AS admissions,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions_30d,
    ROUND(
        100.0 * SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(a.admission_id),
        2
    ) AS readmission_rate_pct,
    ROUND(AVG(a.los_days)::NUMERIC, 1) AS avg_los_days
FROM admissions a
JOIN sdoh_indicators s ON a.patient_id = s.patient_id
WHERE a.is_readmission = 'No'
GROUP BY sdoh_risk_tier
ORDER BY readmission_rate_pct DESC;


-- 3.4 Area Deprivation Index (ADI) quartile analysis
WITH adi_quartiles AS (
    SELECT
        patient_id,
        area_deprivation_index,
        NTILE(4) OVER (ORDER BY area_deprivation_index) AS adi_quartile
    FROM sdoh_indicators
)
SELECT
    aq.adi_quartile,
    CONCAT('Q', aq.adi_quartile,
        CASE aq.adi_quartile
            WHEN 1 THEN ' (Least Deprived)'
            WHEN 4 THEN ' (Most Deprived)'
            ELSE ''
        END
    ) AS quartile_label,
    COUNT(DISTINCT a.patient_id) AS patients,
    ROUND(AVG(aq.area_deprivation_index)::NUMERIC, 1) AS avg_adi,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions_30d,
    ROUND(
        100.0 * SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(a.admission_id),
        2
    ) AS readmission_rate_pct
FROM admissions a
JOIN adi_quartiles aq ON a.patient_id = aq.patient_id
WHERE a.is_readmission = 'No'
GROUP BY aq.adi_quartile
ORDER BY aq.adi_quartile;


-- ============================================================
-- 4. LENGTH OF STAY ANALYSIS
-- ============================================================

-- 4.1 LOS by diagnosis and SDOH risk tier
SELECT
    p.primary_diagnosis_category,
    CASE
        WHEN s.sdoh_risk_score <= 5 THEN 'Low-Moderate SDOH Risk'
        ELSE 'High-Very High SDOH Risk'
    END AS sdoh_group,
    COUNT(a.admission_id) AS admissions,
    ROUND(AVG(a.los_days)::NUMERIC, 2) AS avg_los,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.los_days) AS median_los,
    MAX(a.los_days) AS max_los,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions
FROM admissions a
JOIN patients p ON a.patient_id = p.patient_id
JOIN sdoh_indicators s ON a.patient_id = s.patient_id
WHERE a.is_readmission = 'No'
GROUP BY p.primary_diagnosis_category, sdoh_group
ORDER BY p.primary_diagnosis_category, sdoh_group;


-- 4.2 Discharge disposition and readmission
SELECT
    a.discharge_disposition,
    COUNT(a.admission_id) AS admissions,
    ROUND(AVG(a.los_days)::NUMERIC, 2) AS avg_los,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions_30d,
    ROUND(
        100.0 * SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(a.admission_id),
        2
    ) AS readmission_rate_pct
FROM admissions a
WHERE a.is_readmission = 'No'
GROUP BY a.discharge_disposition
ORDER BY readmission_rate_pct DESC;


-- ============================================================
-- 5. HIGH-RISK PATIENT IDENTIFICATION
-- ============================================================

-- 5.1 High-risk patients: Charlson >= 5, SDOH risk >= 7, readmission history
SELECT
    p.patient_id,
    p.age,
    p.gender,
    p.insurance_type,
    p.primary_diagnosis_category,
    p.charlson_comorbidity_index,
    s.housing_stability,
    s.food_security_status,
    s.social_support_score,
    s.sdoh_risk_score,
    s.area_deprivation_index,
    a.discharge_date AS last_discharge_date,
    a.discharge_disposition,
    a.readmitted_30day
FROM patients p
JOIN sdoh_indicators s ON p.patient_id = s.patient_id
JOIN admissions a ON p.patient_id = a.patient_id
WHERE a.is_readmission = 'No'
  AND p.charlson_comorbidity_index >= 5
  AND s.sdoh_risk_score >= 7
ORDER BY s.sdoh_risk_score DESC, p.charlson_comorbidity_index DESC;


-- 5.2 Care coordinator priority list (for outreach within 48h of discharge)
SELECT
    p.patient_id,
    p.age,
    p.primary_diagnosis_category,
    p.insurance_type,
    p.charlson_comorbidity_index,
    s.housing_stability,
    s.food_security_status,
    s.transportation_barrier,
    s.social_support_score,
    s.mental_health_diagnosis,
    s.sdoh_risk_score,
    a.discharge_date,
    a.discharge_disposition,
    -- Priority score: composite of clinical + SDOH risk
    (p.charlson_comorbidity_index * 0.4 + s.sdoh_risk_score * 0.6) AS priority_score,
    CASE
        WHEN (p.charlson_comorbidity_index * 0.4 + s.sdoh_risk_score * 0.6) >= 7 THEN 'URGENT — Contact same day'
        WHEN (p.charlson_comorbidity_index * 0.4 + s.sdoh_risk_score * 0.6) >= 5 THEN 'HIGH — Contact within 48h'
        ELSE 'STANDARD — Contact within 7 days'
    END AS outreach_priority
FROM patients p
JOIN sdoh_indicators s ON p.patient_id = s.patient_id
JOIN admissions a ON p.patient_id = a.patient_id
WHERE a.is_readmission = 'No'
  AND a.discharge_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY priority_score DESC;


-- ============================================================
-- 6. ADVANCED ANALYTICS — WINDOW FUNCTIONS
-- ============================================================

-- 6.1 Patient admission timeline: sequence each admission and calculate days since previous
-- Uses ROW_NUMBER + LAG to build a longitudinal care history
WITH admission_timeline AS (
    SELECT
        a.patient_id,
        a.admission_id,
        a.admission_date,
        a.discharge_date,
        a.los_days,
        a.department,
        a.readmitted_30day,
        ROW_NUMBER() OVER (PARTITION BY a.patient_id ORDER BY a.admission_date) AS admission_seq,
        LAG(a.discharge_date) OVER (PARTITION BY a.patient_id ORDER BY a.admission_date) AS prev_discharge_date,
        LAG(a.department)     OVER (PARTITION BY a.patient_id ORDER BY a.admission_date) AS prev_department
    FROM admissions a
)
SELECT
    at.patient_id,
    at.admission_seq,
    at.admission_date,
    at.discharge_date,
    at.los_days,
    at.department,
    at.prev_department,
    at.prev_discharge_date,
    (at.admission_date - at.prev_discharge_date) AS days_since_last_discharge,
    CASE
        WHEN (at.admission_date - at.prev_discharge_date) <= 30  THEN '30-day readmission'
        WHEN (at.admission_date - at.prev_discharge_date) <= 90  THEN '31–90 day readmission'
        WHEN (at.admission_date - at.prev_discharge_date) IS NULL THEN 'First admission'
        ELSE 'Non-readmission return'
    END AS return_type,
    at.readmitted_30day
FROM admission_timeline at
ORDER BY at.patient_id, at.admission_seq;


-- 6.2 LOS trend by month — rolling 3-month average to detect seasonal patterns
-- Uses window aggregate with frame to smooth monthly variation
WITH monthly_los AS (
    SELECT
        DATE_TRUNC('month', admission_date)    AS admission_month,
        department,
        COUNT(admission_id)                    AS admissions,
        ROUND(AVG(los_days)::NUMERIC, 2)       AS avg_los,
        SUM(CASE WHEN readmitted_30day = 'Yes' THEN 1 ELSE 0 END) AS readmissions
    FROM admissions
    WHERE is_readmission = 'No'
    GROUP BY DATE_TRUNC('month', admission_date), department
)
SELECT
    admission_month,
    department,
    admissions,
    avg_los,
    readmissions,
    ROUND(
        AVG(avg_los) OVER (
            PARTITION BY department
            ORDER BY admission_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )::NUMERIC, 2
    ) AS rolling_3m_avg_los,
    ROUND(
        SUM(readmissions) OVER (
            PARTITION BY department
            ORDER BY admission_month
            ROWS UNBOUNDED PRECEDING
        )::NUMERIC, 0
    ) AS cumulative_readmissions,
    LAG(avg_los, 1) OVER (PARTITION BY department ORDER BY admission_month) AS prev_month_los,
    ROUND(
        (avg_los - LAG(avg_los, 1) OVER (PARTITION BY department ORDER BY admission_month))
        ::NUMERIC, 2
    ) AS los_mom_delta
FROM monthly_los
ORDER BY department, admission_month;


-- 6.3 High-risk patient ranking within diagnosis category
-- RANK and NTILE used to triage patients for care management programmes
WITH patient_risk AS (
    SELECT
        p.patient_id,
        p.age,
        p.primary_diagnosis_category,
        p.insurance_type,
        p.charlson_comorbidity_index,
        s.sdoh_risk_score,
        s.area_deprivation_index,
        -- Composite priority score
        ROUND((p.charlson_comorbidity_index * 0.4 + s.sdoh_risk_score * 0.6)::NUMERIC, 2) AS composite_risk,
        a.readmitted_30day
    FROM patients p
    JOIN sdoh_indicators s ON p.patient_id = s.patient_id
    JOIN admissions a      ON p.patient_id = a.patient_id
    WHERE a.is_readmission = 'No'
)
SELECT
    patient_id,
    age,
    primary_diagnosis_category,
    insurance_type,
    charlson_comorbidity_index,
    sdoh_risk_score,
    area_deprivation_index,
    composite_risk,
    readmitted_30day,
    RANK()       OVER (ORDER BY composite_risk DESC)                                    AS overall_risk_rank,
    RANK()       OVER (PARTITION BY primary_diagnosis_category ORDER BY composite_risk DESC) AS dx_risk_rank,
    NTILE(5)     OVER (ORDER BY composite_risk DESC)                                    AS risk_quintile,
    ROUND(
        AVG(composite_risk) OVER (PARTITION BY primary_diagnosis_category)::NUMERIC, 2
    )                                                                                   AS dx_avg_composite_risk,
    ROUND(
        (composite_risk - AVG(composite_risk) OVER (PARTITION BY primary_diagnosis_category))
        ::NUMERIC, 2
    )                                                                                   AS vs_dx_avg
FROM patient_risk
ORDER BY composite_risk DESC;


-- 6.4 Readmission recurrence analysis — patients with multiple readmissions
-- LEAD to look ahead at the next admission after each readmission event
WITH readmit_events AS (
    SELECT
        a.patient_id,
        a.admission_id,
        a.admission_date,
        a.discharge_date,
        a.readmitted_30day,
        ROW_NUMBER() OVER (PARTITION BY a.patient_id ORDER BY a.admission_date) AS seq,
        COUNT(*)     OVER (PARTITION BY a.patient_id)                           AS total_admissions
    FROM admissions a
)
SELECT
    re.patient_id,
    re.seq,
    re.admission_date,
    re.discharge_date,
    re.readmitted_30day,
    re.total_admissions,
    LEAD(re.admission_date) OVER (PARTITION BY re.patient_id ORDER BY re.seq) AS next_admission_date,
    LEAD(re.readmitted_30day) OVER (PARTITION BY re.patient_id ORDER BY re.seq) AS next_readmit_flag,
    (LEAD(re.admission_date) OVER (PARTITION BY re.patient_id ORDER BY re.seq)
     - re.discharge_date)                                                       AS days_to_next_admission
FROM readmit_events re
WHERE re.total_admissions > 1        -- only patients with ≥2 admissions
ORDER BY re.patient_id, re.seq;


-- 6.5 Fairness check: readmission rates and false-negative risk by race and insurance type
-- Helps identify disparities the predictive model may need to address
SELECT
    p.race_ethnicity,
    p.insurance_type,
    COUNT(a.admission_id)                                                       AS admissions,
    SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END)                AS actual_readmissions,
    ROUND(
        100.0 * SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END) / COUNT(a.admission_id)
        ::NUMERIC, 2
    )                                                                           AS readmission_rate_pct,
    ROUND(AVG(p.charlson_comorbidity_index)::NUMERIC, 2)                        AS avg_charlson,
    ROUND(AVG(s.sdoh_risk_score)::NUMERIC, 2)                                   AS avg_sdoh_risk,
    RANK() OVER (ORDER BY
        SUM(CASE WHEN a.readmitted_30day = 'Yes' THEN 1 ELSE 0 END)::NUMERIC
        / COUNT(a.admission_id) DESC
    )                                                                            AS readmission_rate_rank
FROM admissions a
JOIN patients p      ON a.patient_id = p.patient_id
JOIN sdoh_indicators s ON a.patient_id = s.patient_id
WHERE a.is_readmission = 'No'
GROUP BY p.race_ethnicity, p.insurance_type
HAVING COUNT(a.admission_id) >= 3    -- exclude very small cells
ORDER BY readmission_rate_pct DESC;
