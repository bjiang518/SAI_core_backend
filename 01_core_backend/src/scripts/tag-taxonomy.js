/**
 * tag-taxonomy.js — Node.js mirror of 04_ai_engine_service/src/config/tag_taxonomy.py
 *
 * Canonical predefined tag sets for all subjects.
 * Used by question-bank-service.js for tag-boosted retrieval.
 */

'use strict';

const UNIVERSAL_STYLE_TAGS = [
  'multi_step', 'single_step', 'real_world_applied', 'data_interpretation', 'graphical',
];

const UNIVERSAL_MC_STRATEGY_TAGS = [
  'distractor_trap', 'elimination_method', 'backsolve', 'estimate_to_eliminate', 'ordering_comparison',
];

const SUBJECT_TAGS = {
  Math: {
    skill_tags: [
      'quick_computation', 'algebraic_manipulation', 'pattern_recognition',
      'logical_deduction', 'formula_recall_apply', 'spatial_reasoning',
      'number_sense', 'word_problem_modeling', 'estimation', 'proof_construction',
    ],
    style_tags: ['olympiad', 'computation_heavy', 'proof_based', 'visual_model'],
    mc_strategy_tags_extra: [],
  },
  Physics: {
    skill_tags: [
      'vector_analysis', 'diagram_analysis', 'unit_analysis',
      'formula_chaining', 'conceptual_reasoning', 'graph_interpretation',
    ],
    style_tags: ['lab_experimental', 'calculation_heavy', 'conceptual_qualitative'],
    mc_strategy_tags_extra: [],
  },
  Chemistry: {
    skill_tags: [
      'stoichiometry_calc', 'formula_writing', 'balancing_equations',
      'periodic_trends_reasoning', 'lab_data_interpretation',
    ],
    style_tags: ['calculation_heavy', 'equation_based', 'concept_check'],
    mc_strategy_tags_extra: [],
  },
  Biology: {
    skill_tags: [
      'diagram_interpretation', 'process_sequencing', 'definition_recall',
      'data_analysis', 'cause_effect_reasoning',
    ],
    style_tags: ['diagram_based', 'case_study', 'classification_type'],
    mc_strategy_tags_extra: [],
  },
  English: {
    skill_tags: [
      'inference', 'author_intent_analysis', 'grammar_application',
      'vocabulary_context', 'text_evidence_citation', 'argument_evaluation', 'tone_identification',
    ],
    style_tags: ['passage_based', 'grammar_drill', 'vocabulary_in_context', 'writing_analysis'],
    mc_strategy_tags_extra: ['closest_meaning', 'best_evidence', 'except_type'],
  },
  History: {
    skill_tags: [
      'chronological_reasoning', 'cause_effect_analysis', 'source_evaluation',
      'comparison_analysis', 'geographic_reasoning',
    ],
    style_tags: ['primary_source_based', 'map_analysis', 'timeline_ordering', 'perspective_analysis'],
    mc_strategy_tags_extra: [],
  },
  'Computer Science': {
    skill_tags: [
      'algorithm_tracing', 'code_debugging', 'complexity_analysis',
      'data_structure_selection', 'recursion_reasoning', 'logic_reasoning',
    ],
    style_tags: ['code_snippet_based', 'trace_execution', 'design_question', 'pseudocode_based'],
    mc_strategy_tags_extra: [],
  },
};

// All valid skill_tags + style_tags for a given subject (for tag-boost validation)
function getAllowedSkillAndStyleTags(subject) {
  const norm = normalizeSubject(subject);
  const data = SUBJECT_TAGS[norm] || {};
  return {
    skill_tags: new Set(data.skill_tags || []),
    style_tags: new Set([...UNIVERSAL_STYLE_TAGS, ...(data.style_tags || [])]),
    mc_strategy_tags: new Set([
      ...UNIVERSAL_MC_STRATEGY_TAGS,
      ...(data.mc_strategy_tags_extra || []),
    ]),
  };
}

const SUBJECT_NORMALIZE = {
  mathematics: 'Math', math: 'Math',
  physics: 'Physics',
  chemistry: 'Chemistry',
  biology: 'Biology',
  english: 'English',
  history: 'History', geography: 'History',
  'computer science': 'Computer Science', cs: 'Computer Science',
};

function normalizeSubject(subject) {
  return SUBJECT_NORMALIZE[(subject || '').toLowerCase()] || subject;
}

/**
 * Compute a tag-match score (0.0–1.0) between a bank question's tags
 * and the student's tag weakness context.
 * A positive return value means "boost this question".
 * A negative value (from styleDeBoost) means "de-boost this question".
 *
 * @param {object} rowTags  - {skill_tags:[], style_tags:[], mc_strategy_tags:[]} from DB
 * @param {object} ctx      - {skill_weakness:[], error_micro_weakness:[], style_weakness:[]}
 * @returns {number} typically 0.0–1.0, may be negative for strong style mismatch
 */
function tagMatchScore(rowTags, ctx) {
  if (!rowTags || !ctx) return 0;

  const rowSkill  = new Set(rowTags.skill_tags || []);
  const rowStyle  = new Set(rowTags.style_tags || []);
  const ctxSkill  = ctx.skill_weakness || [];
  const ctxMicro  = ctx.error_micro_weakness || [];
  const ctxStyle  = ctx.style_weakness || [];

  // Skill overlap — skill_weakness tags that appear in the question
  const skillOverlap = ctxSkill.filter(t => rowSkill.has(t)).length;
  const skillScore   = ctxSkill.length > 0 ? skillOverlap / ctxSkill.length : 0;

  // Micro-error → skill mapping for indirect matching
  // e.g. "sign_error" → questions needing "algebraic_manipulation" or "quick_computation"
  const MICRO_TO_SKILL = {
    sign_error:              new Set(['algebraic_manipulation', 'quick_computation']),
    arithmetic_slip:         new Set(['quick_computation']),
    algebraic_slip:          new Set(['algebraic_manipulation']),
    wrong_formula:           new Set(['formula_recall_apply']),
    setup_error:             new Set(['word_problem_modeling', 'logical_deduction']),
    vector_direction_wrong:  new Set(['vector_analysis']),
    unit_conversion_error:   new Set(['unit_analysis']),
    process_direction_wrong: new Set(['process_sequencing']),
    terminology_confused:    new Set(['definition_recall']),
    wrong_law_applied:       new Set(['formula_chaining', 'conceptual_reasoning']),
  };

  let microScore = 0;
  if (ctxMicro.length > 0) {
    let hits = 0;
    for (const micro of ctxMicro) {
      const relatedSkills = MICRO_TO_SKILL[micro];
      if (relatedSkills) {
        for (const s of relatedSkills) {
          if (rowSkill.has(s)) { hits++; break; }
        }
      }
    }
    microScore = hits / ctxMicro.length;
  }

  // Style de-boost — if the student struggles with this style (e.g. "olympiad"),
  // lower this question's score so easier-style questions rank higher.
  // Cap at -0.08 so it never completely removes a question from results.
  const styleHits   = ctxStyle.filter(t => rowStyle.has(t)).length;
  const styleDeBoost = styleHits > 0 ? -0.08 : 0;

  return Math.max(skillScore, microScore) + styleDeBoost;
}

module.exports = { getAllowedSkillAndStyleTags, tagMatchScore, normalizeSubject, SUBJECT_TAGS };
