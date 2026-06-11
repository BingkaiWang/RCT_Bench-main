# RCT_Research

A comprehensive comparison of covariate adjustment methods for randomized controlled trials (RCTs), evaluating 6 statistical methods × 3 variable selection strategies (18 total combinations) using real-world trial data.

## Overview

This repository contains a systematic empirical study comparing various covariate adjustment methods for analyzing randomized controlled trials. The research evaluates the performance of multiple statistical approaches using 56 real-world RCT datasets, examining both continuous and binary outcomes.

## Key Features

- **56 Real-World RCT Datasets**: 50 non-clustered and 6 clustered randomized controlled trials
- **6 Statistical Methods**: Comprehensive comparison of modern causal inference and machine learning approaches
- **3 Variable Selection Strategies**: All covariates, top-3 by correlation, and manual/baseline selection
- **Standardized Pipeline**: Unified data cleaning and analysis workflow
- **Extensive Visualizations**: Publication-ready plots for method comparison and performance metrics

## Statistical Methods Compared

### Regression-Based Methods
- **Unadjusted**: Simple difference in means
- **ANCOVA**: Analysis of Covariance
- **ANHECOVA**: Heteroscedasticity-Robust ANCOVA

### Robust Methods (RobinCar)
- **RC-ANCOVA**: Robust covariate adjustment
- **RC-ANHECOVA**: Robust heteroscedasticity-adjusted covariate adjustment
- **RC-Logistic G-Computation**: Model-based standardization for binary outcomes

### Machine Learning Ensemble
- **SuperLearner Ensemble**: Optimal weighted combination of base learners
- **Individual SuperLearner Methods**:
  - GLM (Generalized Linear Models)
  - Elastic Net (glmnet)
  - CART (rpart)
  - Random Forest
  - GAM (Generalized Additive Models)
  - BART (Bayesian Additive Regression Trees)

### Causal Inference Methods
- **TMLE**: Targeted Maximum Likelihood Estimation (with SuperLearner)
- **AIPW**: Augmented Inverse Probability Weighting (with SuperLearner)
- **IPW**: Inverse Probability Weighting

## Variable Selection Strategies

1. **All Covariates**: Use all available baseline covariates
2. **Top-3 Correlation**: Select 3 covariates most correlated with the outcome
3. **Manual/Baseline**: Domain-knowledge driven selection with baseline measures

## Repository Structure

```Text
RCT_Data/
├── raw_data/                       # Raw trial data from public sources
│   ├── Non_Clustered_RCT/          # 50 individually randomized trials
│   └── Clustered_RCT/              # 6 cluster-randomized trials
├── cleaned_data/                   # Standardized analysis-ready datasets
│   ├── Non_Clustered_RCT/          # Processed trial data
│   ├── Clustered_RCT/              # Processed cluster trial data
│   ├── Plot/                       # Generated visualization outputs
│   ├── meta_data.xlsx              # Trial metadata and characteristics
│   ├── meta_data_cluster.xlsx      # Cluster trial metadata
│   ├── meta_data_demo.xlsx         # Demographic metadata
│   └── meta_data_comparison.xlsx   # Method comparison results
├── RCT_data_cleaning.Rmd           # Unified data cleaning & variable standardization
├── RCT_analysis.Rmd                # Main analysis pipeline (6 methods × 3 strategies = 18 combinations)
└── RCT_Workspace.Rmd               # Optional exploratory workspace
```

## Usage

### 1. Data Cleaning

The `RCT_data_cleaning.Rmd` script processes raw trial data and standardizes variables:

```r
# Open RCT_data_cleaning.Rmd and run all chunks to:
# - Load raw trial data from various sources
# - Standardize variable naming conventions
# - Compute outcome measures (YP_* for primary, YS_* for secondary)
# - Create baseline covariates (X_*)
# - Export cleaned .rds and .csv files
```

**Variable Naming Convention:**
- `YP_*`: Primary outcomes
- `YS_*`: Secondary outcomes
- `X_*`: Baseline covariates
- `Treatment`: Treatment assignment variable

### 2. Running the Analysis

The `RCT_analysis.Rmd` script performs the comprehensive method comparison:

```r
# Open RCT_analysis.Rmd and execute sequentially:
# 1. Load cleaned trial datasets
# 2. Apply each of 6 methods with 3 selection strategies (18 total combinations)
# 3. Compare estimates and standard errors
# 4. Generate visualizations
# 5. Export comparison results
```

### 3. Exploring Results

Results are saved in `cleaned_data/meta_data_comparison.xlsx` with columns:
- Treatment effect estimates for each method
- Standard errors for precision comparison
- Relative efficiency metrics
- Covariate selection details

## Outcome Types

The analysis handles both:
- **Continuous outcomes**: Changes in quantitative measures (e.g., blood pressure, BMI)
- **Binary outcomes**: Event indicators (e.g., disease occurrence, treatment success)

## Performance Metrics

The study evaluates methods based on:
- **Precision Gain**: Reduction in standard error relative to unadjusted analysis
- **Estimate Stability**: Consistency across variable selection strategies
- **Computational Efficiency**: Runtime and convergence properties
- **Robustness**: Performance across different outcome types and trial characteristics

## Visualizations

The `cleaned_data/Plot/` directory contains:
- Method comparison plots (combined and stratified by outcome type)
- Precision gain visualizations
- Sample size relationship plots
- Trial characteristic distributions
- Covariate selection impact analysis

## Key Findings

The analysis reveals:
- Comparative performance of classical vs. modern methods
- Impact of variable selection strategy on different methods
- Trade-offs between precision and robustness
- Method recommendations based on trial characteristics

## Data Sources

All RCT data are obtained from publicly available sources and published clinical trials. Trial metadata includes:
- Publication year
- Research area (medical specialty)
- Sample size
- Randomization scheme
- Number of treatment arms
- Outcome types
