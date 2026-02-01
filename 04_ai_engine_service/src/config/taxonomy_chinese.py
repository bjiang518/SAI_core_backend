"""
Hierarchical Taxonomy for Chinese Language Arts (母语/语文)
- 10 base branches (major language arts domains)
- 56 detailed branches (specific topics)

Designed for native Chinese speakers (equivalent to English Language Arts)
Covers both Traditional and Simplified Chinese education systems
"""

CHINESE_BASE_BRANCHES = [
    "Reading Foundations",
    "Modern Chinese Reading",
    "Classical Chinese (文言文)",
    "Poetry & Literature (诗词文学)",
    "Writing - Narrative (记叙文)",
    "Writing - Expository (说明文)",
    "Writing - Argumentative (议论文)",
    "Language Knowledge (语言基础)",
    "Oral Communication (口语交际)",
    "Comprehensive Language Skills"
]

CHINESE_DETAILED_BRANCHES = {
    "Reading Foundations": [
        "Character Recognition (识字)",
        "Pinyin & Pronunciation",
        "Reading Fluency",
        "Vocabulary Development (词汇积累)",
        "Reading Strategies"
    ],
    "Modern Chinese Reading": [
        "Article Comprehension (阅读理解)",
        "Main Idea & Theme (主旨大意)",
        "Text Structure & Organization",
        "Author's Purpose & Perspective",
        "Inference & Analysis (推理分析)",
        "Literary Devices (修辞手法)",
        "Genre Study (体裁学习)"
    ],
    "Classical Chinese (文言文)": [
        "Classical Grammar & Structure",
        "Classical Vocabulary (实词/虚词)",
        "Translation (文言翻译)",
        "Classical Text Analysis",
        "Historical Context",
        "Classical Idioms (成语典故)"
    ],
    "Poetry & Literature (诗词文学)": [
        "Ancient Poetry (古诗词)",
        "Modern Poetry (现代诗歌)",
        "Famous Works (名著阅读)",
        "Literary Appreciation (文学鉴赏)",
        "Poetry Techniques (诗歌技巧)",
        "Cultural Background (文化背景)"
    ],
    "Writing - Narrative (记叙文)": [
        "Story Elements (记叙要素)",
        "Character & Setting Description",
        "Plot Development (情节发展)",
        "Descriptive Techniques (描写手法)",
        "Personal Narrative (记事作文)"
    ],
    "Writing - Expository (说明文)": [
        "Expository Methods (说明方法)",
        "Structure & Organization (结构安排)",
        "Informative Writing (说明性文章)",
        "Process Explanation (事理说明)"
    ],
    "Writing - Argumentative (议论文)": [
        "Thesis & Argument (论点论据)",
        "Argumentation Methods (论证方法)",
        "Persuasive Techniques (说服技巧)",
        "Logical Reasoning (逻辑推理)",
        "Counterargument (驳论)"
    ],
    "Language Knowledge (语言基础)": [
        "Grammar & Syntax (语法句法)",
        "Parts of Speech (词性)",
        "Sentence Patterns (句式)",
        "Punctuation (标点符号)",
        "Common Errors (病句修改)",
        "Idioms & Proverbs (成语俗语)",
        "Rhetorical Devices (修辞方法)"
    ],
    "Oral Communication (口语交际)": [
        "Speaking Skills (口语表达)",
        "Listening Comprehension (听力理解)",
        "Presentation & Speech (演讲)",
        "Discussion & Debate (讨论辩论)",
        "Interview & Dialogue (访谈对话)"
    ],
    "Comprehensive Language Skills": [
        "Integrated Reading & Writing",
        "Material Synthesis (材料整合)",
        "Critical Thinking (批判性思维)",
        "Cultural Literacy (文化素养)",
        "Language Application (语言运用)"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return CHINESE_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in CHINESE_DETAILED_BRANCHES.get(base_branch, [])
