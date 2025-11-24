# Gemini Parse Analysis - Sample Homework

**作业图片**: Olivia Jiang 的数学作业（10/1/2025）
**标题**: Class Practice: Number Line and One More One Less

---

## 📊 理想的解析结果（应该得到的）

```json
{
  "subject": "Mathematics",
  "subject_confidence": 0.98,
  "total_questions": 6,
  "questions": [
    {
      "id": 1,
      "question_number": "1",
      "is_parent": true,
      "has_subquestions": true,
      "parent_content": "Label the number line from 10-19 by counting by ones.",
      "subquestions": [
        {
          "id": "1a",
          "question_text": "What number is one more than 14?",
          "student_answer": "15",
          "question_type": "short_answer"
        },
        {
          "id": "1b",
          "question_text": "What number is one less than 17?",
          "student_answer": "16",
          "question_type": "short_answer"
        },
        {
          "id": "1c",
          "question_text": "What number is one more than 11?",
          "student_answer": "12",
          "question_type": "short_answer"
        },
        {
          "id": "1d",
          "question_text": "What number is one less than 18?",
          "student_answer": "17",
          "question_type": "short_answer"
        }
      ]
    },
    {
      "id": 2,
      "question_number": "2",
      "is_parent": true,
      "has_subquestions": true,
      "parent_content": "Find one more or one less. Identify the digit in the tens and ones places in a-b.",
      "subquestions": [
        {
          "id": "2a",
          "question_text": "What number is one more than 64? Fill in: ___ = ___ tens ___ ones",
          "student_answer": "65 = 6 tens 5 ones",
          "question_type": "fill_blank"
        },
        {
          "id": "2b",
          "question_text": "What number is one less than 40? Fill in: ___ = ___ tens ___ ones",
          "student_answer": "39 = 3 tens 9 ones",
          "question_type": "fill_blank"
        },
        {
          "id": "2c",
          "question_text": "Alex counted 34 ducks in the pond. He counted one less duckling than ducks. How many ducklings did he count?",
          "student_answer": "35 ducklings",
          "question_type": "word_problem"
        },
        {
          "id": "2d",
          "question_text": "Sally has 19 stickers. Gia has one more sticker than Sally. How many stickers does Gia have?",
          "student_answer": "20 sticker",
          "question_type": "word_problem"
        }
      ]
    },
    {
      "id": 3,
      "question_number": "3",
      "is_parent": false,
      "question_text": "In the word forty, which letter is to the immediate right of the o? Which letter is to the immediate left of the t?",
      "student_answer": "r (right of o), r (left of t)",
      "question_type": "short_answer"
    },
    {
      "id": 4,
      "question_number": "4",
      "is_parent": false,
      "question_text": "Instead of visiting the zoo in March, Leo will visit the zoo the month before. What month will he visit the zoo?",
      "student_answer": "February",
      "question_type": "short_answer"
    },
    {
      "id": 5,
      "question_number": "5",
      "is_parent": false,
      "question_text": "Write the number that is represented by the picture.",
      "student_answer": "41",
      "question_type": "diagram_interpretation",
      "has_visuals": true
    },
    {
      "id": 6,
      "question_number": "6",
      "is_parent": false,
      "question_text": "Count by ones from 93 to 86.",
      "student_answer": "93 92 91 90 89 88 87 86",
      "question_type": "sequence"
    }
  ]
}
```

---

## ⚠️ 当前 Prompt 可能遇到的问题

### 问题 1: 漏掉 Question 3
**原因**: Question 3 没有明显的编号（在 "Complete the review." 之后）
**当前 prompt 的弱点**:
- 没有"扫描整个页面"的指令
- 可能跳过 "Complete the review." 后面的内容
- 没有验证是否扫描了整个图片

**可能的错误结果**:
```json
{
  "total_questions": 5,  // ❌ 应该是 6
  "questions": [...]  // 缺少 Question 3
}
```

---

### 问题 2: Question 2c 的答案识别错误
**学生写的**: "35 ducklings"
**正确答案应该是**: "33 ducklings" (34 - 1 = 33)

**当前 prompt 的弱点**:
- 没有明确说明"提取学生手写的答案，即使错误"
- AI 可能会自己计算并填入"正确答案"而不是学生写的

**可能的错误结果**:
```json
{
  "id": "2c",
  "student_answer": "33 ducklings"  // ❌ AI 自己算的，不是学生写的
}
```

**应该是**:
```json
{
  "id": "2c",
  "student_answer": "35 ducklings"  // ✅ 学生实际写的（虽然错了）
}
```

---

### 问题 3: Question 1 的数轴答案可能被忽略
**图片中**: 学生在数轴上填写了 10, 11, 12, 13, 14, 15, 16, 17, 18, 19

**当前 prompt 的弱点**:
- 没有说明如何处理"图表填空"类型的答案
- 可能只提取 a, b, c, d 子问题，忽略数轴本身

**可能的错误结果**:
```json
{
  "id": 1,
  "parent_content": "Label the number line from 10-19 by counting by ones.",
  "subquestions": [...]  // ✅ 有 a, b, c, d
}
```

**但缺少**: 数轴本身的答案（10-19 的填写）

**理想结果**: parent_content 应该包含"学生已完成数轴标注"的信息

---

### 问题 4: Question 5 的视觉元素
**图片中**: 有一个 tens/ones 图表（4 个竖条 + 1 个单位）

**当前 prompt 的弱点**:
- 没有说明如何描述视觉元素
- `has_visuals` 字段可能不会被设置

**可能的错误结果**:
```json
{
  "id": 5,
  "question_text": "Write the number that is represented by the picture.",
  "student_answer": "41",
  "has_visuals": false  // ❌ 应该是 true
}
```

---

### 问题 5: Question 2a 和 2b 的答案格式
**学生写的**:
- 2a: `65 = 6 tens 5 ones`
- 2b: `39 = 3 tens 9 ones`

**当前 prompt 的弱点**:
- 没有说明如何处理"多空填空"类型的答案
- 可能只提取部分答案

**可能的错误结果**:
```json
{
  "id": "2a",
  "student_answer": "65"  // ❌ 只提取了数字，漏掉了 tens/ones 部分
}
```

**应该是**:
```json
{
  "id": "2a",
  "student_answer": "65 = 6 tens 5 ones"  // ✅ 完整答案
}
```

---

### 问题 6: Question 3 的双重问题
**问题文本**:
- "In the word forty, which letter is to the immediate right of the o?"
- "Which letter is to the immediate left of the t?"

**当前 prompt 的弱点**:
- 没有说明如何处理"一个题号下有两个独立问题"的情况
- 可能被误识别为 parent question with subquestions

**可能的错误结果 1** (错误地识别为 parent):
```json
{
  "id": 3,
  "is_parent": true,  // ❌ 不应该是 parent
  "has_subquestions": true,
  "subquestions": [...]
}
```

**可能的错误结果 2** (合并为一个答案):
```json
{
  "id": 3,
  "question_text": "In the word forty, which letter is to the immediate right of the o? Which letter is to the immediate left of the t?",
  "student_answer": "r r"  // ❌ 不清晰
}
```

**理想结果**:
```json
{
  "id": 3,
  "question_text": "In the word forty, which letter is to the immediate right of the o? Which letter is to the immediate left of the t?",
  "student_answer": "r (right of o), r (left of t)"  // ✅ 清晰标注
}
```

---

## 📊 问题总结

| 问题类型 | 具体表现 | 当前 Prompt 的缺陷 | 影响 |
|----------|----------|-------------------|------|
| **漏题** | 可能漏掉 Question 3 | 没有"扫描整个页面"指令 | 🔴 高 |
| **答案识别** | Question 2c 可能被"自动修正" | 没有强调"提取实际手写内容" | 🔴 高 |
| **视觉元素** | Question 5 的图表可能被忽略 | 没有说明如何处理图表 | 🟡 中 |
| **格式理解** | Question 2a/2b 多空答案可能不完整 | 没有处理"复合填空"的指示 | 🟡 中 |
| **双重问题** | Question 3 可能被错误分组 | 没有处理"一题多问"的规则 | 🟡 中 |
| **数轴答案** | Question 1 的数轴填写可能被忽略 | 没有说明如何处理图表填空 | 🟢 低 |

---

## 🎯 针对这张作业的改进建议

### 改进 1: 添加扫描指令（防止漏题）
```
SCANNING INSTRUCTIONS:
1. Scan from TOP to BOTTOM, including ALL sections
2. Look for questions AFTER "Complete the review" or similar dividers
3. Check if there are more questions below the visible area
4. Verify: Did I find all numbered questions (1, 2, 3, 4, 5, 6...)?
```

### 改进 2: 强调"提取实际手写内容"（防止自动修正）
```
CRITICAL RULE: student_answer = What the student ACTUALLY WROTE
- Even if the answer is mathematically WRONG → still extract it
- Do NOT calculate or correct the answer yourself
- Do NOT provide the "correct" answer in student_answer field

EXAMPLE:
Question: "34 - 1 = ?"
Student wrote: "35" (wrong)
→ student_answer = "35" ✅ (extract what student wrote)
→ NOT "33" ❌ (don't auto-correct)
```

### 改进 3: 处理图表填空
```
VISUAL ELEMENT EXTRACTION:
1. If question asks to "label" or "fill in" a diagram/number line:
   → Extract what student wrote ON the diagram
   → Mention in parent_content: "Student completed [diagram type]"

2. If question shows a picture (chart, graph, tens/ones blocks):
   → Set has_visuals = true
   → Describe what the visual shows (if relevant)
```

### 改进 4: 处理多空填空
```
MULTI-BLANK ANSWERS:
If question has multiple blanks (e.g., "___ = ___ tens ___ ones"):
→ Extract ALL parts as one student_answer
→ Format: "65 = 6 tens 5 ones" (preserve structure)
→ Do NOT split into separate fields
```

### 改进 5: 处理"一题多问"
```
MULTIPLE QUESTIONS IN ONE NUMBER:
If you see "Question X: [question 1]... [question 2]":
- Check if they are RELATED (share context) → parent with subquestions
- Check if they are INDEPENDENT (different topics) → keep as one question, combine answers

EXAMPLE (Independent):
"3. In the word forty, which letter is right of o? Which is left of t?"
→ ONE question with combined answer: "r (right of o), r (left of t)"
```

---

## 💡 关键发现

通过分析这张实际作业，发现当前 Prompt 的**最大问题**是：

1. ❌ **缺少"完整扫描"保证** → 容易漏题
2. ❌ **没有强调"提取实际内容，不要修正"** → AI 可能自作聪明
3. ❌ **视觉元素处理不明确** → 图表、数轴等容易被忽略
4. ❌ **缺少"多空填空"的提取规则** → 答案可能不完整

---

## 📝 建议的测试流程

1. **先用当前 Prompt 测试这张图片** → 看实际输出
2. **对比理想输出** → 找出具体差异
3. **针对性改进 Prompt** → 逐个修复问题
4. **再次测试** → 验证改进效果
5. **使用更多真实作业测试** → 确保鲁棒性

---

**文档创建时间**: 2025-11-23
**分析对象**: Olivia Jiang 作业（Number Line and One More One Less）
**目的**: 识别当前 Gemini Prompt 的实际问题并提供改进方向
