const express = require('express');
const { db } = require('../utils/railway-database');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

// Achievement definitions
const ACHIEVEMENT_DEFINITIONS = {
  first_question: {
    id: 'first_question',
    name: 'First Steps',
    description: 'Answer your first question',
    icon: 'questionmark.circle.fill',
    category: 'milestone',
    xp_reward: 25,
    rarity: 'common'
  },
  daily_warrior_3: {
    id: 'daily_warrior_3',
    name: '3-Day Warrior',
    description: 'Maintain a 3-day study streak',
    icon: 'flame.fill',
    category: 'streak',
    xp_reward: 50,
    rarity: 'common'
  },
  daily_warrior_7: {
    id: 'daily_warrior_7',
    name: 'Weekly Champion',
    description: 'Maintain a 7-day study streak',
    icon: 'flame.fill',
    category: 'streak',
    xp_reward: 150,
    rarity: 'rare'
  },
  perfectionist: {
    id: 'perfectionist',
    name: 'Perfectionist',
    description: 'Get 100% accuracy in a session',
    icon: 'target',
    category: 'accuracy',
    xp_reward: 75,
    rarity: 'rare'
  },
  speed_learner: {
    id: 'speed_learner',
    name: 'Speed Learner',
    description: 'Answer 10 questions in one day',
    icon: 'bolt.fill',
    category: 'volume',
    xp_reward: 100,
    rarity: 'rare'
  },
  math_master: {
    id: 'math_master',
    name: 'Math Master',
    description: 'Answer 25 math questions correctly',
    icon: 'plus.forwardslash.minus',
    category: 'subject',
    xp_reward: 200,
    rarity: 'epic'
  }
};

// XP calculation function
function calculateXP(isCorrect, subject, streak = 1, bonusMultiplier = 1.0) {
  let baseXP = 10; // Base XP for any question
  
  if (isCorrect) {
    baseXP += 15; // Bonus for correct answer
  }
  
  // Subject multipliers
  const subjectMultipliers = {
    'Mathematics': 1.2,
    'Physics': 1.2,
    'Chemistry': 1.1,
    'Biology': 1.0,
    'English': 1.0
  };
  
  const subjectMultiplier = subjectMultipliers[subject] || 1.0;
  
  // Streak bonus (up to 2x for 10+ day streaks)
  const streakMultiplier = Math.min(1 + (streak * 0.1), 2.0);
  
  return Math.round(baseXP * subjectMultiplier * streakMultiplier * bonusMultiplier);
}

// Check and award achievements
async function checkAchievements(userId, progressData) {
  const newAchievements = [];
  
  try {
    const {
      questionsAnswered = 0,
      correctAnswers = 0,
      streak = 0,
      totalQuestions = 0,
      subject = ''
    } = progressData;
    
    // First question achievement
    if (totalQuestions === 1) {
      const achievement = await db.addUserAchievement(userId, ACHIEVEMENT_DEFINITIONS.first_question);
      if (achievement) newAchievements.push(achievement);
    }
    
    // Streak achievements
    if (streak === 3) {
      const achievement = await db.addUserAchievement(userId, ACHIEVEMENT_DEFINITIONS.daily_warrior_3);
      if (achievement) newAchievements.push(achievement);
    }
    
    if (streak === 7) {
      const achievement = await db.addUserAchievement(userId, ACHIEVEMENT_DEFINITIONS.daily_warrior_7);
      if (achievement) newAchievements.push(achievement);
    }
    
    // Perfect accuracy achievement
    if (questionsAnswered > 0 && correctAnswers === questionsAnswered && questionsAnswered >= 5) {
      const achievement = await db.addUserAchievement(userId, ACHIEVEMENT_DEFINITIONS.perfectionist);
      if (achievement) newAchievements.push(achievement);
    }
    
    // Speed learner achievement
    if (questionsAnswered >= 10) {
      const achievement = await db.addUserAchievement(userId, ACHIEVEMENT_DEFINITIONS.speed_learner);
      if (achievement) newAchievements.push(achievement);
    }
    
    // Subject-specific achievements
    if (subject === 'Mathematics' && correctAnswers >= 25) {
      const achievement = await db.addUserAchievement(userId, ACHIEVEMENT_DEFINITIONS.math_master);
      if (achievement) newAchievements.push(achievement);
    }
    
  } catch (error) {
    console.error('Error checking achievements:', error);
  }
  
  return newAchievements;
}

// @desc    Get enhanced progress summary
// @route   GET /api/progress/enhanced
// @access  Private
router.get('/enhanced', authenticate, async (req, res) => {
  try {
    const userId = req.user.user_id;
    
    console.log(`📊 Getting enhanced progress for user: ${userId}`);
    
    // Get comprehensive progress summary
    const progressSummary = await db.getUserProgressSummary(userId);
    
    // Get heatmap data for the last 90 days
    const heatmapData = await db.getDailyProgressHeatmap(userId, 90);
    
    // Get subject breakdown
    const subjectProgress = await db.getSubjectProgress(userId);
    
    // Get recent achievements
    const recentAchievements = await db.getUserAchievements(userId, 10);
    
    const enhancedProgress = {
      // Today's progress
      today: {
        questions_answered: progressSummary.today_questions || 0,
        correct_answers: progressSummary.today_correct || 0,
        xp_earned: progressSummary.today_xp || 0,
        accuracy: progressSummary.today_questions > 0 
          ? Math.round((progressSummary.today_correct / progressSummary.today_questions) * 100) 
          : 0
      },
      
      // Overall stats
      overall: {
        current_level: progressSummary.current_level || 1,
        total_xp: progressSummary.total_xp || 0,
        xp_to_next_level: progressSummary.xp_to_next_level || 100,
        xp_progress: progressSummary.total_xp > 0 
          ? Math.min((progressSummary.total_xp / progressSummary.xp_to_next_level) * 100, 100)
          : 0
      },
      
      // Streak info
      streak: {
        current: progressSummary.current_streak || 0,
        longest: progressSummary.longest_streak || 0,
        flame_level: Math.min(Math.floor(progressSummary.current_streak / 3), 4) // 0-4 flame levels
      },
      
      // Weekly stats
      week: {
        days_active: progressSummary.week_days_active || 0,
        total_questions: progressSummary.week_questions || 0,
        total_correct: progressSummary.week_correct || 0,
        accuracy: progressSummary.week_accuracy ? Math.round(progressSummary.week_accuracy * 100) : 0
      },
      
      // Daily goal
      daily_goal: {
        target: progressSummary.daily_goal_target || 5,
        current: progressSummary.daily_goal_current || 0,
        completed: progressSummary.daily_goal_completed || false,
        progress_percentage: progressSummary.daily_goal_target > 0 
          ? Math.min((progressSummary.daily_goal_current / progressSummary.daily_goal_target) * 100, 100)
          : 0
      },
      
      // Achievement info
      achievements: {
        total_unlocked: progressSummary.total_achievements || 0,
        recent: recentAchievements.slice(0, 3), // Show top 3 recent
        available_count: Object.keys(ACHIEVEMENT_DEFINITIONS).length
      },
      
      // Subject breakdown
      subjects: subjectProgress.map(subject => ({
        name: subject.subject,
        questions: subject.total_questions,
        correct: subject.total_correct,
        accuracy: Math.round(subject.accuracy * 100),
        xp: subject.total_xp,
        proficiency: subject.proficiency_level,
        days_studied: subject.days_studied
      })),
      
      // Activity heatmap
      heatmap: heatmapData.map(day => ({
        date: day.date,
        activity_level: day.activity_level,
        questions: day.questions_answered,
        xp: day.xp_earned,
        goal_completed: day.daily_goal_completed
      })),
      
      // Motivational message from Adam
      ai_message: generateMotivationalMessage(progressSummary),
      
      // Next milestones
      next_milestones: generateNextMilestones(progressSummary)
    };
    
    console.log(`✅ Enhanced progress retrieved successfully for user ${userId}`);
    res.json({
      success: true,
      data: enhancedProgress
    });
    
  } catch (error) {
    console.error('Enhanced progress error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve enhanced progress'
    });
  }
});

// @desc    Track question answered
// @route   POST /api/progress/track-question
// @access  Private
router.post('/track-question', authenticate, async (req, res) => {
  try {
    const userId = req.user.user_id;
    const { subject, is_correct, study_time_seconds = 0 } = req.body;
    
    console.log(`📈 Tracking question for user ${userId}: ${subject}, correct: ${is_correct}`);
    
    // Get current streak
    const streakResult = await db.updateStudyStreak(userId);
    const currentStreak = streakResult.current_streak;
    
    // Calculate XP
    const xpEarned = calculateXP(is_correct, subject, currentStreak);
    const bonusXp = currentStreak > 3 ? Math.floor(xpEarned * 0.1) : 0;
    
    // Update daily progress
    const progressData = {
      questionsAnswered: 1,
      correctAnswers: is_correct ? 1 : 0,
      studyTimeMinutes: Math.ceil(study_time_seconds / 60),
      subjectsStudied: [subject],
      xpEarned: xpEarned,
      bonusXp: bonusXp
    };
    
    const dailyProgress = await db.updateDailyProgress(userId, progressData);
    
    // Update user XP and check for level up
    const levelResult = await db.updateUserXP(userId, xpEarned + bonusXp);
    const leveledUp = levelResult.leveled_up;
    
    // Update daily goal
    await db.updateDailyGoal(userId, 'questions', 1);
    
    // Check for new achievements
    const achievementData = {
      questionsAnswered: dailyProgress.questions_answered,
      correctAnswers: dailyProgress.correct_answers,
      streak: currentStreak,
      totalQuestions: dailyProgress.questions_answered, // This could be improved with actual total
      subject: subject
    };
    
    const newAchievements = await checkAchievements(userId, achievementData);
    
    // Award XP for achievements
    let achievementXP = 0;
    if (newAchievements.length > 0) {
      achievementXP = newAchievements.reduce((total, achievement) => total + (achievement.xp_reward || 0), 0);
      if (achievementXP > 0) {
        await db.updateUserXP(userId, achievementXP);
      }
    }
    
    console.log(`✅ Progress tracked: +${xpEarned} XP, ${newAchievements.length} new achievements`);
    
    res.json({
      success: true,
      data: {
        xp_earned: xpEarned,
        bonus_xp: bonusXp,
        achievement_xp: achievementXP,
        current_streak: currentStreak,
        level_up: leveledUp,
        new_level: levelResult.current_level,
        new_achievements: newAchievements,
        daily_progress: {
          questions_today: dailyProgress.questions_answered,
          correct_today: dailyProgress.correct_answers,
          xp_today: dailyProgress.xp_earned
        }
      }
    });
    
  } catch (error) {
    console.error('Track question error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to track question progress'
    });
  }
});

// Helper function to generate motivational messages
function generateMotivationalMessage(progressSummary) {
  const messages = [
    `Great job! You've answered ${progressSummary.today_questions || 0} questions today. Keep up the momentum!`,
    `Your ${progressSummary.current_streak || 0}-day streak is impressive! Let's make it even longer.`,
    `You're level ${progressSummary.current_level || 1}! Only ${progressSummary.xp_to_next_level - progressSummary.total_xp || 100} XP until the next level.`,
    `Amazing accuracy this week at ${Math.round((progressSummary.week_accuracy || 0) * 100)}%! You're really mastering the material.`,
    `You've been active ${progressSummary.week_days_active || 0} days this week. Consistency is key to success!`
  ];
  
  // Choose message based on current progress
  if (progressSummary.current_streak > 7) {
    return messages[1];
  } else if (progressSummary.today_questions > 5) {
    return messages[0];
  } else if (progressSummary.week_accuracy > 0.8) {
    return messages[3];
  } else {
    return messages[Math.floor(Math.random() * messages.length)];
  }
}

// Helper function to generate next milestones
function generateNextMilestones(progressSummary) {
  const milestones = [];
  
  // Level milestone
  if (progressSummary.xp_to_next_level) {
    milestones.push({
      type: 'level',
      title: `Reach Level ${(progressSummary.current_level || 1) + 1}`,
      progress: progressSummary.total_xp || 0,
      target: progressSummary.xp_to_next_level || 100,
      icon: 'star.fill'
    });
  }
  
  // Streak milestone
  const nextStreakTarget = Math.ceil((progressSummary.current_streak || 0) / 5) * 5 + 5;
  milestones.push({
    type: 'streak',
    title: `${nextStreakTarget}-Day Streak`,
    progress: progressSummary.current_streak || 0,
    target: nextStreakTarget,
    icon: 'flame.fill'
  });
  
  // Daily goal
  if (!progressSummary.daily_goal_completed) {
    milestones.push({
      type: 'daily',
      title: 'Complete Daily Goal',
      progress: progressSummary.daily_goal_current || 0,
      target: progressSummary.daily_goal_target || 5,
      icon: 'target'
    });
  }
  
  return milestones.slice(0, 3); // Return top 3 milestones
}

module.exports = router;