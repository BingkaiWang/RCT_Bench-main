library(tidyr)
library(dplyr)
library(ggplot2)
library(lme4)
library(lmerTest)
library(performance)

#setwd("R")

data <- read.csv("DFT_glucose.csv",
                 header = T,
                 stringsAsFactors = F,
                 fileEncoding = "SJIS")

delta_data <- data |>
  pivot_wider(names_from = Time, values_from = Value) |>
  mutate(Delta = Post - Pre) |>
  mutate(
    Treatment = factor(Treatment, levels = c("N","S")), # S?D?ʂȂ?S?̌W????????
    Period    = factor(Period),
    Sequence  = factor(Sequence)
  )
delta_data |>
  group_by(Treatment) |>
  summarise(n=n(), mean_delta=mean(Delta), sd=sd(Delta)) |>
  print(digits=3)
ggplot(delta_data, aes(x=Treatment, y=Delta)) +
  geom_boxplot() +
  geom_jitter(width = 0.1, alpha = 0.5) +
  labs(title="glucose concentration (Delta: Post-Pre) by Treatment", y="Delta (mg/dL)")

wide_pair <- delta_data |>
  select(ID, Treatment, Delta) |>
  pivot_wider(names_from = Treatment, values_from = Delta)
t_out <- t.test(wide_pair$S, wide_pair$N, paired = TRUE)
t_out
m2 <- lmer(Delta ~ Treatment + Period + Sequence + (1|ID), data = delta_data)
summary(m2)
#performance::check_model(m2)
