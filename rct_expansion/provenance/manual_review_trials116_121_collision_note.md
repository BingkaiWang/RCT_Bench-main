# Manual-review cleaning ID collision note

Generated: 2026-06-11

The manual-review cleaning batch for candidates RCTC-01557, RCTC-02282,
RCTC-05010, RCTC-02127, RCTC-04923, and RCTC-04272 was first written to
`rct_expansion/cleaned_data/trial100.csv/.rds` through
`trial105.csv/.rds` before noticing that the cleaned-data folder already
contained files numbered through `trial115`.

The batch has been reissued under the next unused IDs:

- `trial116`: RCTC-01557
- `trial117`: RCTC-02282
- `trial118`: RCTC-05010
- `trial119`: RCTC-02127
- `trial120`: RCTC-04923
- `trial121`: RCTC-04272

Current corrected outputs:

- `rct_expansion/cleaned_data/trial116.csv/.rds` through `trial121.csv/.rds`
- `rct_expansion/raw_data/trial116/` through `trial121/`
- `rct_expansion/provenance/validation_summary_manual_review_trials116_121.csv`
- `rct_expansion/metadata/meta_data_manual_review_trials116_121.csv/.xlsx`
- `rct_expansion/metadata/data_dictionary_manual_review_trials116_121.csv`

The earlier `manual_review_trials100_105` provenance outputs are superseded
and should not be used for active numbering. The pre-existing original
`trial100` through `trial105` cleaned outputs need to be restored from a
separate backup, Dropbox version history, or their original generator if
available.
