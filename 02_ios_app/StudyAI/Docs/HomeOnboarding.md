# Home Onboarding — Coach-Mark Tour Copy

Source-of-truth for the 10-step home-screen overlay (`HomeOnboardingOverlayView` in `HomeView.swift`).

Edit freely — once approved, copy is wired into `HomeOnboardingStep` enum + `NSLocalizedString` keys (`homeOnboarding.{step}.title` / `.desc`).

---

## Tour order (top-down, **Points Shop moved to end**)

| # | Step ID          | SF Symbol                              | Position                       |
|---|------------------|----------------------------------------|--------------------------------|
| 1 | `askAI`          | `message.fill`                         | Quick Actions card 1           |
| 2 | `snapHomework`   | `camera.fill`                          | Quick Actions card 2           |
| 3 | `practice`       | `pencil.and.list.clipboard`            | Quick Actions card 3           |
| 4 | `suggestedTodos` | (torn-notebook section, no SF icon)    | Middle suggestion card         |
| 5 | `mistakeReview`  | `xmark.circle.fill`                    | More Features                  |
| 6 | `knowledgeTree`  | `leaf.fill`                            | More Features                  |
| 7 | `focusMode`      | `brain.head.profile`                   | More Features                  |
| 8 | `parentReports`  | `figure.2.and.child.holdinghands`      | More Features                  |
| 9 | `progress`       | `chart.bar.fill`                       | More Features                  |
| 10 | `pointsShop`    | `star.fill` (header badge)             | Header — top-right ⭐ icon      |

> Each step's callout card shows the matching SF Symbol next to its title — no new icons added.

---

## ① Ask AI · `message.fill`

> **Position:** Quick Actions card 1 · **Action:** opens `.chat` tab

### EN
**Title:** Ask AI — your real-time tutor

Type, voice, or photo. Answers in seconds.

- **Practice on the spot** — generate questions tied to the current chat topic, no menu hunting.
- Tap **Smart Learning** to drop into an interactive AI video lesson on whatever you're stuck on.
- Ask for **diagrams** — AI generates visuals for hard-to-grasp concepts.
- ⋯ menu → **Live Mode** for hands-free voice + scenario role-play (e.g. *"be my chemistry teacher and quiz me"*) and to switch the AI's voice.
- **Archive** important chats with the 📥 icon. Only archived chats are remembered — they power personalized practice and let your tutor build a real picture of what you know.

### 中文
**标题:** AI实时辅导

打字、语音、图片提问——AI 秒回。

- **聊天里直接练** — 基于当前话题一键生成练习，不用翻菜单。
- 点 **智能学习** 进入互动 AI 视频课，针对你卡住的点直接讲。
- 让 AI 画 **图表** —— 抽象概念瞬间变直观。
- ⋯ 菜单 → **实时对话模式**，免提语音 + 场景模拟（如*"扮演化学老师抽考我"*），也可切换 AI 声音。
- 用 📥 图标 **存档** 重要对话——只有存档的对话会被记住，它们驱动个性化练习，让 AI 真正了解你。

---

## ② Snap Homework · `camera.fill`

> **Position:** Quick Actions card 2 · **Action:** opens `.grader` tab

### EN
**Title:** Snap homework — graded in seconds

Photo any worksheet (1–5 pages). AI grades each question with step-by-step solutions written for your grade.

- Toggle the **Deep** button to switch from Fast to thinking-tier reasoning — like having a senior tutor on the hard ones.
- Wrong answers flow into Mistake Review, where the AI **smart-organizes** them.
- Tap any graded question to **ask the AI a follow-up**.
- **Save as a digital workbook** — your paper homework becomes a long-lived, shareable digital version with every question smart-parsed.

### 中文
**标题:** 拍照批改作业

拍下任何作业（1–5 页）——AI 按你的年级逐题批改，给步骤化解答。

- 切换 **Deep** 按钮，从快速模式换成思考模型——难题相当于换了位资深老师。
- 错题进入错题本，AI **智能归类**。
- 点任意批改后的题，**直接追问 AI**。
- **存为电子作业本** — 把纸质作业变成长期保存、可分享的电子版，每道题智能解析归档。

---

## ③ Practice · `pencil.and.list.clipboard`

> **Position:** Quick Actions card 3 · **Action:** opens question generation flow

### EN
**Title:** Practice that targets you

Generated for **your** grade, learning style, and weak spots — not a generic worksheet.

- **Daily Challenge** — 3 fresh questions every day, hand-tuned for your level.
- **Real question banks** from leading sources (textbook publishers, AMC archives, curated educational sets), filtered for your subjects and weak spots.
- **Three smart modes:** Random · From your Mistakes · From a Saved Chat.
- **All your practice sessions live here** — auto-saved as PDFs you can share, print, or re-attempt anytime.

### 中文
**标题:** 为你量身定制的练习

按 **你的** 年级、学习风格、薄弱点生成——不是千篇一律的题。

- **每日挑战** — 每天 3 道新鲜题，按你的水平手工调过。
- **真实题库** — 来自权威来源（教材出版社、AMC 题库、精选题集），按学科和薄弱点筛选。
- **三种智能模式：** 随机 · 错题驱动 · 从保存的对话生成。
- **所有练习记录都在这里** — 自动存为 PDF，可随时分享、打印、再做。

---

## ④ Suggested Todos · (torn-notebook section)

> **Position:** middle of home screen, between Quick Actions and More Features
> **Action:** each todo routes to its matching feature

### EN
**Title:** Your daily plan, AI-curated

Refreshes every day with the most useful things to do **right now**.

- Pulled from your real data: weak topics, abandoned practice, untouched homework, expiring streaks.
- **One tap to act** — each card jumps straight to the right place.
- **Swipe to dismiss** what doesn't fit; tap refresh to regenerate.
- The more you complete, the smarter tomorrow's list gets.

### 中文
**标题:** 每日 AI 学习清单

每天刷新，推荐当下 **最该做的事**。

- 来自你的真实数据：薄弱知识点、未完成练习、新作业、即将断的连击。
- **一键直达** — 每条卡片直接跳到对应功能。
- **左滑取消** 不适合今天的；点刷新换一组。
- 完成越多，明天的清单越精准。

---

## ⑤ Mistake Review · `xmark.circle.fill`

> **Position:** More Features section · **Action:** opens `MistakeReviewView`

### EN
**Title:** Every mistake, organized

Every wrong answer lands here, auto-grouped by subject and topic.

- AI labels each error type so you know what to fix, not just what you missed.
- Tap any mistake to retry it solo, or hit **"Practice these"** to drill a whole batch.
- Filter by subject, error type, or time range to focus on this week.
- Powers the **"From Mistakes"** mode in Practice — the more you review, the smarter generated practice gets.

### 中文
**标题:** 错题全收录

所有错题自动按学科、知识点归类。

- AI 标注每种错误类型，让你知道该练什么，而不只是知道错了。
- 点单题重做，或点 **"集中练习"** 一次刷一组。
- 按学科、错因、时间筛选，聚焦本周。
- 驱动练习里的 **"错题驱动"** 模式——复习越多，生成的练习越精准。

---

## ⑥ Knowledge Tree · `leaf.fill`

> **Position:** More Features section · **Action:** opens `MistakeReviewView` (Knowledge Tree tab)

### EN
**Title:** Learn + practice, on a living tree

Every concept you've touched becomes a leaf. Green = mastered, gray = unexplored.

- **Learn** — tap any leaf to drop into an interactive **AI video lesson** built around that concept.
- **Practice** — generate questions directly from the video you just watched, or knowledge-based practice grounded in your tree position.
- **"Light up the tree"** auto-generates targeted practice for the gray leaves — the fastest way to round out a subject.
- Watch your math / science / language branches fill out over weeks — visible proof your studying works.

### 中文
**标题:** 学习与练习，长在一棵活树上

每个学过的知识点变成一片叶子——绿叶=掌握，灰叶=未探索。

- **学** — 点任意叶子进入针对该知识点的 **AI 互动视频课**。
- **练** — 看完视频直接生成对应练习，或基于你在知识树上的位置做知识点针对性练习。
- 点 **"点亮知识树"** 自动针对灰叶生成练习——最快补全学科。
- 看数学 / 科学 / 语文枝叶逐周变绿——学习真有效果的可视证明。

---

## ⑦ Focus Mode · `brain.head.profile`

> **Position:** More Features section · **Action:** opens `FocusView` fullscreen

### EN
**Title:** Focus 25 min, grow tomatoes

Run a Pomodoro, earn a collectible tomato. 13 types across 4 rarity tiers.

- **5 same-tier tomatoes** can be exchanged for a rarer one (Diamond, Platinum, Golden = end-game).
- Real physics garden — tomatoes pile up, roll, settle. Max 25 visible.
- Pair with focus music (changeable in settings) for an immersive deep-work block.
- Daily streak adds points and grows your garden.

### 中文
**标题:** 专注 25 分钟，收获番茄

完成一次番茄钟收获一个可收集番茄——13 种，4 个稀有等级。

- **5 个同级番茄** 可兑换更稀有的（金番茄、铂金、钻石是终极目标）。
- 真实物理引擎花园——番茄会堆叠、滚动、沉淀，最多 25 个。
- 配专注音乐（设置里可换），沉浸式深度工作。
- 每日连续完成涨积分、种番茄。

---

## ⑧ Parent Reports · `figure.2.and.child.holdinghands`

> **Position:** More Features section · **Action:** opens `ParentReportsContainerView` (parent auth)

### EN
**Title:** Weekly reports, AI-written

What your child actually studied this week — in a parent-friendly summary.

- **Subject-by-subject breakdown:** time spent, accuracy, weak areas, recommended focus.
- AI writes the summary in plain language — no jargon, real recommendations.
- **Multi-child support** — switch between siblings if you have more than one student set up.
- Reports auto-generate weekly; tap any past week to compare progress.

### 中文
**标题:** 家长每周报告 · AI 撰写

孩子这周真实学了什么——AI 写的家长版总结。

- **分学科细分：** 用时、正确率、薄弱点、下周建议重点。
- AI 用家长能读懂的话写——没有黑话，有实际建议。
- **多孩切换** — 一个家庭多个学生可分别查看。
- 每周自动生成；点过去任一周横向对比进步。

---

## ⑨ Progress · `chart.bar.fill`

> **Position:** More Features section · **Action:** navigates to `.progress` tab

### EN
**Title:** Your study story, over time

Charts that turn weeks of study into a single picture.

- **Subject breakdown** — which subjects ate time, accuracy trends, mastery growth.
- **Streak calendar** — every active day at a glance.
- **AI insights** — three personalized tips each week, written from **your** real data, not generic advice.
- Tap any chart segment to drill into the underlying questions and chats.

### 中文
**标题:** 你的学习轨迹

把几周的学习浓缩成一张图。

- **学科分析** — 每个学科花了多少时间、正确率趋势、掌握度增长。
- **连击日历** — 一眼看到所有活跃天。
- **AI 洞察** — 每周写 3 条针对 **你** 真实数据的建议，不是空话。
- 点图表任意段下钻看具体题目和对话。

---

## ⑩ Points Shop · `star.fill`

> **Position:** Header top-right ⭐ icon (badge shows unclaimed bonuses) · **Action:** opens `PointsShopView`

### EN
**Title:** Earn points, redeem rewards

Every question answered, every mistake corrected, every Pomodoro = points.

- Multiple sources stack: **daily streak bonus**, **daily challenge**, **weekly milestones**.
- Spend points on **streak freezes** (skip a day without losing your streak) and rare tomato unlocks.
- The **badge number on the ⭐ icon** = unclaimed bonuses today. Tap to collect.

### 中文
**标题:** 积分兑换中心

答题、改错、专注番茄钟——一切都涨积分。

- 多重来源叠加：**每日连击奖励**、**每日挑战**、**每周里程碑**。
- 积分换 **冻结连击卡**（请一天假不掉 streak）和稀有番茄。
- ⭐ 图标上的 **红点数字** = 今天还能领多少奖励，点开一键领取。

---

## Decisions for review

- [ ] **Length** — 10 steps is a long tour. Keep all 10, or trim?
- [ ] **Tone / voice** — production-ready feel? Or too tight in places?
- [ ] **Bullet count** — currently 3–4 per step. Cut to 3 max for tighter cards?
- [ ] **EN ↔ ZH parity** — any phrases that feel translated rather than native?
- [ ] **Per-step copy** — mark up specific edits inline above; once finalized, this becomes the source of truth wired into the code.
