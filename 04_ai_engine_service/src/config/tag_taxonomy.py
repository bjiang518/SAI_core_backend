"""
Question Tag Taxonomy — predefined tag sets for all subjects.

Four tag dimensions:
  skill_tags       — cognitive skill the question tests
  style_tags       — question flavor / context (universal + subject-specific)
  mc_strategy_tags — only for multiple_choice questions (universal)
  error_micro_tags — specific error pattern (only for wrong answers),
                     keyed by the macro error_type they belong to

Usage:
    from config.tag_taxonomy import get_allowed_tags
    allowed = get_allowed_tags("Math", grade_level="8th Grade", question_type="multiple_choice")
"""

# ---------------------------------------------------------------------------
# Universal tags — apply to every subject
# ---------------------------------------------------------------------------

UNIVERSAL_STYLE_TAGS = [
    "multi_step",           # 3+ intermediate steps required
    "single_step",          # one direct concept application
    "real_world_applied",   # applied to a real-world scenario
    "data_interpretation",  # read tables / charts
    "graphical",            # involves graphs or diagrams
]

UNIVERSAL_MC_STRATEGY_TAGS = [
    "distractor_trap",      # a wrong option exploits a common misconception
    "elimination_method",   # easiest solved by eliminating wrong choices
    "backsolve",            # plug answer choices back into the question
    "estimate_to_eliminate",# approximate to rule out extreme options
    "ordering_comparison",  # "which is greatest / least" type
]

# Universal error_micro_tags — valid regardless of subject
UNIVERSAL_ERROR_MICRO = {
    "execution_error":   ["misread_problem", "transcription_error"],
    "conceptual_gap":    ["misread_problem"],
    "needs_refinement":  ["incomplete_solution"],
}

# ---------------------------------------------------------------------------
# Subject-specific tags
# ---------------------------------------------------------------------------

SUBJECT_TAGS = {

    "Math": {
        "skill_tags": [
            "quick_computation",
            "algebraic_manipulation",
            "pattern_recognition",
            "logical_deduction",
            "formula_recall_apply",
            "spatial_reasoning",
            "number_sense",
            "word_problem_modeling",
            "estimation",
            "proof_construction",
        ],
        "style_tags": [
            "olympiad",
            "computation_heavy",
            "proof_based",
            "visual_model",
        ],
        "error_micro_tags": {
            "execution_error": [
                "arithmetic_slip",
                "sign_error",
                "decimal_placement",
                "order_of_operations",
                "algebraic_slip",
                "unit_omission",
            ],
            "conceptual_gap": [
                "wrong_formula",
                "definition_wrong",
                "scope_violation",
                "setup_error",
                "inverse_direction",
                "condition_ignored",
            ],
            "needs_refinement": [
                "rounding_error",
                "notation_error",
            ],
        },
    },

    "Physics": {
        "skill_tags": [
            "vector_analysis",
            "diagram_analysis",
            "unit_analysis",
            "formula_chaining",
            "conceptual_reasoning",
            "graph_interpretation",
        ],
        "style_tags": [
            "lab_experimental",
            "calculation_heavy",
            "conceptual_qualitative",
        ],
        "error_micro_tags": {
            "execution_error": [
                "vector_direction_wrong",
                "unit_conversion_error",
                "trig_ratio_error",
                "arithmetic_slip",
                "sign_error",
            ],
            "conceptual_gap": [
                "wrong_law_applied",
                "force_direction_confused",
                "energy_form_confused",
                "inertia_misunderstood",
                "field_direction_wrong",
            ],
            "needs_refinement": [
                "sig_fig_error",
                "diagram_missing",
                "unit_omission",
            ],
        },
    },

    "Chemistry": {
        "skill_tags": [
            "stoichiometry_calc",
            "formula_writing",
            "balancing_equations",
            "periodic_trends_reasoning",
            "lab_data_interpretation",
        ],
        "style_tags": [
            "calculation_heavy",
            "equation_based",
            "concept_check",
        ],
        "error_micro_tags": {
            "execution_error": [
                "arithmetic_slip",
                "mole_ratio_wrong",
                "coefficient_error",
                "unit_conversion_error",
            ],
            "conceptual_gap": [
                "wrong_reaction_type",
                "charge_balance_wrong",
                "lewis_structure_error",
                "equilibrium_direction_wrong",
                "orbital_filling_wrong",
            ],
            "needs_refinement": [
                "sig_fig_error",
                "formula_notation_error",
                "state_symbol_missing",
            ],
        },
    },

    "Biology": {
        "skill_tags": [
            "diagram_interpretation",
            "process_sequencing",
            "definition_recall",
            "data_analysis",
            "cause_effect_reasoning",
        ],
        "style_tags": [
            "diagram_based",
            "case_study",
            "classification_type",
        ],
        "error_micro_tags": {
            "execution_error": [
                "terminology_confused",
                "sequence_order_wrong",
                "count_wrong",
            ],
            "conceptual_gap": [
                "process_direction_wrong",
                "organelle_function_confused",
                "inheritance_pattern_wrong",
                "evolution_mechanism_wrong",
                "structure_function_confused",
            ],
            "needs_refinement": [
                "vague_explanation",
                "incomplete_process",
            ],
        },
    },

    "English": {
        "skill_tags": [
            "inference",
            "author_intent_analysis",
            "grammar_application",
            "vocabulary_context",
            "text_evidence_citation",
            "argument_evaluation",
            "tone_identification",
        ],
        "style_tags": [
            "passage_based",
            "grammar_drill",
            "vocabulary_in_context",
            "writing_analysis",
        ],
        "mc_strategy_tags_extra": [  # english-specific additions to universal MC tags
            "closest_meaning",
            "best_evidence",
            "except_type",
        ],
        "error_micro_tags": {
            "execution_error": [
                "grammar_rule_slip",
                "punctuation_error",
                "word_form_error",
            ],
            "conceptual_gap": [
                "misidentified_tone",
                "missed_main_idea",
                "inference_too_broad",
                "author_bias_missed",
                "grammar_rule_wrong",
            ],
            "needs_refinement": [
                "evidence_not_cited",
                "vague_response",
            ],
        },
    },

    "History": {
        "skill_tags": [
            "chronological_reasoning",
            "cause_effect_analysis",
            "source_evaluation",
            "comparison_analysis",
            "geographic_reasoning",
        ],
        "style_tags": [
            "primary_source_based",
            "map_analysis",
            "timeline_ordering",
            "perspective_analysis",
        ],
        "error_micro_tags": {
            "execution_error": [
                "date_period_wrong",
                "figure_confused",
                "location_wrong",
            ],
            "conceptual_gap": [
                "causation_correlation_confused",
                "oversimplification",
                "anachronism",
                "perspective_bias",
            ],
            "needs_refinement": [
                "vague_causation",
                "incomplete_context",
            ],
        },
    },

    "Computer Science": {
        "skill_tags": [
            "algorithm_tracing",
            "code_debugging",
            "complexity_analysis",
            "data_structure_selection",
            "recursion_reasoning",
            "logic_reasoning",
        ],
        "style_tags": [
            "code_snippet_based",
            "trace_execution",
            "design_question",
            "pseudocode_based",
        ],
        "error_micro_tags": {
            "execution_error": [
                "off_by_one_error",
                "variable_scope_error",
                "operator_precedence_wrong",
                "syntax_confusion",
            ],
            "conceptual_gap": [
                "wrong_data_structure",
                "complexity_wrong",
                "recursion_base_case_missing",
                "algorithm_logic_wrong",
            ],
            "needs_refinement": [
                "inefficient_solution",
                "edge_case_missed",
                "incomplete_implementation",
            ],
        },
    },
}

# ---------------------------------------------------------------------------
# Grade-level tag exclusions
# Tags in these sets are excluded for students at or below the grade band.
# ---------------------------------------------------------------------------

GRADE_TAG_EXCLUSIONS = {
    "K-3": {
        "skill_tags": {"proof_construction", "algebraic_manipulation", "olympiad"},
        "error_micro_tags": {"scope_violation", "inverse_direction", "wrong_formula",
                             "setup_error", "condition_ignored"},
    },
    "4-6": {
        "skill_tags": {"proof_construction", "olympiad"},
        "error_micro_tags": {"scope_violation", "inverse_direction"},
    },
    "7-9": {
        "skill_tags": {"proof_construction"},
        "error_micro_tags": set(),
    },
    "10-12": {
        "skill_tags": set(),
        "error_micro_tags": set(),
    },
}


def _grade_band(grade_label: str) -> str:
    """Map a grade label string to a grade band key."""
    g = (grade_label or "").lower()
    if any(x in g for x in ("kindergarten", "1st", "2nd", "3rd", "grade 1", "grade 2", "grade 3")):
        return "K-3"
    if any(x in g for x in ("4th", "5th", "6th", "grade 4", "grade 5", "grade 6")):
        return "4-6"
    if any(x in g for x in ("7th", "8th", "9th", "grade 7", "grade 8", "grade 9")):
        return "7-9"
    return "10-12"


def _normalize_subject(subject: str) -> str:
    """Map raw subject string to a SUBJECT_TAGS key."""
    s = (subject or "").lower().strip()
    mapping = {
        "math": "Math", "mathematics": "Math",
        "physics": "Physics",
        "chemistry": "Chemistry",
        "biology": "Biology",
        "english": "English",
        "history": "History", "geography": "History", "social studies": "History",
        "computer science": "Computer Science", "cs": "Computer Science",
    }
    return mapping.get(s, None)


def get_allowed_tags(subject: str, grade_level: str = None, question_type: str = None):
    """
    Return the set of allowed tags for a given subject / grade / question type.

    Returns a dict:
    {
        "skill_tags": [...],
        "style_tags": [...],
        "mc_strategy_tags": [...],   # empty if not MC
        "error_micro_tags": {...},   # keyed by error_type
    }
    """
    norm = _normalize_subject(subject)
    subj_data = SUBJECT_TAGS.get(norm, {})
    band = _grade_band(grade_level or "")
    exclusions = GRADE_TAG_EXCLUSIONS.get(band, {"skill_tags": set(), "error_micro_tags": set()})

    # skill_tags — subject-specific, filtered by grade
    skill_tags = [t for t in subj_data.get("skill_tags", [])
                  if t not in exclusions["skill_tags"]]

    # style_tags — universal + subject-specific
    style_tags = UNIVERSAL_STYLE_TAGS + subj_data.get("style_tags", [])

    # mc_strategy_tags — only for MC
    if question_type == "multiple_choice":
        mc_tags = UNIVERSAL_MC_STRATEGY_TAGS + subj_data.get("mc_strategy_tags_extra", [])
    else:
        mc_tags = []

    # error_micro_tags — subject-specific per error_type + universal, filtered by grade
    error_micro = {}
    subj_micro = subj_data.get("error_micro_tags", {})
    for et in ("execution_error", "conceptual_gap", "needs_refinement"):
        tags_for_type = (subj_micro.get(et, []) + UNIVERSAL_ERROR_MICRO.get(et, []))
        error_micro[et] = [t for t in tags_for_type
                           if t not in exclusions["error_micro_tags"]]

    return {
        "skill_tags": skill_tags,
        "style_tags": style_tags,
        "mc_strategy_tags": mc_tags,
        "error_micro_tags": error_micro,
    }


def get_all_valid_tags(subject: str) -> set:
    """Return flat set of all valid tag strings for a subject (for validation)."""
    allowed = get_allowed_tags(subject)
    all_tags = set(allowed["skill_tags"] + allowed["style_tags"] + allowed["mc_strategy_tags"])
    for tags in allowed["error_micro_tags"].values():
        all_tags.update(tags)
    return all_tags
