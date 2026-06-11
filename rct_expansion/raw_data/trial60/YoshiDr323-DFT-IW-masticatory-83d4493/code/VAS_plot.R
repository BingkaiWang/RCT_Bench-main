library(dplyr); library(tidyr); library(broom)

# ==== 入力データ ====
dat_long <- read.csv("DFT_VAS_spellout.csv",
                     header = T,
                     stringsAsFactors = F,
                     fileEncoding = "SJIS")
value_col <- "VAS"     # 例: "VAS"

# 前処理（Timeの順序を固定）
dat_long <- dat_long %>%
  mutate(
    Time = factor(Time, levels = c("Pre","Post")),
    Treatment = as.character(Treatment),
    VAS = as.numeric(VAS)
  )

# Treatmentごとの対応t検定（Post vs Pre）
t_results <- dat_long %>%
  select(ID, Treatment, Time, VAS) %>%
  pivot_wider(names_from = Time, values_from = VAS) %>%
  drop_na(Pre, Post) %>%
  group_by(Treatment) %>%
  summarise(
    n_pairs   = n(),
    mean_Pre  = mean(Pre),
    mean_Post = mean(Post),
    mean_Diff = mean(Post - Pre),
    # t検定（paired）
    tidied = list(t.test(Post, Pre, paired = TRUE) %>% tidy(conf.int = TRUE)),
    .groups = "drop"
  ) %>%
  unnest_wider(tidied) %>%     # estimate, conf.low, conf.high, statistic, parameter, p.value
  transmute(
    Treatment,
    n_pairs,
    mean_Pre, mean_Post, mean_Diff,
    CI_low = conf.low, CI_high = conf.high,
    t = statistic, df = parameter, p = p.value
  ) %>%
  mutate(
    across(c(mean_Pre, mean_Post, mean_Diff, CI_low, CI_high), ~round(.x, 2)),
    t  = round(t, 3),
    df = round(df, 1),
    p  = signif(p, 3)
  )

t_results

# install.packages("ggplot2")
library(ggplot2)

# Pre/Postを並べた箱ひげ図（処置ごとにfacet）
p1 <- ggplot(dat_long, aes(x = Time, y = VAS)) +
  geom_boxplot(outlier.shape = NA) +
  geom_point(aes(group = ID), position = position_jitter(width = 0.08, height = 0), alpha = 0.5) +
  geom_line(aes(group = ID), alpha = 0.3) +
  facet_wrap(~ Treatment, nrow = 1) +
  labs(title = "VAS: Pre vs Post by Treatment (paired)",
       x = NULL, y = "VAS (mm)") +
  theme_bw()

p1
