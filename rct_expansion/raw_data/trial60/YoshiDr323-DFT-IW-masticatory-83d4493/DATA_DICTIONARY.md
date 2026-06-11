# DATA_DICTIONARY

## data/processed/DFT_glucose.csv
| Column    | Type   | Unit  | Description                                    |
|-----------|--------|-------|------------------------------------------------|
| ID        | int    | –     | Participant ID (re-coded, non-identifiable)   |
| Sequence  | factor | –     | Randomization sequence: A (S→N) or B (N→S)     |
| Period    | int    | –     | Period number (1 or 2)                         |
| Treatment | factor | –     | S = stimulation, N = sham                      |
| Time      | factor | –     | Pre or Post                                    |
| Value     | number | mg/dL | Glucose elution concentration                  |

## data/processed/DFT_VAS.csv
| Column    | Type   | Unit | Description                                     |
|-----------|--------|------|-------------------------------------------------|
| ID        | int    | –    | Participant ID (re-coded, non-identifiable)    |
| Sequence  | factor | –    | Randomization sequence: A (S→N) or B (N→S)      |
| Period    | int    | –    | Period number (1 or 2)                          |
| Treatment | factor | –    | S = stimulation, N = sham                       |
| Time      | factor | –    | Pre or Post                                     |
| VAS       | number | mm   | Visual analogue scale (ease of chewing), 0–100  |

**Units** are standardized as `mg/dL` and `mm`. No direct identifiers are present.
