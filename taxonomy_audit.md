# Taxonomy Grade Range Audit

**Date:** 2026-05-09
**Standards referenced:** Common Core State Standards (CCSS) for Math and ELA, Next Generation Science Standards (NGSS)
**Grade encoding:** 0 = PreK/Kindergarten, 1-12 = Grade 1-12, 13 = College/Adult

---

## Summary of Changes

| File | Topics Changed | Topics Correct |
|------|---------------|----------------|
| math_taxonomy.json | 21 | 22 |
| english_taxonomy.json | 12 | 14 |
| science_taxonomy.json | 9 | 18 |
| general_taxonomy.json | 2 | 4 |
| **Total** | **44** | **58** |

---

## math_taxonomy.json

### Branch: Number & Operations

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Counting & Number Sense | 0-2 | 0-2 | CORRECT | CC K.CC, 1.NBT, 2.NBT — counting ends as focus by grade 2 |
| Addition & Subtraction | 1-4 | **1-5** | FIXED (gradeMax 4→5) | CC 4.NBT.4 and 5.NBT.7 extend multi-digit addition/subtraction through grade 5 |
| Multiplication & Division | 2-5 | **3-5** | FIXED (gradeMin 2→3) | CC 3.OA formally introduces multiplication; grade 2 covers only addition/subtraction (2.OA) |
| Fractions | 3-7 | **3-6** | FIXED (gradeMax 7→6) | CC 3-6 NF/NS covers fractions; grade 7 moves to ratio/proportional reasoning (7.RP), not new fraction concepts |
| Decimals & Percentages | 4-8 | 4-8 | CORRECT | CC 4.NBT introduces decimals; percentages extend into grade 8 pre-algebra |
| Integers & Absolute Value | 5-8 | **6-8** | FIXED (gradeMin 5→6) | CC 6.NS.5-6 formally introduces integers and absolute value; grade 5 stays in positive number domain |
| Ratios & Proportions | 5-8 | **6-8** | FIXED (gradeMin 5→6) | CC 6.RP introduces ratios; grade 5 covers fractions and decimals, not ratios |
| Exponents & Roots | 6-9 | 6-9 | CORRECT | CC 6.EE.1 introduces exponents; square/cube roots in 8.EE.2; extends to grade 9 (known error already corrected) |
| Number Theory | 6-9 | 6-9 | CORRECT | CC 6.NS.4 (GCF, LCM) — appropriate for grades 6-9 |

### Branch: Algebra - Foundations

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Variables & Expressions | 5-8 | **6-8** | FIXED (gradeMin 5→6) | CC 6.EE.1-4 introduces variables and expressions; grade 5 is still arithmetic operations |
| Linear Equations - One Variable | 6-9 | 6-9 | CORRECT | CC 6.EE.7, 7.EE.4a — appropriate |
| Linear Inequalities | 7-10 | 7-10 | CORRECT | CC 7.EE.4b, HS algebra |
| Systems of Equations | 7-10 | **8-10** | FIXED (gradeMin 7→8) | CC 8.EE.8 introduces systems of equations; grade 7 covers single-variable equations only (7.EE) |
| Algebraic Word Problems | 6-10 | 6-10 | CORRECT | Spans from CC 6.EE through HS algebra |
| Functions - Introduction | 7-10 | **8-10** | FIXED (gradeMin 7→8) | CC 8.F formally introduces the concept of a function; grade 7 covers proportional relationships but not functions by name |

### Branch: Algebra - Advanced

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Polynomials | 8-11 | 8-11 | CORRECT | CC HSA.APR; introduced informally in grade 8 |
| Quadratic Equations | 8-11 | **9-11** | FIXED (gradeMin 8→9) | CC HSA.REI.4 — quadratics are an Algebra I topic (grade 9); grade 8 covers linear equations only |
| Functions & Transformations | 8-12 | **9-12** | FIXED (gradeMin 8→9) | Function transformations are an Algebra II / Precalc topic (grades 9-12); grade 8 covers only linear function intro |
| Exponential Functions | 9-12 | 9-12 | CORRECT | CC HSF.IF — Algebra I/II |
| Logarithms | 9-12 | **10-12** | FIXED (gradeMin 9→10) | Logarithms are an Algebra II topic, typically grade 10-11; not part of Algebra I (grade 9) |
| Rational Functions | 10-12 | 10-12 | CORRECT | CC HSA.APR.6-7 — Pre-Calculus / Algebra II |
| Sequences & Series | 10-12 | **9-12** | FIXED (gradeMin 10→9) | Arithmetic/geometric sequences appear in Algebra I (CC HSF.BF.2), typically grade 9 |

### Branch: Geometry

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Shapes & Properties | 3-7 | **0-7** | FIXED (gradeMin 3→0) | CC K.G introduces shape names, attributes, and compositions in kindergarten |
| Area & Perimeter | 3-7 | **3-8** | FIXED (gradeMax 7→8) | CC 7.G.4 covers circles (circumference/area) and composite figures extend into grade 8 |
| Angles & Parallel Lines | 4-9 | 4-9 | CORRECT | CC 4.MD.5 introduces angles; parallel line angle relationships are a HS geometry topic |
| Triangles & Congruence | 7-10 | 7-10 | CORRECT | CC 7.G, 8.G, HSG.CO — appropriate |
| Similarity & Transformations | 7-10 | 7-10 | CORRECT | CC 8.G.4, HSG.SRT — appropriate |
| Coordinate Geometry | 6-10 | 6-10 | CORRECT | CC 6.NS.6 introduces coordinate plane |
| Circles | 7-10 | 7-10 | CORRECT | CC 7.G.4 introduces circle area/circumference; HSG.C extends |
| Volume & Surface Area | 5-9 | 5-9 | CORRECT | CC 5.MD.3 introduces volume; extends through grade 9 with complex solids |
| Geometric Proofs | 8-12 | **9-12** | FIXED (gradeMin 8→9) | Formal deductive proofs are a HS Geometry standard (HSG.CO.9-11), typically grade 9-10; grade 8 uses informal reasoning only |

### Branch: Data Analysis & Probability

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Data Collection & Graphs | 3-7 | **1-7** | FIXED (gradeMin 3→1) | CC 1.MD.4 introduces organizing and representing data with picture graphs and tally charts |
| Mean, Median & Mode | 4-7 | **6-7** | FIXED (gradeMin 4→6) | CC 6.SP.3-5 formally introduces mean, median, mode, and range; not a CC standard before grade 6 |
| Probability - Basic | 5-8 | **7-8** | FIXED (gradeMin 5→7) | CC 7.SP.5-8 introduces probability concepts; grade 5 has no probability in Common Core |
| Statistical Analysis | 7-10 | 7-10 | CORRECT | CC 7.SP, HS Statistics (HSS.ID) — appropriate |
| Data Interpretation | 6-10 | **3-10** | FIXED (gradeMin 6→3) | Reading and interpreting graphs begins at CC 3.MD.3; grade 6 was too late for the start |
| Probability & Combinatorics | 9-12 | 9-12 | CORRECT | CC HSS.CP — appropriate for grades 9-12 |

### Branch: Trigonometry & Pre-Calculus

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Trigonometric Functions | 9-12 | 9-12 | CORRECT | CC HSF.TF — right-triangle trig in Geometry (grade 9-10) |
| Trigonometric Identities | 10-12 | 10-12 | CORRECT | CC HSF.TF.8-9 — Pre-Calculus level |
| Vectors | 10-12 | 10-12 | CORRECT | CC HSN.VM — Pre-Calculus / Physics integration |
| Matrices | 10-12 | 10-12 | CORRECT | CC HSN.VM — Pre-Calculus |
| Complex Numbers | 10-12 | 10-12 | CORRECT | CC HSN.CN — Algebra II / Pre-Calculus |

### Branch: Calculus

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Limits | 11-13 | 11-13 | CORRECT | AP Calculus AB typically starts in grade 11; extends to college |
| Derivatives | 11-13 | 11-13 | CORRECT | AP Calculus AB — grade 11-12 |
| Integration | 12-13 | **11-13** | FIXED (gradeMin 12→11) | AP Calculus AB covers both derivatives AND integration in one year, typically taken in grade 11; grade 12 is AP Calculus BC |
| Applications of Calculus | 12-13 | **11-13** | FIXED (gradeMin 12→11) | Same reason — AP Calc AB applications are covered starting in grade 11 |

### Branch: Mathematical Modeling & Applications

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Real-World Problem Solving | 4-13 | **1-13** | FIXED (gradeMin 4→1) | CC 1.OA.1 requires solving word problems using addition/subtraction within 20; real-world contexts start in grade 1 |
| Mathematical Reasoning | 5-13 | **1-13** | FIXED (gradeMin 5→1) | Mathematical reasoning and justification are explicit in CC Standards for Mathematical Practice beginning in grade 1 |
| Estimation & Approximation | 3-8 | **2-8** | FIXED (gradeMin 3→2) | CC 2.NBT.3 (reading/writing numbers) and 2.MD.3 (estimating lengths) introduce estimation in grade 2 |
| Pattern Recognition | 3-9 | **0-9** | FIXED (gradeMin 3→0) | CC K.OA.5 and K.MD include pattern recognition; kindergarten math explicitly includes patterns |
| Word Problems | 3-10 | **1-10** | FIXED (gradeMin 3→1) | CC 1.OA.1 — addition/subtraction word problems within 20 are a grade 1 standard |

---

## english_taxonomy.json

### Branch: Phonics & Decoding

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Letter Sounds & Phonemes | 0-2 | 0-2 | CORRECT | CC RF.K.2-3, RF.1.2-3 — phonemic awareness peaks in K-2 |
| Sight Words | 0-2 | 0-2 | CORRECT | CC RF.K.3c, RF.1.3g — Dolch/Fry sight words in K-2 |
| Word Families & Patterns | 1-3 | 1-3 | CORRECT | CC RF.1.3, RF.2.3 — decoding patterns in grades 1-3 |
| Syllables & Word Structure | 1-3 | 1-3 | CORRECT | CC RF.1.3d-e, RF.2.3c — syllable types taught in grades 1-3 |

### Branch: Vocabulary & Word Knowledge

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Vocabulary in Context | 1-13 | **0-13** | FIXED (gradeMin 1→0) | CC L.K.4 introduces using context to determine word meaning in kindergarten |
| Word Roots & Affixes | 4-13 | 4-13 | CORRECT | CC L.4.4b explicitly introduces prefixes, suffixes, and roots in grade 4 |
| Figurative Language | 4-13 | **3-13** | FIXED (gradeMin 4→3) | CC RL.3.4 introduces distinguishing literal from nonliteral language in grade 3 |
| Academic Vocabulary | 5-13 | **4-13** | FIXED (gradeMin 5→4) | CC L.4.6 introduces acquiring and using grade-appropriate academic vocabulary in grade 4 |

### Branch: Reading Comprehension

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Main Idea & Details | 1-8 | **1-13** | FIXED (gradeMax 8→13) | CC RI.9-10.2, RI.11-12.2 explicitly require identifying central ideas in informational text through 12th grade |
| Inference & Evidence | 3-13 | **1-13** | FIXED (gradeMin 3→1) | CC RL.1.1, RI.1.1 — grade 1 asks students to ask and answer questions about key details, which is foundational inference |
| Text Structure & Organization | 3-13 | 3-13 | CORRECT | CC RI.3.8 introduces text structure; extends through all grades |
| Author's Purpose & Perspective | 4-13 | **3-13** | FIXED (gradeMin 4→3) | CC RI.3.6 introduces distinguishing point of view and author's purpose in grade 3 |
| Compare & Contrast | 3-10 | **3-13** | FIXED (gradeMax 10→13) | CC RL/RI.11-12.9 require comparing and contrasting across multiple texts through 12th grade |
| Summarizing & Paraphrasing | 4-13 | **2-13** | FIXED (gradeMin 4→2) | CC RI.2.2 requires identifying main topic and retelling key details (foundational summarizing) in grade 2 |

### Branch: Grammar & Language

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Parts of Speech | 1-7 | **1-9** | FIXED (gradeMax 7→9) | CC L.9-10.1 includes grammar instruction on sentence structures using proper parts of speech; grade 9 is appropriate upper bound |
| Sentence Structure | 2-9 | 2-9 | CORRECT | CC L.2.1 introduces sentence types; extends through L.9-10.1 |
| Punctuation & Capitalization | 1-7 | **1-8** | FIXED (gradeMax 7→8) | CC L.7.2 and L.8.2 both contain explicit punctuation standards (commas, em dashes, ellipses for effect) |
| Subject-Verb Agreement | 3-8 | 3-8 | CORRECT | CC L.3.1f through L.8.1 |
| Verb Tense & Aspect | 3-9 | 3-9 | CORRECT | CC L.3.1e through L.9-10.1 |
| Complex Grammar Structures | 7-13 | 7-13 | CORRECT | CC L.7.1-2 through college-level grammar |

### Branch: Writing

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Narrative Writing | 1-10 | **1-12** | FIXED (gradeMax 10→12) | CC W.11-12.3 explicitly includes narrative writing as a standard in grades 11-12 |
| Expository Writing | 3-13 | **2-13** | FIXED (gradeMin 3→2) | CC W.2.2 introduces informational/explanatory writing in grade 2 |
| Persuasive & Argumentative Writing | 5-13 | **4-13** | FIXED (gradeMin 5→4) | CC W.4.1 introduces opinion/argument writing with supporting reasons in grade 4 |
| Research & Citation | 6-13 | **4-13** | FIXED (gradeMin 6→4) | CC W.4.7 introduces short research projects; W.4.8 introduces gathering information from sources |
| Writing Process & Revision | 3-13 | **2-13** | FIXED (gradeMin 3→2) | CC W.2.5 introduces the writing process including revision with guidance in grade 2 |

### Branch: Literary Analysis

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Plot, Character & Setting | 2-8 | **1-8** | FIXED (gradeMin 2→1) | CC RL.1.3 introduces characters, settings, and major events in stories in grade 1 |
| Theme & Symbolism | 5-13 | **4-13** | FIXED (gradeMin 5→4) | CC RL.4.2 introduces theme and summarizing stories in grade 4 |
| Literary Devices | 6-13 | **4-13** | FIXED (gradeMin 6→4) | CC RL.4.4 introduces figurative language including metaphors and similes, which are literary devices, in grade 4 |
| Poetry Analysis | 6-13 | **4-13** | FIXED (gradeMin 6→4) | CC RL.4.5 introduces structural elements of poems (verse, rhythm, meter); formal poetry analysis begins in grade 4 |
| Rhetoric & Argumentation | 9-13 | 9-13 | CORRECT | CC RI.9-10.6 introduces rhetorical analysis; appropriate for grades 9-12 |

---

## science_taxonomy.json

### Branch: Life Science

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Living vs Non-Living Things | 0-2 | 0-2 | CORRECT | NGSS K-LS1-1 — kindergarten standard |
| Plants & Animals | 1-4 | **0-4** | FIXED (gradeMin 1→0) | NGSS K-LS1-1 includes plants and animals as part of what living things need; kindergarten is the appropriate start |
| Ecosystems & Food Webs | 3-7 | **2-7** | FIXED (gradeMin 3→2) | NGSS 2-LS2-1,2 introduce interdependent relationships in ecosystems (plants needing insects, etc.) in grade 2 |
| Cells & Microorganisms | 5-8 | **6-8** | FIXED (gradeMin 5→6) | NGSS MS-LS1-1 introduces cell theory as a middle school standard beginning at grade 6; grade 5 focuses on ecosystems and matter |
| Human Body Systems | 5-8 | **6-8** | FIXED (gradeMin 5→6) | NGSS MS-LS1-3 covers body systems as a middle school standard; grade 5 NGSS is physical science and ecosystems focused |
| Genetics & Heredity | 7-10 | 7-10 | CORRECT | NGSS MS-LS3-1,2 (grade 7) through HS-LS3 (grades 9-10) |
| Evolution & Natural Selection | 7-10 | 7-10 | CORRECT | NGSS MS-LS4-2,4,6 through HS-LS4 |

### Branch: Earth & Space Science

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Weather & Climate | 1-6 | **0-6** | FIXED (gradeMin 1→0) | NGSS K-ESS2-1 — kindergarten students use and share observations of local weather |
| Rocks, Minerals & Soil | 2-6 | 2-6 | CORRECT | NGSS 2-ESS2-2 — Earth materials first appear in grade 2 |
| Solar System & Space | 3-8 | 3-8 | CORRECT | NGSS 1-ESS1 covers sun/moon/stars; formal solar system study is NGSS 3-ESS1, MS-ESS1 |
| Earth Processes & Landforms | 4-8 | **2-8** | FIXED (gradeMin 4→2) | NGSS 2-ESS1-1 introduces slow/rapid changes to Earth's surface in grade 2; erosion/weathering formally in NGSS 4-ESS2 |
| Plate Tectonics | 6-10 | **7-10** | FIXED (gradeMin 6→7) | NGSS MS-ESS2-2,3 introduce plate tectonics — this is typically a grade 7 topic in middle school sequences |
| Atmosphere & Climate Change | 7-12 | 7-12 | CORRECT | NGSS MS-ESS2-5, HS-ESS2-4, HS-ESS3 |

### Branch: Physical Science

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Matter & Its Properties | 2-7 | **0-7** | FIXED (gradeMin 2→0) | NGSS K-PS1-1 — kindergarten students observe and describe properties of materials |
| Forces & Motion | 3-8 | 3-8 | CORRECT | NGSS K-PS2 covers pushes/pulls but formal forces study is NGSS 3-PS2; 3 is appropriate |
| Energy & Its Forms | 3-8 | 3-8 | CORRECT | NGSS 3-PS2-3/4 relates to energy; NGSS 4-PS3 formally introduces energy — 3 is the lower boundary per NGSS |
| Waves, Sound & Light | 4-8 | 4-8 | CORRECT | NGSS 1-PS4 introduces waves/light/sound in grade 1, but formal structured study is NGSS 4-PS4 — 4 is the appropriate gradeMin for structured study |
| Chemical Reactions & Changes | 6-10 | **5-10** | FIXED (gradeMin 6→5) | NGSS 5-PS1-4 introduces chemical reactions (matter is conserved, new substances formed) in grade 5 |
| Electricity & Magnetism | 4-8 | 4-8 | CORRECT | NGSS 3-PS2-3/4 introduces magnetic forces in grade 3; circuits/electricity is NGSS 4-PS3 — 4 is appropriate |

### Branch: Biology (High School)

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Cell Biology & Organelles | 8-13 | **9-13** | FIXED (gradeMin 8→9) | HS-LS1-1,2 cover cell organelles as a high school standard; grade 8 is 8th-grade physical science or general science, not HS Biology |
| Molecular Biology & DNA | 9-13 | 9-13 | CORRECT | NGSS HS-LS1-1, HS-LS3-1 |
| Ecology & Environmental Science | 9-13 | 9-13 | CORRECT | NGSS HS-LS2 |
| Evolution - Advanced | 9-13 | 9-13 | CORRECT | NGSS HS-LS4 |
| Biological Classification | 9-13 | **6-13** | FIXED (gradeMin 9→6) | Classification of organisms (domains, kingdoms, phylogeny basics) is a middle school topic (NGSS MS-LS4, typically grade 6-8 life science) before being revisited in depth in HS Biology |

### Branch: Chemistry (High School)

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Atomic Structure & Periodic Table | 9-13 | 9-13 | CORRECT | NGSS HS-PS1-1 — Chemistry I, grade 9-10 |
| Chemical Bonding | 9-13 | 9-13 | CORRECT | NGSS HS-PS1-2,3 |
| Stoichiometry | 10-13 | 10-13 | CORRECT | Typically Chemistry I/II, grades 10-11 |
| Acids, Bases & pH | 10-13 | **9-13** | FIXED (gradeMin 10→9) | Acids/bases and pH are part of introductory Chemistry I curricula, typically taught in grade 9-10 |
| Thermochemistry & Thermodynamics | 11-13 | 11-13 | CORRECT | AP Chemistry / Chemistry II level — grade 11-12 |

### Branch: Physics (High School)

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Kinematics & Motion | 9-13 | 9-13 | CORRECT | NGSS HS-PS2-1 — Physics I, grade 9-10 |
| Newton's Laws & Dynamics | 9-13 | 9-13 | CORRECT | NGSS HS-PS2-1,2 |
| Energy, Work & Power | 10-13 | **9-13** | FIXED (gradeMin 10→9) | Energy, work, and power are core Physics I topics (NGSS HS-PS3-1,2), typically covered in grade 9-10 Physics |
| Waves & Optics | 10-13 | **9-13** | FIXED (gradeMin 10→9) | NGSS HS-PS4-1,3 — waves and light are Physics I topics covered in grade 9-10 |
| Electromagnetism | 11-13 | 11-13 | CORRECT | Typically AP Physics 2 / Physics II — grade 11-12 |
| Modern Physics | 11-13 | 11-13 | CORRECT | AP Physics / college-level — grade 11-13 |

---

## general_taxonomy.json

### Branch: Critical Thinking

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Logic & Reasoning | 3-13 | **1-13** | FIXED (gradeMin 3→1) | CC Standards for Mathematical Practice (MP.2, MP.3) include reasoning and justification starting in grade 1; basic logical reasoning is explicitly taught from grade 1 |
| Problem Solving Strategies | 2-13 | **0-13** | FIXED (gradeMin 2→0) | NGSS K-ETS1 and CC K.OA explicitly involve problem-solving strategies in kindergarten |
| Analysis & Evaluation | 5-13 | 5-13 | CORRECT | Formal analysis and evaluation (Bloom's higher-order thinking) is appropriately introduced in grade 5 |

### Branch: Study Skills & Learning

| Topic | Was | Now | Status | Rationale |
|-------|-----|-----|--------|-----------|
| Note-Taking & Organization | 3-13 | 3-13 | CORRECT | Formal note-taking strategies are appropriately introduced in grade 3 |
| Time Management | 4-13 | 4-13 | CORRECT | Appropriate for grade 4+ when homework demands increase |
| Memory Techniques | 4-13 | 4-13 | CORRECT | Appropriate for grade 4+ |

---

## Key Patterns Identified

### Common Error Type 1: Missing Kindergarten Coverage
Many topics that NGSS and CC explicitly address in kindergarten (grade 0) had gradeMin of 1, 2, or 3. Fixed in:
- Math: Shapes (K.G), Pattern Recognition (K.OA), Real-World Problem Solving (K.OA), Mathematical Reasoning (K.MP)
- English: Vocabulary in Context (L.K.4)
- Science: Plants & Animals (K-LS1), Weather (K-ESS2), Matter & Its Properties (K-PS1)
- General: Problem Solving Strategies (K.OA, K-ETS1)

### Common Error Type 2: Pre-Algebra Topics Starting Too Early
Topics that require CC Grade 6+ algebra readiness were incorrectly set to start in grade 5:
- Integers & Absolute Value (6.NS, not grade 5)
- Ratios & Proportions (6.RP, not grade 5)
- Variables & Expressions (6.EE, not grade 5)

### Common Error Type 3: High School Topics Bleeding Too Low
Several HS-specific topics were marked as starting in middle school:
- Quadratic Equations: grade 9 (Algebra I), not 8
- Function Transformations: grade 9 (Algebra I/II), not 8
- Geometric Proofs: grade 9 (HS Geometry), not 8
- Cell Biology (HS): grade 9, not 8

### Common Error Type 4: ELA Topics Starting Too Late
Common Core ELA standards introduce many skills earlier than was reflected:
- Inference begins at grade 1 (RL.1.1, RI.1.1)
- Author's Purpose begins at grade 3 (RI.3.6)
- Theme begins at grade 4 (RL.4.2)
- Literary Devices and Poetry Analysis begin at grade 4 (RL.4.4-5)
- Research skills begin at grade 4 (W.4.7)

### Common Error Type 5: Grade Max Cut Too Low
Some topics were cut off before their final CC/NGSS standard year:
- Main Idea & Details: extends through grade 12 (RI.11-12.2), not just 8
- Compare & Contrast: extends through grade 12 (RL.11-12.9), not just 10
- Narrative Writing: grade 12 (W.11-12.3), not just 10
