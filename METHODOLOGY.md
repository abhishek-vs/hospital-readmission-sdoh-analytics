# Methodology — Hospital Readmission & SDOH Analytics

This document records analytical decisions, alternatives considered, and known limitations. It is intended to demonstrate reasoning process alongside the outputs.

---

## 1. Data Decisions

### Why synthetic data?
Patient data is protected under HIPAA. This project uses simulated data calibrated against:
- Published 30-day readmission rates by diagnosis (CMS Hospital Compare 2023)
- SDOH prevalence estimates from the Robert Wood Johnson Foundation SDOH data
- Charlson Comorbidity Index score distributions from peer-reviewed studies

**Realism checks:**
- Heart Failure readmission rate ~45% (matches published HF-specific rates)
- ADI quartile readmission gradient mirrors published epidemiology
- LOS distributions follow published DRG-level benchmarks

### Cohort definition
We define the denominator as **index admissions only** (excluding readmissions from the denominator). This matches CMS HRRP methodology. Failure to exclude readmissions from the denominator would undercount the readmission rate.

---

## 2. SDOH Composite Index

### Weighting rationale
The composite index weights:
- Housing stability: 30% — strongest single SDOH predictor in the literature (Decker & Schmitz 2016)
- Area Deprivation Index: 25% — validated geographic measure, well-established in CMS risk models
- Social support: 15% — important but self-reported, more measurement error
- Food insecurity: 20% — strong predictor for chronic condition management
- Mental health diagnosis: 10% — binary flag; severity not captured

**Alternative considered:** PCA-derived composite (data-driven weights). Not used because:
- PCA weights are harder to explain to clinical stakeholders
- Sample size (80 patients) is too small for stable PCA loadings
- Theory-driven weights are preferable when n is small

### Encoding ordinal variables
Housing stability (Stable/At Risk/Unstable/Homeless) is encoded as 0/1/2/3. This assumes equal intervals — a simplification. In production, logistic regression coefficients for each category would be used (effect coding).

---

## 3. Predictive Model

### Algorithm choice: Gradient Boosting
We chose Gradient Boosting as the final model because:
- It handles mixed feature types (continuous + ordinal) without scaling
- It captures non-linear interactions (e.g., old age × high ADI is more than additive)
- SHAP values are available for explainability — required for clinical AI deployment

**Alternatives evaluated:**
| Model | AUC | Reason not chosen |
|---|---|---|
| Logistic Regression | 0.71 | Lower AUC; assumes linearity |
| Random Forest | 0.79 | Slightly lower AUC; less interpretable with SHAP waterfall |
| XGBoost | ~0.82 | Similar to GBT; GBT chosen for simpler dependency |
| Neural Network | Not evaluated | Sample size too small (n=80); would overfit |

### Class imbalance
Readmission rate ~32% — mild imbalance. We applied **SMOTE** oversampling on the training fold only (never on the test fold). Alternative: class weights (`class_weight='balanced'`). Both approaches give similar AUC; SMOTE chosen to explicitly generate minority class examples.

### Train/test split
80/20 stratified split (n=64/16). Very small test set — a known limitation. With real data, use k-fold cross-validation with a held-out final test set. Here, 5-fold CV is used to report AUC.

---

## 4. Survival Analysis

### Kaplan-Meier censoring assumption
Patients who did not readmit within 30 days are **censored at day 30**. This assumes censoring is non-informative — i.e., patients who didn't readmit were not more or less likely to readmit than uncensored patients. In reality, patients who died or transferred may be selectively censored.

### Cox PH assumption check
The proportional hazards assumption is checked via Schoenfeld residuals. All covariates pass (p > 0.1). If a covariate violated PH, we would use a time-varying coefficient model (`tt()` in R survival).

### Why not competing risks?
In a 30-day window, death before readmission is a competing event. We do not model this explicitly — a limitation for elderly high-comorbidity patients. A competing risks model (Fine-Gray) would be preferred for a 90-day or longer window.

---

## 5. Fairness Audit

### Metric choice: False Negative Rate
We focus on **FNR (missed high-risk patients)** rather than overall accuracy because:
- A false negative in this context means a high-risk patient is missed and not referred for intervention — a clinical harm
- FNR disparities by insurance type or race may reflect systemic undertreatment of disadvantaged groups
- FPR disparities (over-flagging low-risk patients) are a different concern — resource allocation inefficiency

**Acceptable disparity threshold:** FNR disparity >15% (max − min across groups) is flagged as requiring investigation. This is a conservative threshold; some fairness frameworks use stricter criteria (e.g., 80% rule: min group rate / max group rate < 0.8).

### Calibration
The calibration plot checks whether predicted probabilities match observed readmission rates. Good calibration is required for the priority scoring system to be meaningful — if the model says 60% probability, ~60% of those patients should readmit.

---

## 6. Policy Simulation

### Intervention efficacy assumption
We assume a **35% relative risk reduction** for intervened patients. This is based on:
- Care management programmes for heart failure (JAMA 2016): 20–40% RRR
- Transitional care model (TCM) trials: 30–35% RRR for high-risk patients
- We use 35% as a conservative upper bound

**Sensitivity analysis (not shown):** Results are robust across 20–45% efficacy range; optimal N shifts by ±5 patients.

### Cost assumptions
- Intervention cost: $450/patient (care coordinator outreach, 2 calls + follow-up)
- Hospitalisation cost: $15,000/readmission (US average, adjusted for Medicare mix)
- These are approximations; real figures would come from hospital cost accounting

---

## 7. Known Limitations

| Limitation | Impact | Mitigation |
|---|---|---|
| n=80 patients | Unstable model estimates | Document; use CV; note in exec summary |
| Self-reported SDOH | Measurement error | Flag; in production use validated screeners (AHC-HRSN) |
| Censoring assumption | Survival estimates biased if informative | Non-informative censoring documented |
| No competing risks | Mortality not modelled | Acceptable for 30-day window |
| No temporal validation | Model may not generalise over time | Recommend quarterly retraining |
| Equal-interval ordinal encoding | Slight bias in composite index | Use logistic coefficients in production |

---

## 8. What I Would Do Differently in Production

1. **Prospective validation** — track model performance on new discharges monthly
2. **EHR integration** — pull features from Epic/Cerner in real time at discharge
3. **Multi-site validation** — ensure model generalises across hospital campuses
4. **Competing risks model** — Fine-Gray for 90-day window
5. **Dynamic risk scoring** — update score based on post-discharge events (ED visit, lab results)
6. **Shareable risk cards** — generate a 1-page PDF per high-risk patient for care coordinators
7. **A/B test intervention** — randomise outreach timing (48h vs 7d) to measure true causal effect
