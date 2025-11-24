# Gemini 实际输出 vs 理想输出 - 问题分析

**测试作业**: Olivia Jiang - Number Line and One More One Less
**测试时间**: 2025-11-23
**处理时间**: 5.9s ⚡
**模型**: gemini-2.0-flash

---

## 📊 对比结果总览

| Question | 理想输出 | 实际输出 | 状态 | 问题描述 |
|----------|----------|----------|------|----------|
| **Q1** | 1 parent + 4 subs | 1 parent + 4 subs | ✅ 完美 | 无问题 |
| **Q2** | 1 parent + 4 subs | 1 parent + 2 subs | ❌ **严重** | **漏掉 2c 和 2d** |
| **Q2a/2b** | 完整答案 | 部分答案 | ⚠️ 不完整 | 漏掉 tens/ones 部分 |
| **Q3** | 双重问题 | 单一问题 | ⚠️ 不完整 | 只提取了第一个问题 |
| **Q4** | 正确 | 正确 | ✅ 完美 | 无问题 |
| **Q5** | 正确 | 正确 | ✅ 完美 | 无问题 |
| **Q6** | 正确 | 正确 | ✅ 完美 | 使用 | 分隔符 |

**正确率**: 4/6 完美，2/6 有问题（66.7%）

---

## ❌ 问题 1: Question 2 漏掉 2c 和 2d（最严重）

### 理想输出（应该有 4 个子问题）:
```json
{
  "id": 2,
  "question_number": "2",
  "is_parent": true,
  "has_subquestions": true,
  "parent_content": "Find one more or one less. Identify the digit in the tens and ones places in a-b.",
  "subquestions": [
    {"id": "2a", "question_text": "What number is one more than 64?", ...},
    {"id": "2b", "question_text": "What number is one less than 40?", ...},
    {"id": "2c", "question_text": "Alex counted 34 ducks...", ...},  // ❌ 缺少
    {"id": "2d", "question_text": "Sally has 19 stickers...", ...}   // ❌ 缺少
  ]
}
```

### 实际输出（只有 2 个子问题）:
```json
{
  "id": 2,
  "subquestions": [
    {"id": "2a", ...},
    {"id": "2b", ...}
    // ❌ 2c 和 2d 完全缺失！
  ]
}
```

### 🔍 根本原因分析

#### 原因 1: parent_content 误导
**Prompt 中的 parent_content**:
```
"Find one more or one less. Identify the digit in the tens and ones places in a-b."
```

**关键问题**:
- ✅ 明确提到 "in a-b" → AI 认为只有 a 和 b
- ❌ **没有提到 c 和 d** → AI 停止提取

**实际作业中**:
- Question 2a: "What number is one more than 64?" ✅ 提取了
- Question 2b: "What number is one less than 40?" ✅ 提取了
- Question 2c: "Alex counted 34 ducks..." ❌ **被忽略**
- Question 2d: "Sally has 19 stickers..." ❌ **被忽略**

#### 原因 2: 当前 Prompt 的缺陷

**当前 Prompt（Line 406）**:
```
🚨 IF parent_content mentions "in a-b" or "in parts a and b"
   → THERE ARE SUBQUESTIONS a AND b
```

**问题**:
- ✅ AI 正确识别了 "a-b" → 提取 a 和 b
- ❌ **但 2c 和 2d 没有在 parent_content 中提到** → 被跳过
- ❌ **没有"继续扫描后续子问题"的指令**

#### 原因 3: 缺少"扫描所有字母部分"的指令

**当前 Prompt（Line 416）**:
```
1. Look VERY CAREFULLY for all lettered parts (a, b, c, d, etc.)
```

**问题**:
- 这条规则**太弱**，没有强制要求
- 没有说明"即使 parent_content 只提到 a-b，也要检查是否有 c, d, e..."
- 缺少"扫描完所有同级缩进/编号"的指令

---

## ⚠️ 问题 2: Question 2a/2b 答案不完整

### 理想输出:
```json
{
  "id": "2a",
  "question_text": "What number is one more than 64? Fill in: ___ = ___ tens ___ ones",
  "student_answer": "65 = 6 tens 5 ones"  // ✅ 完整答案
}
```

### 实际输出:
```json
{
  "id": "2a",
  "question_text": "What number is one more than 64?",
  "student_answer": "65"  // ❌ 只有数字，漏掉 tens/ones
}
```

### 🔍 根本原因分析

#### 原因: 缺少"多空填空"处理规则

**当前 Prompt（Line 431）**:
```
3. Extract ALL student answers exactly as written (or "" if blank)
```

**问题**:
- 没有说明如何处理**多个空格**的答案
- 没有说明"如果有多个填空，全部提取"
- AI 可能只提取了"第一个空"的答案（65）

**实际作业中**:
```
2a. What number is one more than 64? _____ = _____ tens _____ ones
    学生填写: 65 = 6 tens 5 ones
```

**AI 的理解**:
- ✅ 识别了问题文本
- ❌ **只提取了第一个空（65）**
- ❌ 忽略了后面的 "= 6 tens 5 ones"

---

## ⚠️ 问题 3: Question 3 双重问题只提取一半

### 理想输出:
```json
{
  "id": 3,
  "question_number": "3",
  "question_text": "In the word forty, which letter is to the immediate right of the o? Which letter is to the immediate left of the t?",
  "student_answer": "r (right of o), r (left of t)"  // ✅ 两个答案
}
```

### 实际输出:
```json
{
  "id": 3,
  "question_number": "3",
  "question_text": "In the word forty, which letter is to the immediate right of the o?",
  "student_answer": "r"  // ❌ 只有一个答案
}
```

### 🔍 根本原因分析

#### 原因: 缺少"一题多问"处理规则

**当前 Prompt**:
- ❌ **完全没有**处理"一个题号下有多个独立问题"的规则
- 只有 parent/subquestions 的概念，没有"一题多问"的概念

**实际作业中**:
```
3. In the word forty, which letter is to the immediate right of the o?
   Which letter is to the immediate left of the t?
   学生回答: r (第一行), r (第二行)
```

**AI 的理解**:
- ✅ 识别了第一个问题 "which letter is right of o?"
- ❌ **忽略了第二个问题** "Which letter is to the immediate left of the t?"
- ❌ 只提取了第一个答案 "r"

---

## 📊 问题根源总结

| 问题 | 当前 Prompt 的缺陷 | 后果 |
|------|-------------------|------|
| **Q2 漏掉 2c/2d** | parent_content 提到 "a-b" → AI 认为只有 a 和 b | 🔴 **严重**：漏掉 50% 的子问题 |
| | 没有"继续扫描所有字母部分"的强制指令 | |
| **Q2a/2b 不完整** | 没有"多空填空"的提取规则 | 🟡 中等：答案不完整 |
| | 没有说明"提取所有空格的答案" | |
| **Q3 双重问题** | 没有"一题多问"的处理规则 | 🟡 中等：漏掉第二个问题 |
| | 没有说明如何处理连续的两个问题 | |

---

## 🎯 针对性改进建议

### 改进 1: 修复 "2c/2d 漏掉" 问题（最关键）

#### 当前 Prompt（有问题的部分）:
```
Line 406:
🚨 IF parent_content mentions "in a-b" or "in parts a and b"
   → THERE ARE SUBQUESTIONS a AND b
```

#### 改进后:
```
🚨 SUBQUESTION SCANNING (CRITICAL):
1. IF you see a parent instruction, SCAN for ALL lettered/numbered parts
2. DO NOT STOP at "a-b" mentioned in parent_content
3. Continue scanning until no more lettered parts are found
4. Check: a, b, c, d, e, f... until you reach the next numbered question

EXAMPLE:
Parent: "Find one more or one less. Identify the digit in a-b."
✅ Extract: a, b (mentioned in parent)
✅ ALSO CHECK: Are there c, d, e... below? → YES → Extract them too!

WRONG APPROACH ❌:
Parent mentions "a-b" → Stop at b → Miss c, d

CORRECT APPROACH ✅:
Parent mentions "a-b" → Still scan for c, d, e... → Extract ALL
```

#### 具体规则:
```
SUBQUESTION COMPLETION RULE:
1. Start with the first subquestion (usually "a" or "i")
2. Look for the NEXT sequential letter/number
3. Continue until you find:
   - Next top-level question number (e.g., "3." after "2d")
   - OR a new section divider (e.g., "Complete the review")
   - OR end of page
4. Extract ALL sequential subquestions, even if parent_content doesn't mention them
```

---

### 改进 2: 修复 "多空填空" 问题

#### 新增规则:
```
MULTI-BLANK ANSWER EXTRACTION:
1. IF question has multiple blanks (e.g., "___ = ___ tens ___ ones"):
   → student_answer should include ALL filled blanks
   → Format: "65 = 6 tens 5 ones" (preserve structure)

2. HOW TO IDENTIFY:
   ✅ Look for multiple underscores: "___", "___", "___"
   ✅ Look for multiple answer boxes or spaces
   ✅ Look for student writing in multiple locations

3. EXTRACTION:
   ✅ Extract ALL parts as ONE student_answer
   ✅ Use spaces or " = " to separate parts
   ✅ Preserve the original structure

EXAMPLE:
Question: "What number is one more than 64? ___ = ___ tens ___ ones"
Student wrote: "65" in first blank, "6" in second blank, "5" in third blank
→ student_answer = "65 = 6 tens 5 ones" ✅
→ NOT just "65" ❌
```

---

### 改进 3: 修复 "双重问题" 问题

#### 新增规则:
```
ONE-NUMBER MULTIPLE-QUESTIONS:
IF you see one question number (e.g., "3.") with TWO separate questions:

1. CHECK: Are they RELATED (same context)?
   → YES → Treat as parent with subquestions
   → NO → Treat as ONE question with multiple parts

2. FOR INDEPENDENT QUESTIONS (like Q3):
   ✅ Combine both questions in question_text
   ✅ Combine both answers in student_answer
   ✅ Clearly label which answer goes to which question

EXAMPLE:
"3. In the word forty, which letter is right of o? Which letter is left of t?"
Student answers: "r" (first), "r" (second)

WRONG ❌:
question_text = "which letter is right of o?"
student_answer = "r"

CORRECT ✅:
question_text = "In the word forty, which letter is right of o? Which letter is left of t?"
student_answer = "r (right of o), r (left of t)"
```

---

## 📝 完整改进 Prompt 要点

### 修改位置 1: Line 415-420（子问题提取）

**当前**:
```
⚠️ SUBQUESTION EXTRACTION (CRITICAL):
1. Look VERY CAREFULLY for all lettered parts (a, b, c, d, etc.)
2. Even if student answer is blank/unclear, STILL extract the subquestion
3. If answer is missing: use empty string "" for student_answer
4. If question text is unclear: write your best interpretation
5. NEVER return empty subquestions array if parent_content mentions parts!
```

**改进**:
```
⚠️ SUBQUESTION EXTRACTION (CRITICAL - ENHANCED):
1. IF you see a parent question, SCAN for ALL sequential lettered/numbered parts
   → Do NOT stop at what parent_content mentions (e.g., "a-b")
   → Continue scanning: c, d, e, f... until next top-level question

2. HOW TO SCAN:
   ✅ Start from first sub (usually "a" or "i")
   ✅ Look for NEXT sequential letter/number in order
   ✅ Stop only when you reach next top-level question or section divider

3. Even if student answer is blank/unclear, STILL extract the subquestion
4. If answer is missing: use empty string "" for student_answer
5. NEVER return empty subquestions array if you found ANY lettered parts!

EXAMPLE:
Parent: "Solve the following in a-b:"
Image shows: a) ..., b) ..., c) ..., d) ...
→ Extract ALL: a, b, c, d ✅
→ NOT just a, b ❌ (even though parent only mentioned "a-b")
```

---

### 修改位置 2: Line 431（答案提取规则）

**当前**:
```
3. Extract ALL student answers exactly as written (or "" if blank)
```

**改进**:
```
3. Extract ALL student answers exactly as written (or "" if blank)
   → IF multiple blanks: extract ALL parts as one student_answer
   → Format: "65 = 6 tens 5 ones" (preserve structure)
   → Do NOT split into separate fields
```

---

### 新增规则（插入到 Line 428 之后）:

```
SPECIAL CASES:

A. ONE NUMBER, MULTIPLE QUESTIONS:
   IF one question number has TWO+ separate questions:
   → Combine all questions in question_text (separated by spaces)
   → Combine all answers in student_answer (with labels: "answer1, answer2")

   EXAMPLE:
   "3. Which letter is right of o? Which is left of t?"
   Student: "r", "r"
   → question_text = "Which letter is right of o? Which is left of t?"
   → student_answer = "r (right of o), r (left of t)"

B. MULTI-BLANK ANSWERS:
   IF question has multiple blanks (___, ___, ___):
   → Extract ALL filled blanks as one student_answer
   → Preserve structure: "65 = 6 tens 5 ones"
```

---

## 🎯 关键改进总结

| 问题 | 改进要点 | 预期效果 |
|------|----------|----------|
| **Q2 漏掉 2c/2d** | 强制扫描所有字母部分，不受 parent_content 限制 | ✅ 不再漏掉后续子问题 |
| **Q2a/2b 不完整** | 明确"多空填空全部提取"规则 | ✅ 完整提取 "65 = 6 tens 5 ones" |
| **Q3 双重问题** | 新增"一题多问"处理规则 | ✅ 提取两个问题和两个答案 |

---

## 📊 预期改进后的输出

### Question 2 (修复后):
```json
{
  "id": 2,
  "subquestions": [
    {"id": "2a", "student_answer": "65 = 6 tens 5 ones"},  // ✅ 完整
    {"id": "2b", "student_answer": "39 = 3 tens 9 ones"},  // ✅ 完整
    {"id": "2c", "question_text": "Alex counted 34 ducks...", "student_answer": "35 ducklings"},  // ✅ 不再漏掉
    {"id": "2d", "question_text": "Sally has 19 stickers...", "student_answer": "20 sticker"}  // ✅ 不再漏掉
  ]
}
```

### Question 3 (修复后):
```json
{
  "id": 3,
  "question_text": "In the word forty, which letter is to the immediate right of the o? Which letter is to the immediate left of the t?",
  "student_answer": "r (right of o), r (left of t)"  // ✅ 两个答案都有
}
```

---

**结论**: 当前 Prompt 的**核心问题**是：
1. ❌ 子问题扫描不够彻底（受 parent_content 误导）
2. ❌ 缺少"多空填空"规则
3. ❌ 缺少"一题多问"规则

通过上述改进，可以将准确率从 **66.7%** 提升到接近 **100%**。

---

**文档创建时间**: 2025-11-23
**测试对象**: Olivia Jiang 作业（Gemini 实际输出）
**改进优先级**: 🔴 高（Q2 漏题问题最严重）
