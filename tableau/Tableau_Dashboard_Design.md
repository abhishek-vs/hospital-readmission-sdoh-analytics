# Hospital Readmission & SDOH Analytics — Tableau Dashboard Design

## Overview

This document defines the layout, calculated fields, and visual specifications for the Hospital Readmission Risk Tableau dashboard. Audience: care coordinators, hospital operations leadership, and population health managers.

---

## Data Sources

| Source | File | Grain |
|---|---|---|
| `Patients` | patients.csv | 1 row per patient |
| `Admissions` | admissions.csv | 1 row per admission |
| `SDOH` | sdoh_indicators.csv | 1 row per patient |

### Relationships
- `Admissions` LEFT JOIN `Patients` ON patient_id
- `Admissions` LEFT JOIN `SDOH` ON patient_id
- Filter all views to `is_readmission = No` by default

---

## Page 1: Executive Readmission Overview

### KPI Cards (top strip)
1. **30-Day Readmission Rate** — `COUNTIF(readmitted_30day="Yes") / COUNT(admission_id)` → format as %
2. **Avg Length of Stay** — `AVG(los_days)` → format as `X.X days`
3. **High-Risk Patients** — patients with SDOH risk score ≥ 7
4. **Benchmark Gap** — portfolio rate vs CMS benchmark (15.5%)

### Calculated Fields

```tableau
// 30-Day Readmission Rate
[Readmission Rate 30D] =
    COUNTD(IF [readmitted_30day] = "Yes" THEN [admission_id] END) /
    COUNTD([admission_id])

// SDOH Risk Tier
[SDOH Risk Tier] =
    IF [sdoh_risk_score] <= 2 THEN "Low"
    ELSEIF [sdoh_risk_score] <= 5 THEN "Moderate"
    ELSEIF [sdoh_risk_score] <= 8 THEN "High"
    ELSE "Very High"
    END

// Age Group
[Age Group] =
    IF [age] < 50 THEN "< 50"
    ELSEIF [age] < 65 THEN "50–64"
    ELSEIF [age] < 75 THEN "65–74"
    ELSEIF [age] < 85 THEN "75–84"
    ELSE "85+"
    END

// Priority Score
[Priority Score] = [charlson_comorbidity_index] * 0.4 + [sdoh_risk_score] * 0.6
```

### Visuals
- **Bar chart**: 30-day readmission rate by diagnosis (sorted descending, benchmark line at 15.5%)
- **Heatmap**: Diagnosis × Insurance type → readmission rate (colour: green=low, red=high)
- **Trend line**: Monthly readmission rate (last 12 months)
- **Donut**: Discharge disposition breakdown

### Filters (global)
- Date range (admission_date)
- Hospital (H01 / H02 / H03)
- Diagnosis category
- Insurance type

---

## Page 2: SDOH Risk Profile

### KPI Cards
1. % Patients with Housing Instability
2. % Patients with Food Insecurity
3. % Patients with Transportation Barrier
4. Avg Area Deprivation Index (ADI)

### Visuals
- **Stacked bar**: SDOH risk tier × readmission status (to show dose-response)
- **Box plot**: Social support score distribution by readmission outcome
- **Geographic map**: ADI by ZIP code, colour intensity = readmission rate (use zip_code field)
- **Scatter**: ADI (x) vs Readmission Rate (y), colour by diagnosis
- **Table**: SDOH factor prevalence by housing stability group

### Calculated Fields

```tableau
// % Housing Unstable or Homeless
[Housing Risk %] =
    COUNTD(IF [housing_stability] != "Stable" THEN [patient_id] END) /
    COUNTD([patient_id])

// Food Insecure
[Food Insecure %] =
    COUNTD(IF [food_security_status] != "Secure" THEN [patient_id] END) /
    COUNTD([patient_id])
```

---

## Page 3: Care Coordinator Worklist

### Purpose
Actionable daily list for care coordinators — who to call first after discharge.

### Visuals
- **Data table** (primary visual):
  Columns: Patient ID | Age | Diagnosis | Insurance | Discharge Date | Housing | Food | Transportation | SDOH Score | Charlson | Priority Score | Action

- **Colour coding**:
  - Red row: Priority score ≥ 7 ("URGENT")
  - Orange row: Priority score 5–6.9 ("HIGH")
  - Yellow row: Priority score 3–4.9 ("STANDARD")
  - Green row: Priority score < 3 ("ROUTINE")

- **Filters**:
  - Discharge date (default: last 7 days)
  - Priority level (multi-select)
  - Care coordinator assignment (if column exists)

### Action Buttons (Tableau Extensions)
- "Mark Contacted" — updates status in linked Google Sheet / Salesforce Health Cloud
- "Flag for Social Work Referral"
- "Schedule Follow-Up Call"

---

## Page 4: Predictive Risk Score Monitor

### Purpose
Display model scores for recently discharged patients; monitor model drift over time.

### KPI Cards
1. Model AUC (last 90 days)
2. High-risk patients correctly flagged (recall %)
3. False positive rate
4. Avg predicted probability for readmitted vs non-readmitted patients

### Visuals
- **ROC curve** (if model scores available as a field)
- **Histogram**: Predicted readmission probability distribution
- **Lift chart**: Model lift by decile of predicted probability
- **Time series**: Actual vs predicted readmission rate (weekly)

---

## Formatting & Branding

| Element | Value |
|---|---|
| Background | #F8FAFC |
| Primary colour | #1E3A5F (navy) |
| Accent colour | #0F766E (teal) |
| Alert colour | #DC2626 (red) |
| Font | Tableau Book |
| Header | Bold 14pt |
| Body | Regular 11pt |

---

## Performance Notes
- Data extract (`.hyper`): refresh nightly at 02:00
- Row-level security: care coordinators see only their assigned unit
- Publish to Tableau Server: `Hospital Analytics / Readmission Risk` project
