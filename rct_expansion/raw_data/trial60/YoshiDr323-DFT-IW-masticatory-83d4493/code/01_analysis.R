# 01_analysis.R — primary and sensitivity analyses (reproducible)
set.seed(20250824)

suppressPackageStartupMessages({
  library(tidyverse)
  library(lme4)
  library(lmerTest)
  library(broom.mixed)
})

# Read data
g <- readr::read_csv('data/processed/DFT_glucose.csv', show_col_types = FALSE) %>%
  mutate(
    Treatment = factor(Treatment, levels = c('N','S')),
    Period = as.integer(Period),
    Sequence = factor(Sequence, levels = c('A','B')),
    Time = factor(Time, levels = c('Pre','Post'))
  )

# Compute within-session delta for glucose
gl_wide <- g %>% select(ID, Sequence, Period, Treatment, Time, Value) %>%
  pivot_wider(names_from = Time, values_from = Value)

gl_delta <- gl_wide %>%
  mutate(delta_glucose = Post - Pre) %>%
  select(ID, Sequence, Period, Treatment, delta_glucose)

# Primary crossover model
# Δ_ij = β0 + β1·Treatment_ij + β2·Period_j + β3·Sequence_i + u_i + ε_ij
fit <- lmer(delta_glucose ~ Treatment + Period + Sequence + (1|ID), data = gl_delta)
summ <- summary(fit)
print(summ)

# Sensitivity: paired t-test (Δ between S and N within subject)
gl_pair <- gl_delta %>% select(ID, Treatment, delta_glucose) %>% pivot_wider(names_from = Treatment, values_from = delta_glucose)
tt <- with(gl_pair, t.test(S, N, paired = TRUE))

# Secondary (VAS): Wilcoxon paired on Δ
v <- readr::read_csv('data/processed/DFT_VAS.csv', show_col_types = FALSE) %>%
  mutate(Treatment = factor(Treatment, levels = c('N','S')), Time = factor(Time, levels = c('Pre','Post')))
v_wide <- v %>% select(ID, Treatment, Time, VAS) %>% pivot_wider(names_from = Time, values_from = VAS)
v_delta <- v_wide %>% transmute(ID, Treatment, delta_vas = Post - Pre) %>%
  pivot_wider(names_from = Treatment, values_from = delta_vas)
wt <- wilcox.test(v_delta$S, v_delta$N, paired = TRUE, exact = FALSE)

# Save outputs
dir.create('results/tables', showWarnings = FALSE, recursive = TRUE)
dir.create('results/figures', showWarnings = FALSE, recursive = TRUE)

sink('results/tables/model_summary.txt'); print(summ); sink()
sink('results/tables/paired_t_glucose.txt'); print(tt); sink()
sink('results/tables/wilcoxon_vas.txt'); print(wt); sink()

# Simple figure: Δ glucose by Treatment
gl_plot <- gl_delta %>% ggplot(aes(Treatment, delta_glucose)) + geom_boxplot() + geom_jitter(width = 0.1, alpha = 0.5) +
  labs(x = 'Treatment', y = 'Δ glucose (mg/dL)', title = 'Within-session change by treatment')
ggsave('results/figures/delta_glucose_boxplot.png', gl_plot, width = 5, height = 4, dpi = 300)
