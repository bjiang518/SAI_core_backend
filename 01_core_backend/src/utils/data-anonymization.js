/**
 * Data Anonymization Utility for Analytics
 * GDPR-compliant data anonymization for parent reports and analytics
 * Removes all PII while preserving statistical accuracy
 *
 * GDPR Requirements:
 * - Article 6(1)(f): Legitimate interest for analytics
 * - Recital 26: Anonymous data not subject to GDPR
 * - Article 25: Data protection by design
 */

const crypto = require('crypto');

class DataAnonymization {
  /**
   * Anonymize user ID using one-way hash
   * Consistent for the same user (for tracking) but cannot be reversed
   * @param {string} userId - User ID to anonymize
   * @param {string} salt - Optional salt for additional security
   * @returns {string} Anonymized user ID
   */
  static anonymizeUserId(userId, salt = process.env.ANALYTICS_SALT || 'studyai-analytics-2025') {
    if (!userId) return 'anonymous';

    // Create consistent hash (same user = same hash)
    const hash = crypto
      .createHmac('sha256', salt)
      .update(userId.toString())
      .digest('hex');

    // Return first 12 characters for readability
    return `anon_${hash.substring(0, 12)}`;
  }

  /**
   * Anonymize email address
   * Preserves domain for analytics (e.g., school vs personal email)
   * @param {string} email - Email to anonymize
   * @returns {object} Anonymized email data
   */
  static anonymizeEmail(email) {
    if (!email || typeof email !== 'string') {
      return {
        anonymized: 'anonymous@unknown.com',
        domain: 'unknown.com',
        isDomainKnown: false
      };
    }

    const parts = email.split('@');
    if (parts.length !== 2) {
      return {
        anonymized: 'anonymous@invalid.com',
        domain: 'invalid.com',
        isDomainKnown: false
      };
    }

    const domain = parts[1];
    const domainHash = crypto
      .createHash('md5')
      .update(domain)
      .digest('hex')
      .substring(0, 6);

    return {
      anonymized: `user_${domainHash}@${domain}`,
      domain: domain,
      isDomainKnown: true,
      // Classify domain type for analytics
      domainType: this.classifyEmailDomain(domain)
    };
  }

  /**
   * Classify email domain type (preserves useful analytics without PII)
   * @param {string} domain - Email domain
   * @returns {string} Domain classification
   */
  static classifyEmailDomain(domain) {
    const lowerDomain = domain.toLowerCase();

    // Common personal email providers
    const personalDomains = ['gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 'icloud.com', 'aol.com'];
    if (personalDomains.includes(lowerDomain)) {
      return 'personal';
    }

    // Education domains
    if (lowerDomain.endsWith('.edu') || lowerDomain.includes('school') || lowerDomain.includes('university')) {
      return 'education';
    }

    // Government domains
    if (lowerDomain.endsWith('.gov') || lowerDomain.endsWith('.mil')) {
      return 'government';
    }

    return 'other';
  }

  /**
   * Anonymize location data
   * Preserves region/state but removes specific city/address
   * @param {object} location - Location data
   * @returns {object} Anonymized location
   */
  static anonymizeLocation(location) {
    if (!location) return { region: 'unknown', country: 'unknown' };

    return {
      // Keep country and state for regional analytics
      country: location.country || 'unknown',
      stateProvince: location.stateProvince || location.state_province || 'unknown',

      // Remove specific city
      city: '[anonymized]',

      // Remove any street addresses
      address: '[anonymized]',

      // Keep timezone for usage pattern analytics
      timezone: location.timezone || 'UTC',

      // Add region classification
      region: this.classifyRegion(location.country, location.stateProvince)
    };
  }

  /**
   * Classify region for broad analytics
   * @param {string} country - Country
   * @param {string} state - State/province
   * @returns {string} Region classification
   */
  static classifyRegion(country, state) {
    if (!country) return 'unknown';

    const countryUpper = country.toUpperCase();

    // US regions
    if (countryUpper === 'US' || countryUpper === 'USA' || countryUpper === 'UNITED STATES') {
      const usRegions = {
        'northeast': ['NY', 'PA', 'NJ', 'MA', 'CT', 'RI', 'NH', 'VT', 'ME'],
        'southeast': ['FL', 'GA', 'NC', 'SC', 'VA', 'WV', 'KY', 'TN', 'AL', 'MS', 'AR', 'LA'],
        'midwest': ['OH', 'IN', 'IL', 'MI', 'WI', 'MN', 'IA', 'MO', 'ND', 'SD', 'NE', 'KS'],
        'southwest': ['TX', 'OK', 'NM', 'AZ'],
        'west': ['CA', 'OR', 'WA', 'NV', 'ID', 'MT', 'WY', 'UT', 'CO'],
        'pacific': ['HI', 'AK']
      };

      for (const [region, states] of Object.entries(usRegions)) {
        if (state && states.includes(state.toUpperCase())) {
          return `US-${region}`;
        }
      }
      return 'US-other';
    }

    // International regions
    const internationalRegions = {
      'europe': ['UK', 'GB', 'DE', 'FR', 'IT', 'ES', 'NL', 'BE', 'SE', 'NO', 'DK', 'FI'],
      'asia': ['CN', 'JP', 'KR', 'IN', 'SG', 'TH', 'VN', 'PH', 'ID', 'MY'],
      'oceania': ['AU', 'NZ'],
      'latin-america': ['MX', 'BR', 'AR', 'CL', 'CO', 'PE'],
      'middle-east': ['AE', 'SA', 'IL'],
      'africa': ['ZA', 'EG', 'NG', 'KE']
    };

    for (const [region, countries] of Object.entries(internationalRegions)) {
      if (countries.includes(countryUpper)) {
        return region;
      }
    }

    return 'other-international';
  }

  /**
   * Anonymize date of birth - preserve age range only
   * @param {string|Date} dateOfBirth - Date of birth
   * @returns {object} Age range instead of exact DOB
   */
  static anonymizeDateOfBirth(dateOfBirth) {
    if (!dateOfBirth) {
      return {
        ageRange: 'unknown',
        isMinor: null
      };
    }

    const dob = new Date(dateOfBirth);
    const today = new Date();
    const age = today.getFullYear() - dob.getFullYear();
    const monthDiff = today.getMonth() - dob.getMonth();
    const adjustedAge = monthDiff < 0 || (monthDiff === 0 && today.getDate() < dob.getDate())
      ? age - 1
      : age;

    // Age ranges for analytics (COPPA-compliant: under 13 is special category)
    let ageRange;
    if (adjustedAge < 13) {
      ageRange = 'under-13';
    } else if (adjustedAge < 18) {
      ageRange = '13-17';
    } else if (adjustedAge < 25) {
      ageRange = '18-24';
    } else if (adjustedAge < 35) {
      ageRange = '25-34';
    } else if (adjustedAge < 45) {
      ageRange = '35-44';
    } else if (adjustedAge < 55) {
      ageRange = '45-54';
    } else {
      ageRange = '55+';
    }

    return {
      ageRange: ageRange,
      isMinor: adjustedAge < 18,
      isCoppaProtected: adjustedAge < 13  // COPPA requires parental consent
    };
  }

  /**
   * Anonymize name - remove completely for analytics
   * @param {string} name - Name to anonymize
   * @returns {string} Anonymized placeholder
   */
  static anonymizeName(name) {
    // For analytics, names provide no value - remove completely
    return '[anonymized]';
  }

  /**
   * Anonymize complete user profile for parent reports
   * Removes all PII while preserving analytics value
   * @param {object} userProfile - User profile data
   * @returns {object} Anonymized profile
   */
  static anonymizeUserProfile(userProfile) {
    if (!userProfile) return null;

    const emailData = this.anonymizeEmail(userProfile.email || userProfile.user_email);
    const locationData = this.anonymizeLocation({
      country: userProfile.country,
      stateProvince: userProfile.state_province || userProfile.stateProvince,
      city: userProfile.city,
      timezone: userProfile.timezone
    });
    const ageData = this.anonymizeDateOfBirth(userProfile.date_of_birth || userProfile.dateOfBirth);

    return {
      // Anonymized identifiers
      userId: this.anonymizeUserId(userProfile.id || userProfile.user_id),
      emailDomain: emailData.domain,
      emailType: emailData.domainType,

      // Demographics (anonymized)
      ageRange: ageData.ageRange,
      isMinor: ageData.isMinor,
      isCoppaProtected: ageData.isCoppaProtected,
      gender: userProfile.gender || 'not-specified',  // Keep gender for analytics if provided

      // Location (aggregated)
      country: locationData.country,
      region: locationData.region,
      timezone: locationData.timezone,

      // Learning preferences (not PII)
      gradeLevel: userProfile.grade_level || userProfile.gradeLevel || 'unknown',
      favoriteSubjects: userProfile.favorite_subjects || userProfile.favoriteSubjects || [],
      learningStyle: userProfile.learning_style || userProfile.learningStyle || 'unknown',
      languagePreference: userProfile.language_preference || userProfile.languagePreference || 'en',

      // Account metadata (not PII)
      authProvider: userProfile.auth_provider || userProfile.authProvider || 'unknown',
      accountCreatedAt: userProfile.created_at || userProfile.accountCreatedAt,
      profileCompleteness: userProfile.profile_completion_percentage || 0,

      // All PII removed
      firstName: '[anonymized]',
      lastName: '[anonymized]',
      displayName: '[anonymized]',
      fullName: '[anonymized]',
      email: '[anonymized]',
      profileImageUrl: '[anonymized]',
      city: '[anonymized]'
    };
  }

  /**
   * Anonymize conversation data for analytics
   * Removes conversation content but preserves metadata
   * @param {object} conversation - Conversation data
   * @returns {object} Anonymized conversation
   */
  static anonymizeConversation(conversation) {
    if (!conversation) return null;

    return {
      conversationId: this.anonymizeUserId(conversation.id || conversation.conversation_id),
      userId: this.anonymizeUserId(conversation.user_id),

      // Metadata (not PII)
      subject: conversation.subject || 'unknown',
      messageCount: conversation.message_count || 0,
      totalTokens: conversation.total_tokens || 0,
      durationMinutes: conversation.duration_minutes || 0,

      // Temporal data (for usage patterns)
      createdAt: conversation.created_at || conversation.archivedDate,
      dayOfWeek: conversation.created_at ? new Date(conversation.created_at).getDay() : null,
      hourOfDay: conversation.created_at ? new Date(conversation.created_at).getHours() : null,

      // Topics (not PII)
      topics: conversation.topics || conversation.key_topics || [],

      // Content removed for privacy
      conversationContent: '[anonymized]',
      summary: '[anonymized]'
    };
  }

  /**
   * Anonymize question data for analytics
   * @param {object} question - Question data
   * @returns {object} Anonymized question
   */
  static anonymizeQuestion(question) {
    if (!question) return null;

    return {
      questionId: this.anonymizeUserId(question.id || question.question_id),
      userId: this.anonymizeUserId(question.user_id),

      // Academic metadata (not PII)
      subject: question.subject || 'unknown',
      isCorrect: question.is_correct || question.isCorrect || false,
      confidenceScore: question.confidence_score || question.confidenceScore || 0,

      // Temporal data
      answeredAt: question.created_at || question.archivedDate,
      dayOfWeek: question.created_at ? new Date(question.created_at).getDay() : null,
      hourOfDay: question.created_at ? new Date(question.created_at).getHours() : null,

      // Content removed for privacy
      questionText: '[anonymized]',
      studentAnswer: '[anonymized]',
      aiAnswer: '[anonymized]'
    };
  }

  /**
   * Anonymize complete parent report data
   * Main entry point for analytics anonymization
   * @param {object} reportData - Complete report data
   * @returns {object} Fully anonymized report
   */
  static anonymizeParentReport(reportData) {
    if (!reportData) return null;

    return {
      // Report metadata (not PII)
      reportId: this.anonymizeUserId(reportData.reportId || reportData.report_id),
      reportType: reportData.reportType || reportData.report_type,
      startDate: reportData.startDate || reportData.start_date,
      endDate: reportData.endDate || reportData.end_date,
      generatedAt: reportData.generatedAt || new Date().toISOString(),

      // Anonymized user info
      user: this.anonymizeUserProfile(reportData.userProfile || reportData.personalInformation),

      // Academic statistics (aggregated, not PII)
      academicStats: {
        totalQuestions: reportData.academic?.totalQuestions || 0,
        correctAnswers: reportData.academic?.correctAnswers || 0,
        accuracy: reportData.academic?.accuracy || 0,
        studyTimeMinutes: reportData.activity?.studyTime?.totalMinutes || 0,
        activeDays: reportData.activity?.studyTime?.activeDays || 0,
        totalSessions: reportData.metadata?.dataPoints?.sessions || 0,
        subjectBreakdown: reportData.academic?.subjectBreakdown || {}
      },

      // Anonymized conversations (metadata only)
      conversations: (reportData.conversations?.data || []).map(conv =>
        this.anonymizeConversation(conv)
      ),

      // Anonymized questions (metadata only)
      questions: (reportData.questions?.data || []).map(q =>
        this.anonymizeQuestion(q)
      ),

      // Usage patterns (temporal, not PII)
      usagePatterns: {
        mostActiveDay: reportData.activity?.patterns?.mostActiveDay || null,
        preferredStudyTime: reportData.activity?.patterns?.preferredTime || null,
        weeklyTrend: reportData.activity?.trends?.weekly || []
      },

      // Privacy notice
      anonymizationMetadata: {
        anonymized: true,
        anonymizationDate: new Date().toISOString(),
        complianceStandard: 'GDPR Article 6(1)(f) - Legitimate Interest',
        dataRetention: '90 days for analytics, then deleted',
        privacyPolicy: 'https://study-mates.net/privacy'
      }
    };
  }

  /**
   * Generate anonymized analytics summary
   * For internal business intelligence without PII
   * @param {array} reports - Array of reports
   * @returns {object} Aggregated anonymous analytics
   */
  static generateAnonymousAnalytics(reports) {
    if (!reports || reports.length === 0) {
      return {
        totalReports: 0,
        totalUniqueUsers: 0,
        averageMetrics: {},
        regionalBreakdown: {},
        subjectPopularity: {}
      };
    }

    // Aggregate statistics without PII
    const uniqueUserIds = new Set();
    const regionCounts = {};
    const subjectCounts = {};
    let totalQuestions = 0;
    let totalStudyTime = 0;
    let totalAccuracy = 0;

    reports.forEach(report => {
      const anonymizedReport = this.anonymizeParentReport(report);

      // Count unique users (anonymized)
      uniqueUserIds.add(anonymizedReport.user?.userId);

      // Regional distribution
      const region = anonymizedReport.user?.region || 'unknown';
      regionCounts[region] = (regionCounts[region] || 0) + 1;

      // Subject popularity
      Object.keys(anonymizedReport.academicStats?.subjectBreakdown || {}).forEach(subject => {
        subjectCounts[subject] = (subjectCounts[subject] || 0) + 1;
      });

      // Aggregate metrics
      totalQuestions += anonymizedReport.academicStats?.totalQuestions || 0;
      totalStudyTime += anonymizedReport.academicStats?.studyTimeMinutes || 0;
      totalAccuracy += anonymizedReport.academicStats?.accuracy || 0;
    });

    return {
      totalReports: reports.length,
      totalUniqueUsers: uniqueUserIds.size,
      averageMetrics: {
        questionsPerReport: totalQuestions / reports.length,
        studyTimePerReport: totalStudyTime / reports.length,
        averageAccuracy: totalAccuracy / reports.length
      },
      regionalBreakdown: regionCounts,
      subjectPopularity: subjectCounts,
      generatedAt: new Date().toISOString(),
      dataProtectionCompliance: 'GDPR-compliant anonymous analytics'
    };
  }
}

module.exports = DataAnonymization;
