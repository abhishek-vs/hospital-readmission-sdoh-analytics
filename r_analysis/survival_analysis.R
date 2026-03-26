# ============================================================
# Hospital Readmission & SDOH Analytics
# R Script: Survival Analysis — Time to Readmission
# ============================================================

# install.packages(c("survival", "survminer", "tidyverse", "ggplot2", "broom"))

library(survival)
library(survminer)
library(tidyverse)
library(ggplot2)
library(broom)

cat("=== Survival Analysis: Time to Readmission ===\n\n")

# ============================================================
# 1. PREPARE SURVIVAL DATA
# ============================================================
patients   <- read_csv("../data/patients.csv")
admissions <- read_csv("../data/admissions.csv")
sdoh       <- read_csv("../data/sdoh_indicators.csv")

# Merge index + readmission admissions to compute time-to-event
index_adm <- admissions %>%
  filter(is_readmission == "No") %>%
  mutate(discharge_date = as.Date(discharge_date))

readmissions <- admissions %>%
  filter(is_readmission == "Yes") %>%
  mutate(readmission_date = as.Date(admission_date)) %>%
  select(patient_id, readmission_date)

# Build survival data: time = days from discharge to readmission (or censoring)
# Censoring time = 30 days if not readmitted
survival_df <- index_adm %>%
  left_join(readmissions, by = "patient_id") %>%
  left_join(patients, by = "patient_id") %>%
  left_join(sdoh, by = "patient_id") %>%
  mutate(
    event = if_else(readmitted_30day == "Yes", 1L, 0L),
    time_to_event = if_else(
      event == 1L & !is.na(readmission_date),
      as.numeric(readmission_date - discharge_date),
      30  # censored at 30 days if no readmission
    ),
    time_to_event = pmax(time_to_event, 1),  # floor at 1 day
    # Groupings
    sdoh_risk_group = case_when(
      sdoh_risk_score <= 5 ~ "Low-Moderate SDOH",
      TRUE ~ "High-Very High SDOH"
    ) %>% factor(levels = c("Low-Moderate SDOH", "High-Very High SDOH")),
    housing_group = factor(
      if_else(housing_stability == "Stable", "Stable Housing", "Unstable/Homeless"),
      levels = c("Stable Housing", "Unstable/Homeless")
    ),
    age_group = case_when(
      age < 65 ~ "Under 65",
      age < 75 ~ "65–74",
      TRUE ~ "75+"
    ) %>% factor(levels = c("Under 65", "65–74", "75+"))
  )

cat(sprintf("Survival dataset: %d patients\n", nrow(survival_df)))
cat(sprintf("Events (readmissions): %d (%.1f%%)\n\n",
    sum(survival_df$event), 100 * mean(survival_df$event)))


# ============================================================
# 2. KAPLAN-MEIER CURVES
# ============================================================

# 2a. KM by SDOH risk group
km_sdoh <- survfit(Surv(time_to_event, event) ~ sdoh_risk_group, data = survival_df)
cat("--- KM Survival by SDOH Risk Group ---\n")
print(summary(km_sdoh, times = c(7, 14, 21, 30)))

p_km_sdoh <- ggsurvplot(
  km_sdoh,
  data = survival_df,
  fun = "event",  # cumulative event (readmission) probability
  palette = c("#059669", "#DC2626"),
  linetype = c("solid", "solid"),
  conf.int = TRUE,
  conf.int.alpha = 0.15,
  pval = TRUE,
  pval.method = TRUE,
  risk.table = TRUE,
  risk.table.y.text = FALSE,
  xlab = "Days from Discharge",
  ylab = "Cumulative Readmission Probability",
  title = "Kaplan-Meier: Readmission by SDOH Risk Group",
  legend.title = "SDOH Risk",
  legend.labs = c("Low-Moderate", "High-Very High"),
  ggtheme = theme_minimal(base_size = 12),
  break.x.by = 5,
  xlim = c(0, 30)
)
ggsave("../tableau/km_sdoh_risk_group.png",
       print(p_km_sdoh), width = 10, height = 8, dpi = 150)


# 2b. KM by housing stability
km_housing <- survfit(Surv(time_to_event, event) ~ housing_group, data = survival_df)
cat("\n--- KM Survival by Housing Stability ---\n")
print(summary(km_housing, times = c(7, 14, 21, 30)))

p_km_housing <- ggsurvplot(
  km_housing,
  data = survival_df,
  fun = "event",
  palette = c("#0F766E", "#DC2626"),
  conf.int = TRUE,
  conf.int.alpha = 0.15,
  pval = TRUE,
  pval.method = TRUE,
  risk.table = TRUE,
  risk.table.y.text = FALSE,
  xlab = "Days from Discharge",
  ylab = "Cumulative Readmission Probability",
  title = "Kaplan-Meier: Readmission by Housing Stability",
  legend.title = "Housing",
  legend.labs = c("Stable", "Unstable/Homeless"),
  ggtheme = theme_minimal(base_size = 12),
  xlim = c(0, 30)
)
ggsave("../tableau/km_housing_stability.png",
       print(p_km_housing), width = 10, height = 8, dpi = 150)


# 2c. KM by diagnosis group (Heart Failure vs Others)
survival_df <- survival_df %>%
  mutate(hf_group = factor(
    if_else(primary_diagnosis_category == "Heart Failure", "Heart Failure", "Other Diagnoses"),
    levels = c("Other Diagnoses", "Heart Failure")
  ))

km_hf <- survfit(Surv(time_to_event, event) ~ hf_group, data = survival_df)
p_km_hf <- ggsurvplot(
  km_hf,
  data = survival_df,
  fun = "event",
  palette = c("#0F766E", "#DC2626"),
  conf.int = TRUE,
  pval = TRUE,
  risk.table = TRUE,
  xlab = "Days from Discharge",
  ylab = "Cumulative Readmission Probability",
  title = "Kaplan-Meier: Heart Failure vs Other Diagnoses",
  ggtheme = theme_minimal(base_size = 12),
  xlim = c(0, 30)
)
ggsave("../tableau/km_heart_failure.png",
       print(p_km_hf), width = 10, height = 8, dpi = 150)


# ============================================================
# 3. LOG-RANK TESTS
# ============================================================
cat("\n--- Log-Rank Tests ---\n")

lr_sdoh    <- survdiff(Surv(time_to_event, event) ~ sdoh_risk_group, data = survival_df)
lr_housing <- survdiff(Surv(time_to_event, event) ~ housing_group, data = survival_df)
lr_age     <- survdiff(Surv(time_to_event, event) ~ age_group, data = survival_df)

cat(sprintf("SDOH risk group log-rank p = %.4f\n",
    1 - pchisq(lr_sdoh$chisq, df = length(lr_sdoh$n) - 1)))
cat(sprintf("Housing stability log-rank p = %.4f\n",
    1 - pchisq(lr_housing$chisq, df = length(lr_housing$n) - 1)))
cat(sprintf("Age group log-rank p = %.4f\n",
    1 - pchisq(lr_age$chisq, df = length(lr_age$n) - 1)))


# ============================================================
# 4. COX PROPORTIONAL HAZARDS MODEL
# ============================================================
cat("\n--- Cox Proportional Hazards Model ---\n")

cox_model <- coxph(
  Surv(time_to_event, event) ~
    charlson_comorbidity_index +
    los_days +
    age +
    housing_unstable +
    food_insecure +
    social_support_score +
    area_deprivation_index +
    mental_health +
    medicare_medicaid,
  data = survival_df %>%
    mutate(
      housing_unstable   = if_else(housing_stability != "Stable", 1L, 0L),
      food_insecure      = if_else(food_security_status != "Secure", 1L, 0L),
      mental_health      = if_else(mental_health_diagnosis == "Yes", 1L, 0L),
      medicare_medicaid  = if_else(insurance_type %in% c("Medicare","Medicaid"), 1L, 0L)
    )
)

cat("\nCox Model Summary:\n")
print(summary(cox_model))

# Concordance (C-statistic)
cat(sprintf("\nConcordance (C-statistic): %.3f\n", summary(cox_model)$concordance[1]))

# Proportional hazards assumption test
cat("\nSchoenfeld residuals test (PH assumption):\n")
ph_test <- cox.zph(cox_model)
print(ph_test)


# ============================================================
# 5. HAZARD RATIO FOREST PLOT
# ============================================================
cox_results <- tidy(cox_model, exponentiate = TRUE, conf.int = TRUE)

p_cox_forest <- ggplot(cox_results, aes(x = estimate, y = reorder(term, estimate),
                                          colour = p.value < 0.05)) +
  geom_point(size = 3.5) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high), height = 0.3, linewidth = 0.8) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey40", linewidth = 1) +
  scale_colour_manual(values = c("grey60", "#DC2626"),
                       labels = c("p ≥ 0.05", "p < 0.05")) +
  scale_x_log10() +
  labs(
    title = "Hazard Ratios: Cox Proportional Hazards Model",
    subtitle = "Outcome: 30-day readmission | Error bars = 95% CI",
    x = "Hazard Ratio (log scale)",
    y = NULL,
    colour = "Significance"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave("../tableau/cox_hazard_ratios.png", p_cox_forest, width = 10, height = 7, dpi = 150)
print(p_cox_forest)


# ============================================================
# 6. MEDIAN SURVIVAL TIME BY SUBGROUP
# ============================================================
cat("\n--- Median Time to Readmission by Subgroup ---\n")

subgroups <- list(
  "Full cohort"           = survfit(Surv(time_to_event, event) ~ 1, data = survival_df),
  "SDOH High-Very High"   = survfit(Surv(time_to_event, event) ~ 1,
                                     data = filter(survival_df, sdoh_risk_group == "High-Very High SDOH")),
  "SDOH Low-Moderate"     = survfit(Surv(time_to_event, event) ~ 1,
                                     data = filter(survival_df, sdoh_risk_group == "Low-Moderate SDOH")),
  "Housing Unstable"      = survfit(Surv(time_to_event, event) ~ 1,
                                     data = filter(survival_df, housing_stability != "Stable")),
  "Heart Failure"         = survfit(Surv(time_to_event, event) ~ 1,
                                     data = filter(survival_df, primary_diagnosis_category == "Heart Failure"))
)

for (name in names(subgroups)) {
  median_t <- surv_median(subgroups[[name]])
  cat(sprintf("  %-30s  Median (days): %s  [95%% CI: %s – %s]\n",
      name,
      ifelse(is.na(median_t$median), ">30", round(median_t$median, 1)),
      ifelse(is.na(median_t$lower), "-", round(median_t$lower, 1)),
      ifelse(is.na(median_t$upper), "-", round(median_t$upper, 1))))
}

cat("\n=== Survival Analysis Complete ===\n")
cat("All output charts saved to ../tableau/\n")
