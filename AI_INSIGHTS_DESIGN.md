# AI-Powered Insights Design for Passive Reports

**Date**: February 13, 2026
**AI Model**: OpenAI GPT-4o
**Goal**: Embed personalized AI insights into each of the 4 passive reports

---

## Overview

Each report will have **2-4 AI-powered insight sections** that provide personalized, context-aware analysis beyond raw data aggregation.

### AI Insight Placement Strategy

**Principle**: Place AI insights where interpretation and personalized recommendations add the most value.

---

## 1. Activity Report (📊)

### Current Sections:
- Header with key metrics (Questions, Chats, Active Days, Time Spent)
- Subject Breakdown (pie/bar charts)
- Week-over-Week Comparison
- Summary

### **AI Insights to Add**:

#### AI Insight 1: **Learning Pattern Analysis** (After Subject Breakdown)
**Input Signals**:
- Questions per subject distribution
- Active days pattern
- Time of day distribution
- Week-over-week activity change

**AI Prompt Focus**:
```
Analyze this student's learning patterns:
- Is their activity consistent or sporadic?
- Which subjects get more attention and why might that be?
- Are there concerning patterns (e.g., cramming, avoidance)?
- What does their activity rhythm suggest about their learning style?

Provide 2-3 specific, actionable insights for parents.
```

**Expected Output**: 2-3 bullet points with interpretation + recommendation

---

#### AI Insight 2: **Engagement Quality Assessment** (After Week-over-Week Comparison)
**Input Signals**:
- Question count vs chat count ratio
- Study session lengths
- Time distribution across subjects
- Handwriting quality (if available)

**AI Prompt Focus**:
```
Assess the quality of engagement:
- Is the student just completing homework or truly learning?
- Does the question/chat ratio suggest deep thinking or surface-level work?
- Are study sessions appropriately paced or too rushed/too long?
- What does this tell parents about focus and engagement?

Provide specific indicators of engagement quality.
```

**Expected Output**: Quality rating + 2-3 indicators + 1 recommendation

---

#### AI Insight 3: **Study Optimization Recommendations** (Monthly Reports Only, After Session Insights)
**Input Signals**:
- Weekly breakdown data
- Day of week heatmap
- Peak performance windows
- Session patterns

**AI Prompt Focus**:
```
Based on this student's activity patterns:
- What is their optimal study schedule?
- Which subjects should be studied when?
- Are there untapped opportunities (e.g., underutilized weekend time)?
- How can parents help optimize the study routine?

Provide 3-4 concrete scheduling recommendations.
```

**Expected Output**: 3-4 specific scheduling recommendations

---

## 2. Areas of Improvement Report (🎯)

### Current Sections:
- Header with mistake metrics
- Subject-specific weaknesses
- Error pattern breakdown
- Concrete action items

### **AI Insights to Add**:

#### AI Insight 1: **Root Cause Analysis** (After Subject Weaknesses)
**Input Signals**:
- Mistake types distribution
- Subject-specific error patterns
- Help-seeking behavior (chat conversations)
- Error trend (improving/worsening)

**AI Prompt Focus**:
```
Analyze the root causes of this student's mistakes:
- Are mistakes due to lack of understanding, carelessness, or incomplete work?
- Which subjects have fundamental gaps vs minor issues?
- Does the student seek help appropriately?
- What underlying skills (e.g., attention to detail, reading comprehension) need work?

Identify 2-3 root causes parents should address.
```

**Expected Output**: 2-3 root causes with evidence + priority level

---

#### AI Insight 2: **Progress Trajectory** (After Error Patterns)
**Input Signals**:
- Week-over-week mistake comparison
- Error type trends
- Concept mastery data
- Subject accuracy trends

**AI Prompt Focus**:
```
Assess progress trajectory:
- Is the student improving, plateauing, or regressing?
- Which areas show improvement and which need intervention?
- At this rate, what can we expect in 4-8 weeks?
- Are current strategies working?

Provide realistic expectations and intervention recommendations.
```

**Expected Output**: Trajectory assessment + timeline + strategic recommendation

---

#### AI Insight 3: **Personalized Practice Plan** (End of Report)
**Input Signals**:
- Top 3 weakness areas
- Student age
- Error patterns
- Handwriting/concept weakness data

**AI Prompt Focus**:
```
Create a personalized practice plan:
- What specific skills to practice this week?
- How much time per day/week?
- What resources or activities would help?
- How can parents support practice at home?

Provide a concrete weekly practice schedule.
```

**Expected Output**: Weekly practice schedule with specific activities

---

## 3. Mental Health & Wellbeing Report (💭)

### Current Sections:
- Learning Attitude assessment
- Focus Capability assessment
- Emotional Wellbeing (red flags detection)
- Summary & Recommendations

### **AI Insights to Add**:

#### AI Insight 1: **Behavioral Signals Interpretation** (After Learning Attitude)
**Input Signals**:
- Active days count
- Help-seeking patterns
- Conversation tone/content
- Red flags detected
- Student age

**AI Prompt Focus**:
```
Interpret behavioral and emotional signals:
- What does their activity pattern reveal about motivation?
- Are there signs of frustration, anxiety, or burnout?
- How does their help-seeking behavior reflect confidence?
- Age-appropriate context: What's normal vs concerning for age X?

Provide nuanced interpretation of observed behaviors.
```

**Expected Output**: 3-4 behavioral interpretations with context

---

#### AI Insight 2: **Emotional Wellbeing Assessment** (After Red Flags Section)
**Input Signals**:
- Red flag count and types
- Session engagement quality
- Time pressure indicators
- Subject-specific stress signals

**AI Prompt Focus**:
```
Assess emotional wellbeing and stress:
- Is the student coping well or showing stress?
- Which subjects or situations cause the most stress?
- Are there signs of academic pressure or perfectionism?
- What protective factors (resilience, positive attitude) are present?

Provide holistic emotional health assessment.
```

**Expected Output**: Wellbeing status + stress factors + protective factors

---

#### AI Insight 3: **Parent Communication Strategies** (End of Report)
**Input Signals**:
- Overall mental health status
- Identified concerns
- Student age and developmental stage

**AI Prompt Focus**:
```
Recommend age-appropriate communication strategies:
- How should parents discuss challenges with their child?
- What questions to ask to understand the student's perspective?
- When to offer help vs let them struggle productively?
- How to balance support with independence?

Provide conversation starters and communication tips.
```

**Expected Output**: 3-4 specific conversation strategies

---

## 4. Summary Report (📋)

### Current Sections:
- Executive summary of all 3 reports
- Key highlights
- Top priorities

### **AI Insights to Add**:

#### AI Insight 1: **Holistic Student Profile** (After Summary)
**Input Signals**:
- Activity data (all metrics)
- Improvement areas data
- Mental health data
- Student age

**AI Prompt Focus**:
```
Create a holistic student profile:
- What are this student's strengths and learning style?
- How do activity, performance, and wellbeing connect?
- What's the "big picture" story of this student's learning?
- What opportunities are being maximized or missed?

Provide integrated analysis across all dimensions.
```

**Expected Output**: 4-5 bullet profile synthesis

---

#### AI Insight 2: **Priority Action Plan** (End of Report)
**Input Signals**:
- Top areas of improvement
- Mental health concerns
- Activity optimization opportunities
- Current trajectory

**AI Prompt Focus**:
```
Synthesize top 3-5 priorities for the next period:
- What should parents focus on FIRST?
- Which issues are urgent vs important but not urgent?
- What quick wins are available?
- What long-term investments are needed?

Provide prioritized action plan with clear next steps.
```

**Expected Output**: 3-5 prioritized action items with timeframes

---

## Implementation Architecture

### Service Layer: `openai-insights-service.js`

```javascript
class OpenAIInsightsService {
    constructor() {
        this.openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
        this.model = 'gpt-4o';
        this.cache = new Map(); // Simple in-memory cache
    }

    async generateInsight(type, signals, context) {
        // Generate cache key
        const cacheKey = this.generateCacheKey(type, signals);

        // Check cache
        if (this.cache.has(cacheKey)) {
            return this.cache.get(cacheKey);
        }

        // Build prompt
        const prompt = this.buildPrompt(type, signals, context);

        // Call GPT-4o
        const response = await this.openai.chat.completions.create({
            model: this.model,
            messages: [
                { role: 'system', content: this.getSystemPrompt(type) },
                { role: 'user', content: prompt }
            ],
            temperature: 0.7,
            max_tokens: 500
        });

        const insight = response.choices[0].message.content;

        // Cache result
        this.cache.set(cacheKey, insight);

        return insight;
    }
}
```

### Integration Points

Each report generator will:
1. Calculate metrics (existing code)
2. Call `openaiInsightsService.generateInsight()` 2-4 times per report
3. Inject AI insights into HTML at designated sections

### Cache Strategy

**Cache Key Format**: `{report_type}:{insight_type}:{user_id}:{period}:{start_date}`

**Example**: `activity:learning_pattern:7b5ff4f8:monthly:2026-01-14`

**Cache Invalidation**:
- Cache cleared daily
- Batch ID included in cache key to prevent cross-batch pollution

---

## Cost & Performance Estimates

### Per Report Generation (4 reports × 2-3 insights each):
- **AI Calls**: 10-12 GPT-4o requests
- **Input Tokens**: ~300-500 tokens per request = 3,000-6,000 tokens total
- **Output Tokens**: ~200-300 tokens per request = 2,000-3,600 tokens total
- **Cost**: ~$0.15-0.25 per full report batch (GPT-4o pricing: $2.50/1M input, $10/1M output)
- **Time**: ~15-30 seconds for AI generation (with parallel requests)

### Caching Benefits:
- Regenerating same period = $0 (cached)
- Testing/debugging = Minimal cost

---

## Rollout Plan

1. **Phase 1**: Implement OpenAI service wrapper (today)
2. **Phase 2**: Add 2 AI insights to Activity Report (today)
3. **Phase 3**: Add 2 AI insights to Areas of Improvement (today)
4. **Phase 4**: Add 3 AI insights to Mental Health (tomorrow)
5. **Phase 5**: Add 2 AI insights to Summary (tomorrow)
6. **Phase 6**: Test with real data, tune prompts (tomorrow)
7. **Phase 7**: Deploy to production (after validation)

---

## Success Metrics

- [ ] AI insights generate within 30 seconds total
- [ ] Insights are specific and actionable (not generic)
- [ ] Cost per report batch < $0.30
- [ ] Cache hit rate > 70% for testing scenarios
- [ ] Parents find insights valuable (user feedback)
