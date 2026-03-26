# ============================================================
# Hospital Readmission & SDOH Analytics
# R Script: SDOH Logistic Regression Analysis
# ============================================================

# Install required packages (run once)
# install.packages(c("tidyverse", "ggplot2", "gtsummary", "broom", "pROC", "car"))

library(tidyverse)
library(ggplot2)
library(gtsummary)
library(broom)
library(pROC)
library(car)

cat("=== SDOH Logistic Regression Analysis ===\n\n")

# ============================================================
# 1. LOAD & PREPARE DATA
# ============================================================
patients   <- read_csv("../data/patients.csv")
admissions <- read_csv("../data/admissions.csv")
sdoh       <- read_csv("../data/sdoh_indicators.csv")

# Index admissions only
index_adm <- admissions %>% filter(is_readmission == "No")

# Merge all data
df <- index_adm %>%
  left_join(patients, by = "patient_id") %>%
  left_join(sdoh, by = "patient_id") %>%
  mutate(
    # Binary outcome
    readmitted = if_else(readmitted_30day == "Yes", 1L, 0L),
    # Factor encoding
    housing_unstable = if_else(housing_stability != "Stable", 1L, 0L),
    food_insecure    = if_else(food_security_status != "Secure", 1L, 0L),
    transport_barrier = if_else(transportation_barrier == "Yes", 1L, 0L),
    mental_health    = if_else(mental_health_diagnosis == "Yes", 1L, 0L),
    substance_use    = if_else(substance_use_disorder == "Yes", 1L, 0L),
    medicare_medicaid = if_else(insurance_type %in% c("Medicare", "Medicaid"), 1L, 0L),
    age_group = case_when(
      age < 65 ~ "Under 65",
      age < 75 ~ "65-74",
      age < 85 ~ "75-84",
      TRUE     ~ "85+"
    ) %>% factor(levels = c("Under 65", "65-74", "75-84", "85+")),
    diagnosis_category = factor(primary_diagnosis_category)
  )

cat(sprintf("Index admissions: %d | Readmissions: %d (%.1f%%)\n\n",
    nrow(df), sum(df$readmitted), 100 * mean(df$readmitted)))


# ============================================================
# 2. DESCRIPTIVE STATISTICS BY READMISSION STATUS
# ============================================================
cat("--- Table 1: Patient Characteristics by Readmission Status ---\n")

tbl1 <- df %>%
  select(readmitted, age, gender, insurance_type,
         primary_diagnosis_category, charlson_comorbidity_index, los_days,
         housing_stability, food_security_status, sdoh_risk_score,
         social_support_score, area_deprivation_index) %>%
  tbl_summary(
    by = readmitted,
    label = list(
      age ~ "Age (years)",
      charlson_comorbidity_index ~ "Charlson Comorbidity Index",
      los_days ~ "Length of Stay (days)",
      sdoh_risk_score ~ "SDOH Risk Score",
      social_support_score ~ "Social Support Score",
      area_deprivation_index ~ "Area Deprivation Index"
    ),
    statistic = list(
      all_continuous() ~ "{mean} ({sd})",
      all_categorical() ~ "{n} ({p}%)"
    )
  ) %>%
  add_p() %>%
  add_overall() %>%
  bold_labels()

print(tbl1)


# ============================================================
# 3. UNIVARIABLE LOGISTIC REGRESSION — SDOH FACTORS
# ============================================================
cat("\n--- Univariable Logistic Regression: SDOH Predictors ---\n")

sdoh_vars <- c("housing_unstable", "food_insecure", "transport_barrier",
               "mental_health", "substance_use", "social_support_score",
               "area_deprivation_index", "sdoh_risk_score")

univar_results <- map_dfr(sdoh_vars, function(var) {
  formula_str <- paste("readmitted ~", var)
  model <- glm(as.formula(formula_str), data = df, family = binomial)
  tidy(model, exponentiate = TRUE, conf.int = TRUE) %>%
    filter(term != "(Intercept)") %>%
    mutate(variable = var)
}) %>%
  mutate(
    sig = case_when(
      p.value < 0.001 ~ "***",
      p.value < 0.01  ~ "**",
      p.value < 0.05  ~ "*",
      p.value < 0.1   ~ ".",
      TRUE            ~ ""
    )
  )

cat(sprintf("%-30s %8s %8s %8s %8s %4s\n",
    "Variable", "OR", "CI_Low", "CI_High", "P-value", "Sig"))
cat(strrep("-", 70), "\n")
for (i in seq_len(nrow(univar_results))) {
  row <- univar_results[i, ]
  cat(sprintf("%-30s %8.3f %8.3f %8.3f %8.4f %4s\n",
      row$variable, row$estimate, row$conf.low, row$conf.high,
      row$p.value, row$sig))
}


# ============================================================
# 4. MULTIVARIABLE LOGISTIC REGRESSION
# ============================================================
cat("\n--- Multivariable Logistic Regression ---\n")

# Model 1: Clinical features only
model_clinical <- glm(
  readmitted ~ charlson_comorbidity_index + los_days + age + medicare_medicaid +
    diagnosis_category + icu_stay,
  data = df, family = binomial
)

# Model 2: SDOH features only
model_sdoh <- glm(
  readmitted ~ housing_unstable + food_insecure + transport_barrier +
    mental_health + substance_use + social_support_score + area_deprivation_index,
  data = df, family = binomial
)

# Model 3: Full model (clinical + SDOH)
model_full <- glm(
  readmitted ~ charlson_comorbidity_index + los_days + age + medicare_medicaid +
    diagnosis_category + housing_unstable + food_insecure + transport_barrier +
    mental_health + social_support_score + area_deprivation_index,
  data = df, family = binomial
)

# Summary of full model
cat("\nFull Model Summary (Odds Ratios):\n")
full_results <- tidy(model_full, exponentiate = TRUE, conf.int = TRUE) %>%
  filter(term != "(Intercept)") %>%
  arrange(p.value)
print(full_results, n = 20)


# ============================================================
# 5. MODEL COMPARISON
# ============================================================
cat("\n--- Model Performance Comparison ---\n")

# Predicted probabilities
df$pred_clinical <- predict(model_clinical, type = "response")
df$pred_sdoh     <- predict(model_sdoh, type = "response")
df$pred_full     <- predict(model_full, type = "response")

# ROC-AUC
roc_clinical <- roc(df$readmitted, df$pred_clinical, quiet = TRUE)
roc_sdoh     <- roc(df$readmitted, df$pred_sdoh, quiet = TRUE)
roc_full     <- roc(df$readmitted, df$pred_full, quiet = TRUE)

cat(sprintf("  AUC — Clinical only:   %.3f\n", auc(roc_clinical)))
cat(sprintf("  AUC — SDOH only:       %.3f\n", auc(roc_sdoh)))
cat(sprintf("  AUC — Full model:      %.3f\n", auc(roc_full)))
cat(sprintf("  AUC improvement (Full vs Clinical): +%.3f\n",
    auc(roc_full) - auc(roc_clinical)))


# ============================================================
# 6. VISUALISATIONS
# ============================================================

# 6.1 Forest plot: odds ratios for full model
forest_data <- tidy(model_full, exponentiate = TRUE, conf.int = TRUE) %>%
  filter(term != "(Intercept)") %>%
  mutate(
    significant = p.value < 0.05,
    term = str_replace_all(term, "diagnosis_category", "Dx: ")
  )

p_forest <- ggplot(forest_data, aes(x = estimate, y = reorder(term, estimate),
                                     colour = significant)) +
  geom_point(size = 3) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high), height = 0.3) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50") +
  scale_colour_manual(values = c("grey60", "#DC2626"),
                       labels = c("p ≥ 0.05", "p < 0.05")) +
  labs(
    title = "Odds Ratios: Predictors of 30-Day Readmission",
    subtitle = "Full model (clinical + SDOH features) | 95% Confidence Intervals",
    x = "Odds Ratio (log scale)",
    y = NULL,
    colour = "Significance"
  ) +
  scale_x_log10() +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave("../tableau/forest_plot_odds_ratios.png", p_forest, width = 10, height = 7, dpi = 150)
print(p_forest)

# 6.2 ROC curves comparison
png("../tableau/roc_curves_comparison.png", width = 800, height = 600, res = 120)
plot(roc_clinical, col = "#6B7280", lwd = 2,
     main = "ROC Curves: Clinical vs SDOH vs Full Model",
     xlab = "1 - Specificity", ylab = "Sensitivity")
plot(roc_sdoh, col = "#0F766E", lwd = 2, add = TRUE)
plot(roc_full, col = "#DC2626", lwd = 2.5, add = TRUE)
legend("bottomright",
       legend = c(
         sprintf("Clinical only (AUC=%.2f)", auc(roc_clinical)),
         sprintf("SDOH only (AUC=%.2f)", auc(roc_sdoh)),
         sprintf("Full model (AUC=%.2f)", auc(roc_full))
       ),
       col = c("#6B7280", "#0F766E", "#DC2626"), lwd = 2, cex = 0.9)
dev.off()

# 6.3 Readmission rate by SDOH risk tier
sdoh_tier_plot <- df %>%
  mutate(sdoh_tier = case_when(
    sdoh_risk_score <= 2 ~ "Low (1-2)",
    sdoh_risk_score <= 5 ~ "Moderate (3-5)",
    sdoh_risk_score <= 8 ~ "High (6-8)",
    TRUE ~ "Very High (9-10)"
  ) %>% factor(levels = c("Low (1-2)", "Moderate (3-5)", "High (6-8)", "Very High (9-10)"))) %>%
  group_by(sdoh_tier) %>%
  summarise(
    patients = n(),
    readmitted_count = sum(readmitted),
    readmission_rate = mean(readmitted)
  )

p_sdoh_tier <- ggplot(sdoh_tier_plot, aes(x = sdoh_tier, y = readmission_rate,
                                            fill = sdoh_tier)) +
  geom_col(width = 0.65, colour = "white") +
  geom_text(aes(label = sprintf("%.1f%%\n(n=%d)", readmission_rate * 100, patients)),
             vjust = -0.4, fontface = "bold", size = 4) +
  geom_hline(yintercept = 0.155, linetype = "dashed", colour = "#6B7280", linewidth = 1) +
  annotate("text", x = 4.5, y = 0.16, label = "CMS Benchmark\n15.5%",
           colour = "#6B7280", size = 3.5, hjust = 1) +
  scale_fill_manual(values = c("#059669", "#FBBF24", "#F97316", "#DC2626")) +
  scale_y_continuous(labels = scales::percent_format(), limits = c(0, 0.7)) +
  labs(
    title = "30-Day Readmission Rate by SDOH Risk Tier",
    x = "SDOH Risk Tier", y = "Readmission Rate", fill = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none")

ggsave("../tableau/readmission_by_sdoh_tier.png", p_sdoh_tier,
       width = 9, height = 6, dpi = 150)
print(p_sdoh_tier)

cat("\n=== Analysis Complete ===\n")
cat("Output charts saved to ../tableau/\n")
