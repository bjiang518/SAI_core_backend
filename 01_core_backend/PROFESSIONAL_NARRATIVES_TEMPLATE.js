/**
 * Professional Narrative Templates for Passive Reports
 * No emojis - structured, data-driven narratives for parent communication
 *
 * These templates use the enriched data from PassiveReportGenerator
 * to create comprehensive, actionable reports.
 */

function generateProfessionalNarratives(reportType, data, previousData) {
    const accuracy = (data.academic.overallAccuracy * 100).toFixed(1);
    const questions = data.questions.length;

    // Safely extract new enriched data
    const questionAnalysis = data.questionAnalysis || {};
    const conversationAnalysis = data.conversationAnalysis || {};
    const emotionalIndicators = data.emotionalIndicators || {};

    const narratives = {
        executive_summary: `
Learning Progress Summary
===================================

Dear Parent,

This ${data.questions.length >= 30 ? 'week' : 'period'} represents a snapshot of your child's learning journey. Below is a comprehensive overview of their academic engagement and progress.

OVERALL PERFORMANCE
-----------------------------------
Grade: ${calculateGrade(accuracy)}
Accuracy: ${accuracy}%
Questions Completed: ${questions}
Study Time: ${data.activity.totalMinutes} minutes
Active Days: ${data.activity.activeDays || 0}
Current Streak: ${data.streakInfo?.currentStreak || 0} days

KEY METRICS
-----------------------------------
Engagement Level: ${formatEngagement(emotionalIndicators.engagement_level)}
Confidence Level: ${formatConfidence(emotionalIndicators.confidence_level)}
Frustration Indicators: ${formatFrustration(emotionalIndicators.frustration_index)}
Mental Health Score: ${emotionalIndicators.mental_health_score}/1.0

PERFORMANCE ASSESSMENT
-----------------------------------
${accuracy >= 80 ?
    'Your child is demonstrating strong academic performance and mastery of core concepts.' :
    accuracy >= 70 ?
    'Your child is building solid foundational skills with consistent improvement.' :
    'Your child is developing learning skills. With targeted practice, progress will accelerate.'}

${questions >= 30 ?
    'The volume of practice shows strong engagement and commitment to learning.' :
    'Increasing practice frequency will accelerate skill development and confidence.'}

ENGAGEMENT PATTERNS
-----------------------------------
Total Conversations: ${conversationAnalysis.total_conversations || 0}
Average Conversation Depth: ${conversationAnalysis.avg_depth_turns || 0} exchanges
Curiosity Indicators: ${conversationAnalysis.curiosity_indicators || 0} instances
Learning Approach: ${conversationAnalysis.curiosity_ratio > 50 ? 'Highly inquisitive' : 'Practical-focused'}

NEXT STEPS
-----------------------------------
See detailed reports below for subject-specific insights and personalized recommendations.
        `.trim(),

        academic_performance: `
Academic Performance Analysis
===================================

PERFORMANCE OVERVIEW
-----------------------------------
Total Questions Answered: ${questions}
Overall Accuracy: ${accuracy}%

SUBJECT BREAKDOWN
-----------------------------------
${Object.entries(data.subjects).map(([subject, metrics]) => {
    const subjectAccuracy = (metrics.accuracy * 100).toFixed(0);
    const performance = subjectAccuracy >= 80 ? 'Strong' : subjectAccuracy >= 70 ? 'Solid' : 'Developing';
    return `${subject}
  • Accuracy: ${subjectAccuracy}%
  • Questions: ${metrics.totalQuestions}
  • Assessment: ${performance}`;
}).join('\n\n')}

QUESTION TYPE ANALYSIS
-----------------------------------
${questionAnalysis.by_type ? Object.entries(questionAnalysis.by_type).map(([type, metrics]) => {
    const typeLabel = type === 'homework_image' ? 'Homework Images' : 'Text Questions';
    return `${typeLabel}
  • Count: ${metrics.count}
  • Accuracy: ${metrics.accuracy}%
  • Errors: ${metrics.incorrect || 0}`;
}).join('\n\n') : 'Analysis pending...'}

INTERPRETATION
-----------------------------------
${accuracy >= 80 ?
    'Your child demonstrates strong conceptual understanding and is ready for more advanced material.' :
    accuracy >= 70 ?
    'Your child shows solid understanding of fundamentals and would benefit from targeted practice in specific areas.' :
    'Your child is building foundational skills. Focused review of key concepts will strengthen overall performance.'}

RECOMMENDATIONS
-----------------------------------
${accuracy >= 80 ?
    '• Challenge with more complex problems in strong subjects\n• Begin exploring advanced topics\n• Maintain current study routine' :
    accuracy >= 70 ?
    '• Review foundational concepts in weaker subjects\n• Practice problem-solving strategies\n• Schedule regular study sessions' :
    '• Focus on core concepts first\n• Work through concepts step-by-step\n• Use tutoring resources for clarification'}
        `.trim(),

        learning_behavior: `
Learning Behavior & Study Habits
===================================

STUDY PATTERN ANALYSIS
-----------------------------------
Total Study Time: ${data.activity.totalMinutes} minutes
Active Days: ${data.activity.activeDays || 0} out of 7
Average Questions per Day: ${(questions / Math.max(1, data.activity.activeDays || 1)).toFixed(1)}
Questions per Session: ~${(questions / Math.max(1, data.activity.activeDays || 1)).toFixed(0)}

CONSISTENCY ASSESSMENT
-----------------------------------
${data.activity.activeDays >= 5 ?
    'Excellent Consistency: Your child has established a regular study routine.' :
    data.activity.activeDays >= 3 ?
    'Moderate Consistency: Study habits are developing with room for improvement.' :
    'Developing Consistency: More frequent study sessions would accelerate progress.'}

ENGAGEMENT DURATION
-----------------------------------
${data.activity.totalMinutes >= 120 ?
    'High Commitment: Extended study time demonstrates strong dedication to learning.' :
    data.activity.totalMinutes >= 60 ?
    'Solid Effort: Regular study sessions show meaningful engagement.' :
    'Developing Habit: Building a consistent study practice will improve results.'}

SESSION EFFICIENCY
-----------------------------------
${accuracy >= 75 ?
    'Your child demonstrates productive focus and effective use of study time.' :
    'Session effectiveness can be improved through structured learning techniques and reduced distractions.'}

RECOMMENDATIONS
-----------------------------------
${data.activity.activeDays < 5 ?
    '• Set specific study times each day\n• Create a consistent schedule\n• Use reminders for study sessions' :
    '• Maintain current study routine\n• Explore varied learning materials\n• Challenge yourself with new topics'}
        `.trim(),

        motivation_emotional: `
Engagement & Emotional Development
===================================

ENGAGEMENT METRICS
-----------------------------------
Questions Attempted: ${questions}
Conversations Initiated: ${data.conversations.length}
Conversation Depth: ${conversationAnalysis.avg_depth_turns || 0} exchanges on average

CURIOSITY & LEARNING STYLE
-----------------------------------
Curiosity Indicators: ${conversationAnalysis.curiosity_indicators || 0} instances
Curiosity Ratio: ${conversationAnalysis.curiosity_ratio || 0}%
${emotionalIndicators.engagement_level > 0.7 ? 'Assessment: Highly engaged learner' : 'Assessment: Moderately engaged learner'}

INTERACTION PATTERNS
-----------------------------------
${data.conversations.length >= 5 ?
    'Your child actively seeks clarification and engages in extended learning conversations.\nThis indicates genuine curiosity and desire for deep understanding.' :
    data.conversations.length > 0 ?
    'Your child occasionally seeks clarification through conversations.\nMore interactive engagement could deepen learning.' :
    'Your child primarily works independently.\nEncouraging more dialogue could enhance understanding.'}

EMOTIONAL INDICATORS
-----------------------------------
Confidence Level: ${(emotionalIndicators.confidence_level * 100).toFixed(0)}%
Frustration Index: ${(emotionalIndicators.frustration_index * 100).toFixed(0)}%
Burnout Risk: ${emotionalIndicators.burnout_risk > 0 ? 'Moderate - Monitor closely' : 'Low - Healthy engagement'}

MENTAL HEALTH ASSESSMENT
-----------------------------------
Composite Score: ${(emotionalIndicators.mental_health_score * 100).toFixed(0)}/100

${emotionalIndicators.mental_health_score > 0.75 ?
    'Strong mental health indicators. Your child shows healthy engagement with learning.' :
    emotionalIndicators.mental_health_score > 0.5 ?
    'Moderate engagement levels. Encourage more interactive learning experiences.' :
    'Lower engagement indicators. Consider discussing learning goals and addressing any concerns.'}

RECOMMENDATIONS
-----------------------------------
${data.conversations.length < 3 ?
    '• Encourage asking questions when confused\n• Use tutoring resources for clarification\n• Practice explaining concepts aloud' :
    '• Maintain current interactive learning style\n• Explore new topics through dialogue\n• Challenge yourself with complex questions'}
        `.trim(),

        progress_trajectory: `
Progress Trajectory & Growth Analysis
===================================

CURRENT PERIOD PERFORMANCE
-----------------------------------
Accuracy: ${accuracy}%
Questions Completed: ${questions}
Study Time: ${data.activity.totalMinutes} minutes
Active Study Days: ${data.activity.activeDays}

PERFORMANCE TREND
-----------------------------------
${data.progress && data.progress.trend ? `
Trend Direction: ${data.progress.trend === 'improving' ? 'Improving' : data.progress.trend === 'declining' ? 'Declining' : 'Stable'}
First Half Accuracy: ${(data.progress.firstHalfAccuracy * 100).toFixed(1)}%
Second Half Accuracy: ${(data.progress.secondHalfAccuracy * 100).toFixed(1)}%
` : 'Insufficient data for trend analysis'}

TRAJECTORY ASSESSMENT
-----------------------------------
${accuracy >= 75 ?
    'Your child is on an upward trajectory and demonstrates readiness for more advanced material.' :
    accuracy >= 70 ?
    'Your child is building momentum with consistent effort. Progress is steady and sustainable.' :
    'Your child is in the early stages of skill development. Targeted practice will accelerate growth.'}

SUBJECT-SPECIFIC PROGRESS
-----------------------------------
${Object.entries(data.subjects)
    .sort(([,a], [,b]) => b.accuracy - a.accuracy)
    .map(([subject, metrics]) => {
        const acc = (metrics.accuracy * 100).toFixed(0);
        return `${subject}: ${acc}%`;
    }).join(' | ')}

GROWTH INDICATORS
-----------------------------------
• Questions completed this period: ${questions}
• Study consistency maintained
• ${data.conversations.length > 0 ? 'Engaging with tutoring resources' : 'Primarily self-directed learning'}

RECOMMENDATIONS
-----------------------------------
${accuracy >= 80 ?
    '• Introduce more challenging problems\n• Explore advanced topics\n• Maintain current study pattern' :
    '• Continue building skills with consistent practice\n• Review difficult concepts\n• Celebrate milestones achieved'}
        `.trim(),

        social_learning: `
AI Tutoring & Learning Resource Usage
===================================

TUTORING ENGAGEMENT
-----------------------------------
Total Conversations: ${data.conversations.length}
Average Conversation Depth: ${conversationAnalysis.avg_depth_turns || 0} exchanges
${data.conversations.length > 0 ? `Curiosity Questions: ${conversationAnalysis.curiosity_indicators || 0}` : 'No conversations recorded'}

LEARNING RESOURCE UTILIZATION
-----------------------------------
${data.conversations.length >= 5 ?
    'Your child actively uses tutoring resources for clarification and deeper understanding.\nThis demonstrates initiative and curiosity-driven learning.' :
    data.conversations.length > 0 ?
    'Your child uses tutoring resources occasionally.\nIncreasing resource usage could accelerate learning.' :
    'Your child primarily works independently.\nUsing tutoring resources could provide additional support.'}

QUESTION PATTERNS
-----------------------------------
${data.questionAnalysis.by_type ?
    Object.entries(data.questionAnalysis.by_type)
        .map(([type, metrics]) => {
            const typeLabel = type === 'homework_image' ? 'Homework Images' : 'Text Questions';
            return `${typeLabel}: ${metrics.count} questions`;
        }).join('\n') :
    'Analysis in progress'}

CRITICAL THINKING DEVELOPMENT
-----------------------------------
${data.conversations.length > 0 && conversationAnalysis.curiosity_ratio > 40 ?
    'Your child demonstrates strong critical thinking through exploratory questions.' :
    'Critical thinking skills are developing. Encourage deeper questioning.'}

${conversationAnalysis.avg_depth_turns > 4 ?
    'Extended conversations indicate thoughtful engagement with concepts.' :
    'Conversation depth could be increased through more interactive learning.'}

RECOMMENDATIONS
-----------------------------------
${data.conversations.length < 5 ?
    '• Ask questions when uncertain\n• Use tutoring for concept clarification\n• Explore why things work, not just how' :
    '• Continue active engagement with tutoring\n• Challenge yourself with complex questions\n• Explain concepts to others for deeper understanding'}
        `.trim(),

        risk_opportunity: `
Risk Assessment & Growth Opportunities
===================================

PERFORMANCE CONCERNS
-----------------------------------
${accuracy < 60 ?
    'Accuracy Below Target: ${accuracy}%\nRecommendation: Focus on foundational concepts before advancing.' :
    accuracy < 70 ?
    'Moderate Accuracy: ${accuracy}%\nRecommendation: Targeted practice in weak areas will improve performance.' :
    'Performance Level: Satisfactory\nNo major concerns identified.'}

${data.activity.activeDays < 3 ?
    '\nStudy Frequency: Limited engagement\nRecommendation: Increase study frequency for better retention.' :
    '\nStudy Frequency: Adequate'}

${emotionalIndicators.frustration_index > 0.3 ?
    '\nFrustration Indicators: Detected in conversations\nRecommendation: Break topics into smaller steps, celebrate small wins.' :
    '\nFrustration Level: Low'}

STRENGTHS IDENTIFIED
-----------------------------------
${accuracy >= 80 ? 'Strong Academic Performance: Above-average mastery demonstrated' : ''}
${data.activity.totalMinutes >= 90 ? 'High Commitment: Extended study time shows dedication' : ''}
${questions >= 50 ? 'High Engagement: Substantial practice volume completed' : ''}
${data.conversations.length >= 5 ? 'Active Learning: Uses tutoring resources effectively' : ''}

GROWTH OPPORTUNITIES
-----------------------------------
${accuracy >= 80 ?
    '• Challenge with advanced material\n• Explore enrichment topics\n• Mentor others in their learning' :
    '• Build consistency through regular practice\n• Focus on understanding core concepts\n• Use tutoring resources strategically'}

NEXT PRIORITY
-----------------------------------
${accuracy < 70 ? 'Strengthen foundational skills' : 'Build on current momentum'}
        `.trim(),

        action_plan: `
Personalized Learning Action Plan
===================================

ASSESSMENT SUMMARY
-----------------------------------
Current Grade: ${calculateGrade(accuracy)}
Accuracy Level: ${accuracy}%
Engagement: ${formatEngagement(emotionalIndicators.engagement_level)}
Study Consistency: ${data.activity.activeDays}/7 days active

PRIMARY OBJECTIVES
-----------------------------------
${accuracy < 70 ?
    'Objective 1: Build Foundational Skills\n• Focus on core concepts\n• Daily practice (20-30 minutes)\n• Seek clarification for difficult topics' :
    'Objective 1: Maintain Momentum\n• Continue current study routine\n• Gradually increase difficulty\n• Explore new topics'}

${data.activity.activeDays < 5 ?
    '\nObjective 2: Establish Study Consistency\n• Set fixed study times\n• Create a dedicated study space\n• Use reminder notifications' :
    '\nObjective 2: Deepen Understanding\n• Explore advanced concepts\n• Connect learning across subjects\n• Apply knowledge to real-world problems'}

${data.conversations.length < 3 ?
    '\nObjective 3: Increase Learning Support Usage\n• Ask questions when confused\n• Use tutoring for clarification\n• Practice explaining concepts' :
    '\nObjective 3: Maximize Learning Resources\n• Continue engaging with tutoring\n• Challenge yourself with complex questions\n• Teach others to solidify understanding'}

RECOMMENDED STRATEGIES
-----------------------------------
Study Techniques:
${accuracy < 70 ?
    '• Spaced repetition for core concepts\n• Practice problems with solutions\n• Concept mapping for connections' :
    '• Teach-back method for deeper understanding\n• Varied problem-solving approaches\n• Application to real scenarios'}

Support Resources:
• AI tutor for question clarification
• Subject-specific practice materials
• Progress tracking and feedback

CELEBRATION & MILESTONES
-----------------------------------
This Period's Achievements:
${accuracy >= 75 ? '• Achieved solid accuracy level' : '• Progressed in skill development'}
${questions >= 30 ? '• Completed substantial practice volume' : ''}
${data.activity.activeDays >= 5 ? '• Established regular study habit' : ''}
${data.conversations.length >= 5 ? '• Actively engaged with learning resources' : ''}

NEXT PERIOD GOALS
-----------------------------------
Short-term (Next 1-2 weeks):
${accuracy < 70 ?
    '• Review foundational concepts in weak areas\n• Complete 15-20 minutes of daily practice\n• Identify 2-3 specific topics for focus' :
    '• Introduce one new advanced topic\n• Increase challenge level gradually\n• Explore cross-subject connections'}

Medium-term (Next month):
${accuracy < 70 ?
    '• Achieve 70%+ accuracy\n• Build 5-day study streak\n• Complete 50+ practice questions' :
    '• Reach target accuracy level\n• Maintain consistent study habit\n• Deepen understanding across subjects'}

CONVERSATION STARTERS FOR PARENTS
-----------------------------------
${accuracy >= 75 ?
    '"You\'re doing great in your studies! What\'s your favorite topic so far?"' :
    '"How are you feeling about school? What subjects are most challenging?"'}

"Can you explain one concept you learned today?"
"What would you like to explore next?"
"How can I support your learning?"

SUPPORT & COMMUNICATION
-----------------------------------
• Weekly check-ins on progress
• Celebrate weekly milestones
• Adjust plan based on progress
• Communicate with educators if needed
        `.trim()
    };

    return narratives[reportType] || 'Report type not found';
}

// Helper functions
function calculateGrade(accuracy) {
    const acc = parseFloat(accuracy);
    if (acc >= 95) return 'A+';
    if (acc >= 90) return 'A';
    if (acc >= 85) return 'A-';
    if (acc >= 80) return 'B+';
    if (acc >= 75) return 'B';
    if (acc >= 70) return 'B-';
    if (acc >= 65) return 'C+';
    if (acc >= 60) return 'C';
    return 'C-';
}

function formatEngagement(level) {
    if (level > 0.8) return 'Highly Engaged';
    if (level > 0.6) return 'Moderately Engaged';
    if (level > 0.4) return 'Developing Engagement';
    return 'Low Engagement';
}

function formatConfidence(level) {
    return `${(level * 100).toFixed(0)}%`;
}

function formatFrustration(index) {
    if (index < 0.2) return 'Low';
    if (index < 0.5) return 'Moderate';
    return 'Elevated';
}

module.exports = { generateProfessionalNarratives };
