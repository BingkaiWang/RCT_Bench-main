"""Controlled metadata categories for the public RCT Bench workbook."""

from __future__ import annotations


OUTCOME_TYPE_BY_TRIAL: dict[int, str] = {}

for trial_id in [
    1, 4, 6, 7, 11, 12, 14, 15, 16, 17, 19, 20, 30, 32, 33, 35, 36,
    45, 46, 48, 51, 53, 54, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
    66, 67, 68, 69, 70, 74, 75, 76, 77, 79, 80, 83, 84, 85, 87, 89,
    90, 91, 95, 96, 97, 99, 105, 106, 107, 109, 110, 111, 116, 117,
    118, 119, 121, 122, 123, 124, 125, 100, 103,
]:
    OUTCOME_TYPE_BY_TRIAL[trial_id] = "Continuous"

for trial_id in [
    3, 5, 8, 9, 10, 22, 24, 28, 34, 37, 41, 44, 47, 71, 72, 78, 81,
    82, 86, 88, 93, 94, 102, 108, 113, 115,
]:
    OUTCOME_TYPE_BY_TRIAL[trial_id] = "Binary"

for trial_id in [2, 21, 23, 29, 31, 38, 39, 40, 42, 43, 50, 98, 112, 120]:
    OUTCOME_TYPE_BY_TRIAL[trial_id] = "Time-to-event"

for trial_id in [55, 104]:
    OUTCOME_TYPE_BY_TRIAL[trial_id] = "Count"

for trial_id in [27, 73, 101, 114]:
    OUTCOME_TYPE_BY_TRIAL[trial_id] = "Ordinal"

OUTCOME_TYPE_BY_TRIAL.update(
    {
        13: "Continuous; Binary",
        18: "Continuous; Time-to-event",
        25: "Continuous; Count; Ordinal",
        26: "Continuous; Binary; Categorical",
        49: "Continuous; Ordinal",
        52: "Continuous; Ordinal",
        92: "Count; Ordinal",
    }
)

if set(OUTCOME_TYPE_BY_TRIAL) != set(range(1, 126)):
    missing = sorted(set(range(1, 126)) - set(OUTCOME_TYPE_BY_TRIAL))
    duplicates_or_extra = sorted(set(OUTCOME_TYPE_BY_TRIAL) - set(range(1, 126)))
    raise RuntimeError(
        f"Outcome taxonomy must cover trials 1-125 exactly; missing={missing}, extra={duplicates_or_extra}"
    )


RESEARCH_AREA_GROUPS: dict[str, tuple[str, ...]] = {
    "Anesthesiology & Pain Medicine": (
        "Anesthesia/respiratory physiology",
        "Anesthesiology",
        "Anesthesiology/Pain Medicine",
        "Pain medicine",
        "Pain pharmacology",
        "Pediatric anesthesia/emergency airway",
        "Surgery/Anesthesiology",
    ),
    "Cardiovascular Medicine": (
        "Cardiac rehabilitation",
        "Cardiology/Nutrition",
        "Cardiovascular",
    ),
    "Dentistry & Oral Health": (
        "Dentistry",
        "Dentistry/oral rehabilitation",
        "Orthodontics",
    ),
    "Emergency, Pulmonary & Critical Care": (
        "Critical Care",
        "Emergency Medicine",
        "Pulmonology",
    ),
    "Gastroenterology & Hepatology": (
        "Gastroenterology",
        "Hepatology",
    ),
    "General Medicine, Health Services & Education": (
        "Geriatrics",
        "Medical Education",
        "Pharmacy/health services",
        "Research Ethics",
    ),
    "Infectious Diseases & Immunology": (
        "COVID-19",
        "HIV/AIDS",
        "Immunology",
        "Infectious Disease",
        "Inflammation/placebo effects",
        "Malaria prevention/pregnancy",
        "Malaria treatment adherence",
        "Obstetrics/infectious disease",
        "Tuberculosis treatment adherence",
    ),
    "Mental & Behavioral Health": (
        "Behavioral medicine/mindfulness",
        "Lifestyle/Behavioral Medicine",
        "Mental Health",
        "Neuropsychology/burnout",
        "Psychiatry",
    ),
    "Nephrology": (
        "Nephrology",
        "Nephrology/critical care",
        "Nephrology/transplantation",
    ),
    "Neurology & Neurorehabilitation": (
        "Cognitive training",
        "Neurology",
        "Neurology/complementary medicine",
        "Neurology/rehabilitation",
        "Pediatric ADHD/neurofeedback",
        "Sports performance/neuromodulation",
        "Stroke rehabilitation",
        "Traumatic brain injury/neurorehabilitation",
    ),
    "Nutrition, Metabolism & Lifestyle": (
        "Digital health/obesity",
        "Endocrinology",
        "Nutrition",
        "Nutrition/metabolism",
        "Obesity/behavioral medicine",
        "Physical activity/preventive health",
        "Sports Medicine/Sleep",
        "Type 2 Diabetes",
    ),
    "Oncology": (
        "Oncology",
        "Oncology supportive care/psycho-oncology",
    ),
    "Rehabilitation & Physical Medicine": (
        "Occupational rehabilitation",
        "Pediatric Rehabilitation",
        "Rehabilitation",
        "Rehabilitation/balance",
        "Sports medicine/rehabilitation",
    ),
    "Surgery": (
        "Dermatology/surgical nursing",
        "Surgery",
        "Surgery/Transplantation",
        "Surgery/wound healing",
        "Urology/digital health",
    ),
    "Women's, Maternal & Child Health": (
        "Gynecology/outpatient hysteroscopy",
        "Maternal & Child Health",
        "Neonatology",
        "Obstetrics",
        "Obstetrics/Gynecology",
        "Pediatrics",
        "Urogynecology",
        "Women's health education",
    ),
}

RESEARCH_AREA_BY_LEGACY = {
    legacy: grouped
    for grouped, legacy_values in RESEARCH_AREA_GROUPS.items()
    for legacy in legacy_values
}


def standard_outcome_type(trial_id: int) -> str:
    return OUTCOME_TYPE_BY_TRIAL[trial_id]


def grouped_research_area(value: object) -> str:
    text = "" if value is None else str(value).strip()
    if text in RESEARCH_AREA_GROUPS:
        return text
    if text not in RESEARCH_AREA_BY_LEGACY:
        raise ValueError(f"Unmapped research area: {text!r}")
    return RESEARCH_AREA_BY_LEGACY[text]
