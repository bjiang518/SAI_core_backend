# Subject-Specific Parsing Analysis & Prompt Design

**目标**: 为13个科目设计专门的解析规则，提升各科作业的解析准确度
**原则**: 不同科目题型不同 → 需要不同的parsing指令
**状态**: 📊 调研中

---

## 📚 iOS App 支持的科目列表

根据 `UserProfile.swift` (Line 334-352)，系统支持以下13个科目：

| # | 科目英文 | 科目中文 | 代码标识 |
|---|---------|---------|---------|
| 1 | **Math** | 数学 | `math` |
| 2 | **Science** | 科学（综合） | `science` |
| 3 | **English** | 英语 | `english` |
| 4 | **History** | 历史 | `history` |
| 5 | **Geography** | 地理 | `geography` |
| 6 | **Physics** | 物理 | `physics` |
| 7 | **Chemistry** | 化学 | `chemistry` |
| 8 | **Biology** | 生物 | `biology` |
| 9 | **Computer Science** | 计算机科学 | `computerScience` |
| 10 | **Foreign Language** | 外语 | `foreignLanguage` |
| 11 | **Art** | 艺术 | `art` |
| 12 | **Music** | 音乐 | `music` |
| 13 | **Physical Education** | 体育 | `physicalEducation` |

---

## 🎯 科目分类与特点分析

### 分类方法

根据题型特点和答案类型，将13个科目分为5大类：

#### Category A: **STEM 计算类**（需要精确数值和公式）
- Math（数学）
- Physics（物理）
- Chemistry（化学）

#### Category B: **STEM 概念类**（需要理解图表和术语）
- Science（综合科学）
- Biology（生物）
- Computer Science（计算机科学）

#### Category C: **语言文字类**（需要处理长文本和语法）
- English（英语）
- Foreign Language（外语）

#### Category D: **社会科学类**（需要理解时间线和地图）
- History（历史）
- Geography（地理）

#### Category E: **创意表达类**（需要处理视觉和创作内容）
- Art（艺术）
- Music（音乐）
- Physical Education（体育）

---

## 📋 各科目详细分析

---

## 1️⃣ Math（数学）

### 科目特点
- 🔢 **数值精度要求高**：答案必须完全准确（65 vs 66 = 错）
- 📐 **图表丰富**：数轴、几何图形、表格、坐标系
- ✏️ **工作步骤重要**：需要提取计算过程，不只是最终答案
- 🧮 **符号多**：+, -, ×, ÷, =, <, >, ≤, ≥, √, ², ³, π, ∞

### 常见题型

#### 1.1 Calculation（计算题）
```
Example:
Q: "25 + 17 = ?"
Student wrote: "42"
→ student_answer: "42"
```

**特殊要求**:
- 提取所有计算步骤：`"25 + 17 = 42"` 而不只是 `"42"`
- 如果学生写了竖式，描述竖式结构

#### 1.2 Word Problems（应用题）
```
Example:
Q: "Sally has 19 stickers. Gia has one more. How many does Gia have?"
Student wrote: "20 stickers"
→ student_answer: "20 stickers"
```

**特殊要求**:
- 保留单位（stickers, dollars, meters）
- 如果学生写了算式，提取算式

#### 1.3 Number Line（数轴）
```
Example:
Q: "Label the number line from 10-19"
Student filled: 10, 11, 12, 13, 14, 15, 16, 17, 18, 19
→ student_answer: "10, 11, 12, 13, 14, 15, 16, 17, 18, 19"
→ question_type: "number_line"
```

**特殊要求**:
- 提取所有填写的数字（按顺序）
- 如果学生标记了某些特殊点，说明

#### 1.4 Geometry（几何）
```
Example:
Q: "Find the area of the rectangle (length=5, width=3)"
Student drew diagram and wrote: "15 square units"
→ student_answer: "15 square units"
→ has_visuals: true
```

**特殊要求**:
- 如果学生画了图，设置 `has_visuals: true`
- 提取图中的标注（长度、角度标记）

#### 1.5 Place Value（位值）
```
Example:
Q: "What number is one more than 64? ___ = ___ tens ___ ones"
Student wrote: "65 = 6 tens 5 ones"
→ question_type: "fill_blank"
→ student_answer: "65 = 6 tens 5 ones"  (完整结构)
```

**特殊要求**:
- **多空填空必须完整提取**（见VISION FIRST原则）
- 保留 "tens" 和 "ones" 结构

#### 1.6 Fractions/Decimals（分数/小数）
```
Example:
Q: "Simplify: 4/8 = ?"
Student wrote: "1/2"
→ student_answer: "1/2"
```

**特殊要求**:
- 识别分数线（/、─）
- 识别小数点（.）

### Math-Specific Parsing Rules

```python
MATH-SPECIFIC RULES:

1. PRESERVE ALL MATHEMATICAL NOTATION:
   ✅ Extract: "x² + 2x + 1 = 0"
   ❌ Don't simplify to: "x squared plus 2x plus 1 equals 0"

2. EXTRACT CALCULATION STEPS:
   IF student shows work:
   → student_answer: "25 + 17 = 42" (not just "42")

3. UNITS ARE CRITICAL:
   ✅ "20 stickers" (with unit)
   ❌ "20" (missing unit)

4. NUMBER LINE EXTRACTION:
   IF question involves number line:
   → Extract ALL filled numbers in order
   → question_type: "number_line"

5. GEOMETRIC DIAGRAMS:
   IF student drew shapes/diagrams:
   → has_visuals: true
   → Describe labeled dimensions

6. MULTI-BLANK PLACE VALUE:
   Format: "___ = ___ tens ___ ones"
   → Extract ALL parts: "65 = 6 tens 5 ones"
```

---

## 2️⃣ Physics（物理）

### 科目特点
- ⚡ **公式和单位**：F=ma, v=d/t, E=mc² (单位必须正确)
- 📊 **图表和图示**：力的图示、电路图、波形图
- 🔬 **实验数据**：表格数据、测量值、误差分析
- 📐 **矢量和标量**：需要区分方向（→, ←, ↑, ↓）

### 常见题型

#### 2.1 Formula Application（公式应用）
```
Example:
Q: "Calculate force: mass=10kg, acceleration=5m/s². F=ma"
Student wrote: "F = 10 × 5 = 50N"
→ student_answer: "F = 10 × 5 = 50N"
→ question_type: "calculation"
```

**特殊要求**:
- 保留公式：`F = ma`
- 保留单位：`N` (Newtons), `m/s²`, `kg`
- 提取完整计算过程

#### 2.2 Circuit Diagrams（电路图）
```
Example:
Q: "Draw a series circuit with 2 batteries and 3 light bulbs"
Student drew circuit diagram
→ student_answer: "Circuit diagram drawn with 2 batteries in series and 3 bulbs"
→ has_visuals: true
→ question_type: "diagram"
```

**特殊要求**:
- 如果学生画了电路图，设置 `has_visuals: true`
- 描述电路元件（resistor, battery, switch）
- 识别电路符号（⚡, ─, ╱, ○）

#### 2.3 Vector Diagrams（矢量图）
```
Example:
Q: "Draw the force vector acting on the object"
Student drew arrow pointing right labeled "20N"
→ student_answer: "Force vector: 20N pointing right"
→ has_visuals: true
```

**特殊要求**:
- 识别箭头方向（→, ←, ↑, ↓）
- 提取矢量大小和方向

#### 2.4 Data Tables（实验数据表）
```
Example:
Q: "Record your measurements in the table below"
Student filled table:
Time(s) | Distance(m)
1       | 5
2       | 10
3       | 15
→ student_answer: "Time: 1s→5m, 2s→10m, 3s→15m"
→ question_type: "data_table"
```

**特殊要求**:
- 提取表格所有数据
- 保留单位和对应关系

### Physics-Specific Parsing Rules

```python
PHYSICS-SPECIFIC RULES:

1. UNITS ARE MANDATORY:
   ✅ "50N" or "50 Newtons"
   ❌ "50" (missing unit)

   Common units: N, kg, m/s, m/s², J, W, V, A, Ω, Hz

2. FORMULAS MUST BE PRESERVED:
   ✅ "F = ma = 10 × 5 = 50N"
   ❌ "50N" (missing formula)

3. CIRCUIT DIAGRAMS:
   IF question involves circuits:
   → has_visuals: true
   → question_type: "diagram"
   → Describe circuit elements and connections

4. VECTOR NOTATION:
   IF arrows/directions present:
   → Extract: "Force = 20N pointing right (→)"
   → Include direction explicitly

5. EXPERIMENTAL DATA:
   IF data table present:
   → question_type: "data_table"
   → Extract all rows with units
```

---

## 3️⃣ Chemistry（化学）

### 科目特点
- ⚗️ **化学方程式**：H₂O, 2H₂ + O₂ → 2H₂O
- 🔤 **化学符号**：元素符号、离子符号、下标和上标
- 🧪 **实验操作**：步骤描述、安全措施
- 📊 **化学计算**：摩尔质量、浓度、pH值

### 常见题型

#### 3.1 Chemical Equations（化学方程式）
```
Example:
Q: "Balance the equation: H₂ + O₂ → H₂O"
Student wrote: "2H₂ + O₂ → 2H₂O"
→ student_answer: "2H₂ + O₂ → 2H₂O"
→ question_type: "chemical_equation"
```

**特殊要求**:
- 识别下标（₂, ₃）和上标（²⁺, ³⁻）
- 保留系数（2H₂ 不是 H₂）
- 保留箭头方向（→, ⇌）

#### 3.2 Element Names & Symbols（元素名称与符号）
```
Example:
Q: "What is the symbol for Sodium?"
Student wrote: "Na"
→ student_answer: "Na"
```

**特殊要求**:
- 大小写敏感：`Na` (正确) vs `na` (错误)
- 不要"修正"学生写的符号

#### 3.3 Lab Procedures（实验步骤）
```
Example:
Q: "Describe the steps to prepare a salt solution"
Student wrote:
"1. Measure 10g of NaCl
 2. Add to 100mL water
 3. Stir until dissolved"
→ student_answer: "1. Measure 10g of NaCl | 2. Add to 100mL water | 3. Stir until dissolved"
→ question_type: "long_answer"
```

**特殊要求**:
- 保留步骤编号
- 提取所有步骤（用 | 分隔）

#### 3.4 pH & Concentration（pH值与浓度）
```
Example:
Q: "Calculate the pH of the solution"
Student wrote: "pH = 7.4"
→ student_answer: "pH = 7.4"
```

**特殊要求**:
- 保留小数精度
- 保留单位（M, mol/L, g/mL）

### Chemistry-Specific Parsing Rules

```python
CHEMISTRY-SPECIFIC RULES:

1. CHEMICAL NOTATION:
   ✅ Preserve subscripts: H₂O (not H2O)
   ✅ Preserve superscripts: Ca²⁺ (not Ca2+)
   ✅ Preserve coefficients: 2H₂O (not H₂O)
   ✅ Preserve arrows: → or ⇌

2. ELEMENT SYMBOLS (CASE-SENSITIVE):
   ✅ "Na" (Sodium - correct)
   ❌ "na" or "NA" (incorrect case)
   → Extract EXACTLY as student wrote (don't correct)

3. CHEMICAL EQUATIONS:
   → question_type: "chemical_equation"
   → Extract complete equation with coefficients

4. LAB PROCEDURES:
   IF multi-step procedure:
   → Separate steps with " | "
   → Keep step numbers

5. PRECISION MATTERS:
   ✅ "pH = 7.4" (2 decimal places)
   ❌ "pH = 7" (lost precision)
```

---

## 4️⃣ Science（综合科学）

### 科目特点
- 🌍 **跨学科**：包含物理、化学、生物、地球科学
- 🔬 **观察和分类**：动物分类、物质状态、天气现象
- 📸 **图片识别**：识别动植物、实验器材、自然现象
- 📊 **数据记录**：温度、降雨量、生长速度

### 常见题型

#### 4.1 Classification（分类题）
```
Example:
Q: "Circle all the mammals: dog, fish, cat, bird, whale"
Student circled: dog, cat, whale
→ student_answer: "dog, cat, whale"
→ question_type: "multiple_choice"
```

**特殊要求**:
- 提取所有被圈选的选项
- 用逗号分隔

#### 4.2 Diagram Labeling（图表标注）
```
Example:
Q: "Label the parts of the plant"
Student labeled: roots, stem, leaves, flower
→ student_answer: "roots, stem, leaves, flower"
→ has_visuals: true
→ question_type: "diagram"
```

**特殊要求**:
- 设置 `has_visuals: true`
- 提取所有标签

#### 4.3 Observation Recording（观察记录）
```
Example:
Q: "Describe what you observed during the experiment"
Student wrote: "The ice melted in 5 minutes. Water temperature increased to 25°C."
→ student_answer: "The ice melted in 5 minutes. Water temperature increased to 25°C."
→ question_type: "long_answer"
```

### Science-Specific Parsing Rules

```python
SCIENCE-SPECIFIC RULES:

1. CLASSIFICATION ANSWERS:
   IF multiple items selected (circled/checked):
   → Separate with commas: "dog, cat, whale"

2. DIAGRAM LABELING:
   IF diagram present:
   → has_visuals: true
   → Extract all labels student wrote

3. OBSERVATIONS:
   IF descriptive answer:
   → question_type: "long_answer"
   → Extract complete sentences

4. MEASUREMENTS:
   → Always include units: "25°C", "5 minutes", "10 cm"
```

---

## 5️⃣ Biology（生物）

### 科目特点
- 🧬 **专业术语**：DNA, RNA, mitochondria, photosynthesis
- 📊 **图表**：细胞结构图、食物链、生命周期
- 🔬 **实验观察**：显微镜观察、解剖描述
- 📈 **数据分析**：种群数量、遗传概率

### 常见题型

#### 5.1 Cell Diagrams（细胞图）
```
Example:
Q: "Label the parts of the cell"
Student labeled: nucleus, cytoplasm, cell membrane, mitochondria
→ student_answer: "nucleus, cytoplasm, cell membrane, mitochondria"
→ has_visuals: true
→ question_type: "diagram"
```

#### 5.2 Food Chain（食物链）
```
Example:
Q: "Draw a food chain with at least 4 organisms"
Student drew: Sun → Grass → Rabbit → Fox
→ student_answer: "Sun → Grass → Rabbit → Fox"
→ has_visuals: true
```

**特殊要求**:
- 保留箭头方向（→）
- 保留顺序（producer → consumer）

#### 5.3 Genetics Problems（遗传题）
```
Example:
Q: "If both parents are Aa, what is the probability of aa offspring?"
Student wrote: "25% or 1/4"
→ student_answer: "25% or 1/4"
```

### Biology-Specific Parsing Rules

```python
BIOLOGY-SPECIFIC RULES:

1. DIAGRAM LABELING:
   IF biological diagram (cell, organ, ecosystem):
   → has_visuals: true
   → Extract all labeled parts

2. FOOD CHAINS/WEBS:
   IF arrows showing energy flow:
   → Preserve arrow direction: "→"
   → Format: "A → B → C"

3. GENETICS:
   → Accept multiple formats: "25%", "1/4", "0.25"
   → Preserve genotype notation: "Aa", "AA", "aa"

4. SCIENTIFIC TERMS:
   → Extract exactly as written (don't correct spelling)
```

---

## 6️⃣ Computer Science（计算机科学）

### 科目特点
- 💻 **代码片段**：Python, JavaScript, Scratch blocks
- 🔢 **算法逻辑**：伪代码、流程图、逻辑判断
- 🎮 **编程概念**：循环、条件、变量、函数
- 📊 **二进制/数据**：binary, hexadecimal, data structures

### 常见题型

#### 6.1 Code Reading（代码阅读）
```
Example:
Q: "What does this code output? print(5 + 3)"
Student wrote: "8"
→ student_answer: "8"
```

#### 6.2 Fill in Code（代码填空）
```
Example:
Q: "Complete the code: for i in range(___): print(i)"
Student wrote: "5"
→ student_answer: "5"
→ question_type: "fill_blank"
```

**特殊要求**:
- 识别代码语法（保留缩进、引号、括号）
- 不要"美化"代码

#### 6.3 Debugging（调试题）
```
Example:
Q: "Find the error in this code: print 'Hello World'"
Student wrote: "Missing parentheses: print('Hello World')"
→ student_answer: "Missing parentheses: print('Hello World')"
→ question_type: "short_answer"
```

#### 6.4 Binary/Hex Conversion（进制转换）
```
Example:
Q: "Convert 10 to binary"
Student wrote: "1010"
→ student_answer: "1010"
```

### Computer Science-Specific Parsing Rules

```python
COMPUTER_SCIENCE-SPECIFIC RULES:

1. CODE PRESERVATION:
   ✅ Preserve exact syntax: print('Hello')
   ❌ Don't modify: print ("Hello") or PRINT('Hello')
   → Extract exactly as student wrote

2. INDENTATION:
   IF code block:
   → Preserve indentation/spacing
   → Use spaces, not describe them

3. BINARY/HEX:
   → Extract as-is: "1010", "0xFF"
   → Don't convert or validate

4. ALGORITHM DESCRIPTION:
   IF pseudocode or steps:
   → question_type: "long_answer"
   → Preserve step numbers and logic
```

---

## 7️⃣ English（英语）

### 科目特点
- 📖 **阅读理解**：段落、文章、诗歌
- ✍️ **写作**：作文、短文、创意写作
- 📝 **语法**：句子结构、词性、标点
- 🔤 **词汇**：拼写、定义、同义词/反义词

### 常见题型

#### 7.1 Reading Comprehension（阅读理解）
```
Example:
Q: "What is the main idea of the passage?"
Student wrote: "The importance of recycling and protecting the environment."
→ student_answer: "The importance of recycling and protecting the environment."
→ question_type: "short_answer"
```

#### 7.2 Grammar（语法题）
```
Example:
Q: "Identify the verb in this sentence: 'The dog runs fast.'"
Student circled: "runs"
→ student_answer: "runs"
```

#### 7.3 Spelling（拼写题）
```
Example:
Q: "Spell the word: [image of elephant]"
Student wrote: "elefant"  (wrong spelling)
→ student_answer: "elefant"
→ question_type: "fill_blank"
```

**特殊要求**:
- 不要纠正拼写错误！提取学生实际写的

#### 7.4 Sentence Construction（造句）
```
Example:
Q: "Use 'because' in a sentence"
Student wrote: "I like summer because it is warm."
→ student_answer: "I like summer because it is warm."
→ question_type: "short_answer"
```

#### 7.5 Fill in the Blank (Cloze)（完形填空）
```
Example:
Q: "The boy _____ at _____ with his _____."
Student wrote: "is playing", "home", "dad"
→ student_answer: "is playing | home | dad"
→ question_type: "fill_blank"
```

**特殊要求**:
- 多空填空用 ` | ` 分隔（已在VISION FIRST中定义）

### English-Specific Parsing Rules

```python
ENGLISH-SPECIFIC RULES:

1. SPELLING ERRORS:
   ✅ Extract exactly: "elefant" (even if wrong)
   ❌ Don't correct to: "elephant"
   → AI will grade, not parse

2. PUNCTUATION PRESERVATION:
   ✅ "I like summer because it is warm."
   → Keep period, comma, quotation marks

3. MULTI-BLANK SENTENCES:
   Format: "The boy _____ at _____ with his _____."
   → student_answer: "is playing | home | dad"

4. LONG ANSWERS (Essays):
   IF student wrote paragraph(s):
   → question_type: "long_answer"
   → Extract complete text with line breaks

5. CIRCLED WORDS:
   IF student circled/underlined answer in text:
   → Extract only the circled word(s)
```

---

## 8️⃣ Foreign Language（外语）

### 科目特点
- 🌍 **多语言**：Spanish, French, Chinese, etc.
- 📚 **词汇翻译**：英文 ↔ 目标语言
- 🗣️ **语法练习**：动词变位、性数一致
- ✍️ **书写系统**：字母、汉字、假名

### 常见题型

#### 8.1 Translation（翻译）
```
Example:
Q: "Translate to Spanish: 'Hello, how are you?'"
Student wrote: "Hola, ¿cómo estás?"
→ student_answer: "Hola, ¿cómo estás?"
→ question_type: "short_answer"
```

**特殊要求**:
- 保留特殊字符（é, ñ, ¿, ¡, ü）
- 识别非拉丁字符（汉字、日文、韩文）

#### 8.2 Vocabulary（词汇）
```
Example:
Q: "What does 'gato' mean in English?"
Student wrote: "cat"
→ student_answer: "cat"
```

#### 8.3 Conjugation（动词变位）
```
Example:
Q: "Conjugate 'hablar' in present tense (yo)"
Student wrote: "hablo"
→ student_answer: "hablo"
```

#### 8.4 Character Writing（书写练习）
```
Example (Chinese):
Q: "Write the character for 'mountain'"
Student wrote: "山"
→ student_answer: "山"
→ question_type: "character_writing"
```

### Foreign Language-Specific Parsing Rules

```python
FOREIGN_LANGUAGE-SPECIFIC RULES:

1. SPECIAL CHARACTERS (CRITICAL):
   ✅ Preserve: é, ñ, ü, ö, à, ç, etc.
   → OCR must handle: Spanish (ñ, ¿), French (é, è, ê), German (ü, ö, ß)

2. NON-LATIN SCRIPTS:
   ✅ Chinese: 山, 水, 人
   ✅ Japanese: ひらがな, カタカナ, 漢字
   ✅ Arabic: العربية (right-to-left)
   → question_type: "character_writing" (if applicable)

3. ACCENTS MATTER:
   ✅ "está" ≠ "esta" (different meaning)
   → Don't remove or change accents

4. TRANSLATION DIRECTION:
   → Always note which direction (English→Spanish or Spanish→English)
```

---

## 9️⃣ History（历史）

### 科目特点
- 📅 **时间线**：年份、时期、世纪
- 🗺️ **地图**：历史地图、战役图
- 📜 **文件分析**：历史文献、演讲、宣言
- 👥 **人物事件**：历史人物、重大事件

### 常见题型

#### 9.1 Timeline（时间线）
```
Example:
Q: "Arrange these events in order: Civil War, WWI, WWII, Revolutionary War"
Student wrote: "Revolutionary War → Civil War → WWI → WWII"
→ student_answer: "Revolutionary War → Civil War → WWI → WWII"
→ question_type: "short_answer"
```

**特殊要求**:
- 保留箭头（→）表示顺序
- 保留年份（1776, 1865）

#### 9.2 Map Identification（地图识别）
```
Example:
Q: "Label the 13 original colonies on the map"
Student labeled states on map
→ student_answer: "VA, MA, NY, PA, NC, SC, GA, NH, CT, RI, MD, DE, NJ"
→ has_visuals: true
```

#### 9.3 Short Essay（简答题）
```
Example:
Q: "Explain the causes of WWI (3-5 sentences)"
Student wrote: [paragraph]
→ question_type: "long_answer"
```

### History-Specific Parsing Rules

```python
HISTORY-SPECIFIC RULES:

1. DATES & YEARS:
   ✅ Preserve format: "1776", "July 4, 1776", "1940s"
   → Don't convert or normalize

2. TIMELINES:
   IF sequential events:
   → Use arrows: "Event A → Event B → Event C"

3. MAP LABELING:
   IF map present:
   → has_visuals: true
   → Extract all labeled locations

4. PROPER NAMES:
   ✅ "George Washington" (exact capitalization)
   → Extract exactly as written
```

---

## 🔟 Geography（地理）

### 科目特点
- 🗺️ **地图技能**：识别国家、首都、地形
- 🌍 **空间关系**：方位、距离、比例
- 🏔️ **地形特征**：山脉、河流、海洋
- 📊 **数据分析**：人口、气候、资源

### 常见题型

#### 10.1 Map Labeling（地图标注）
```
Example:
Q: "Label the continents on the map"
Student labeled: North America, South America, Europe, Africa, Asia, Australia, Antarctica
→ student_answer: "North America, South America, Europe, Africa, Asia, Australia, Antarctica"
→ has_visuals: true
```

#### 10.2 Capital Cities（首都）
```
Example:
Q: "What is the capital of France?"
Student wrote: "Paris"
→ student_answer: "Paris"
```

#### 10.3 Compass Directions（方位）
```
Example:
Q: "Which ocean is to the east of the United States?"
Student wrote: "Atlantic Ocean"
→ student_answer: "Atlantic Ocean"
```

### Geography-Specific Parsing Rules

```python
GEOGRAPHY-SPECIFIC RULES:

1. MAP ELEMENTS:
   IF map present:
   → has_visuals: true
   → Extract all labels (countries, cities, features)

2. COMPASS DIRECTIONS:
   ✅ Accept: "north", "N", "北"
   → Extract as-is

3. PLACE NAMES:
   → Preserve exact spelling and capitalization
```

---

## 1️⃣1️⃣ Art（艺术）

### 科目特点
- 🎨 **视觉创作**：绘画、涂色、设计
- 🖼️ **作品分析**：识别艺术家、风格、技法
- 📐 **设计元素**：线条、形状、颜色、构图
- 🔧 **材料技术**：水彩、油画、雕塑

### 常见题型

#### 11.1 Drawing Tasks（绘画任务）
```
Example:
Q: "Draw a self-portrait"
Student drew portrait
→ student_answer: "Self-portrait drawn"
→ has_visuals: true
→ question_type: "creative_work"
```

**特殊要求**:
- 始终设置 `has_visuals: true`
- 描述创作内容（如果有文字标注）

#### 11.2 Color Theory（色彩理论）
```
Example:
Q: "What color do you get when you mix red and blue?"
Student wrote: "Purple"
→ student_answer: "Purple"
```

#### 11.3 Artist Identification（艺术家识别）
```
Example:
Q: "Who painted the Mona Lisa?"
Student wrote: "Leonardo da Vinci"
→ student_answer: "Leonardo da Vinci"
```

### Art-Specific Parsing Rules

```python
ART-SPECIFIC RULES:

1. VISUAL WORK:
   IF student created drawing/painting:
   → has_visuals: true
   → question_type: "creative_work"
   → student_answer: Brief description

2. COLOR NAMES:
   ✅ Accept various formats: "purple", "Purple", "紫色"
   → Extract as-is

3. ARTIST NAMES:
   → Preserve exact spelling
```

---

## 1️⃣2️⃣ Music（音乐）

### 科目特点
- 🎵 **乐谱识别**：五线谱、音符、节奏
- 🎼 **音乐理论**：音阶、和弦、调号
- 🎤 **音乐史**：作曲家、时期、作品
- 🎹 **演奏技巧**：指法、技法描述

### 常见题型

#### 12.1 Note Reading（读谱）
```
Example:
Q: "What note is this? [image of middle C on staff]"
Student wrote: "C"
→ student_answer: "C"
```

#### 12.2 Rhythm（节奏）
```
Example:
Q: "How many beats is a whole note?"
Student wrote: "4 beats"
→ student_answer: "4 beats"
```

#### 12.3 Composer Identification（作曲家识别）
```
Example:
Q: "Who composed the Moonlight Sonata?"
Student wrote: "Beethoven"
→ student_answer: "Beethoven"
```

### Music-Specific Parsing Rules

```python
MUSIC-SPECIFIC RULES:

1. MUSICAL NOTATION:
   IF staff/notes present:
   → has_visuals: true
   → Extract note names: "C", "G", "F#"

2. RHYTHM VALUES:
   → Include "beats": "4 beats", "1/2 beat"

3. SHARP/FLAT NOTATION:
   ✅ Preserve: "F#", "Bb", "C♯"
```

---

## 1️⃣3️⃣ Physical Education（体育）

### 科目特点
- 🏃 **运动技能**：跑、跳、投、接
- 📊 **体能测试**：时间、距离、次数
- 🏀 **规则知识**：运动规则、策略
- 💪 **健康知识**：营养、锻炼、安全

### 常见题型

#### 13.1 Performance Recording（成绩记录）
```
Example:
Q: "Record your 50-meter dash time"
Student wrote: "8.5 seconds"
→ student_answer: "8.5 seconds"
```

#### 13.2 Rules Knowledge（规则知识）
```
Example:
Q: "How many players are on a basketball team on the court?"
Student wrote: "5 players"
→ student_answer: "5 players"
```

#### 13.3 Diagram Labeling（图表标注）
```
Example:
Q: "Label the parts of the basketball court"
Student labeled: free throw line, 3-point line, key
→ student_answer: "free throw line, 3-point line, key"
→ has_visuals: true
```

### Physical Education-Specific Parsing Rules

```python
PE-SPECIFIC RULES:

1. MEASUREMENTS:
   → Include units: "8.5 seconds", "10 meters", "25 reps"

2. COUNTS:
   → Include descriptor: "5 players", "3 points"

3. DIAGRAMS:
   IF court/field diagram:
   → has_visuals: true
   → Extract labeled parts
```

---

## 🎯 Subject-Specific Prompt Design Strategy

### 设计原则

1. **通用基础 (General Base)**
   - VISION FIRST原则（所有科目共享）
   - 7种基础question_type（所有科目共享）
   - JSON schema（所有科目共享）

2. **科目增强 (Subject Enhancement)**
   - 在通用规则基础上添加科目特定规则
   - 不替换通用规则，只增强

3. **实现方式**
   ```python
   def _build_parse_prompt(self, subject: str = "General") -> str:
       # 1. Load base prompt (VISION FIRST + 7 types)
       base_prompt = self._get_base_prompt()

       # 2. Add subject-specific rules
       subject_rules = self._get_subject_rules(subject)

       # 3. Combine
       return f"{base_prompt}\n\n{subject_rules}"
   ```

### Prompt Structure

```
[SECTION 1: JSON SCHEMA] ← 所有科目共享
[SECTION 2: VISION FIRST] ← 所有科目共享
[SECTION 3: EXTRACTION RULES] ← 所有科目共享
[SECTION 4: 7 QUESTION TYPES] ← 所有科目共享
[SECTION 5: ANSWER EXTRACTION] ← 所有科目共享
[SECTION 6: SUBJECT-SPECIFIC RULES] ← 根据subject动态插入
[SECTION 7: OUTPUT CHECKLIST] ← 所有科目共享
```

---

## 📊 Subject Grouping for Implementation

为了高效实现，按相似度分组：

### Group 1: STEM Calculation (3 subjects)
- Math, Physics, Chemistry
- **共同点**: 公式、单位、精确计算
- **共享规则**: 单位保留、公式提取、数值精度

### Group 2: STEM Concept (3 subjects)
- Science, Biology, Computer Science
- **共同点**: 图表、专业术语、数据结构
- **共享规则**: 图表识别、术语保留、数据提取

### Group 3: Language Arts (2 subjects)
- English, Foreign Language
- **共同点**: 文本、拼写、语法
- **共享规则**: 多空填空、拼写保留、特殊字符

### Group 4: Social Sciences (2 subjects)
- History, Geography
- **共同点**: 地图、时间线、地点
- **共享规则**: 地图标注、时间顺序、地名保留

### Group 5: Creative Arts (3 subjects)
- Art, Music, Physical Education
- **共同点**: 视觉创作、表现描述
- **共享规则**: has_visuals=true、描述性答案

---

## ✅ Next Steps

1. ✅ **Phase 1: 调研完成**（当前文档）
   - 13个科目分析
   - 题型分类
   - 解析规则设计

2. ⏳ **Phase 2: 实现科目特定prompt系统**
   - 创建 `subject_prompts.py`
   - 实现 `_get_subject_rules(subject)` 方法
   - 修改 `_build_parse_prompt()` 支持subject参数

3. ⏳ **Phase 3: 测试与验证**
   - 每个科目至少测试3份真实作业
   - 对比通用prompt vs 科目特定prompt
   - 调整规则

4. ⏳ **Phase 4: 文档与部署**
   - 更新API文档
   - 部署到Railway
   - 通知iOS团队subject参数可用

---

**创建时间**: 2025-11-24
**状态**: 📊 调研完成，待实现
**下一步**: 实现 subject_prompts.py 模块
