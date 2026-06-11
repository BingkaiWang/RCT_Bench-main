# Expansion Format Check

Run date: 2026-06-11

- Original trials checked: 50
- Expansion trials checked: 71
- Expansion hard-format pass: 71/71
- Expansion analysis-compatible pass: 71/71
- Expansion warning rows: 6

Hard-format pass requires CSV/RDS pair, matching names, data-frame RDS, factor Treatment, non-missing Treatment, at least two arms, at least one YP_ outcome, no unsupported column prefixes, no duplicate names, and syntactic column names.

Analysis-compatible pass additionally requires no all-missing YP_/YS_ outcome columns. Nonnumeric categorical outcomes are reported as warnings but are allowed because the original trials include such outcomes too.

## Warnings

- trial55: categorical/non-numeric outcomes: YS_pulmonary_rehab_attendance_12m
- trial92: categorical/non-numeric outcomes: YS_malaria_diagnosis_2m;YS_malaria_diagnosis_4m
- trial95: categorical/non-numeric outcomes: YS_postop_throat_pain
- trial101: categorical/non-numeric outcomes: YP_eq5d_pain_3m
- trial103: categorical/non-numeric outcomes: YP_eq5d_pain_3m;YS_mmse_3m
- trial114: categorical/non-numeric outcomes: YP_rankin_3m;YS_nihss_day7;YS_barthel_3m
