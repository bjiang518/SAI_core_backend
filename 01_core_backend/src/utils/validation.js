const Joi = require('joi');

// Environment validation schema
const envSchema = Joi.object({
  NODE_ENV: Joi.string().valid('development', 'production', 'test').default('development'),
  PORT: Joi.number().default(3000),
  SUPABASE_URL: Joi.string().uri().optional(),
  SUPABASE_ANON_KEY: Joi.string().optional(),
  JWT_SECRET: Joi.string().min(32).required(),
  OPENAI_API_KEY: Joi.string().optional(),
  YOUTUBE_API_KEY: Joi.string().optional(),
}).unknown();

// Validate environment variables
const validateEnv = () => {
  const { error, value } = envSchema.validate(process.env);
  
  if (error) {
    throw new Error(`Config validation error: ${error.message}`);
  }
  
  return value;
};

// Request validation schemas
const authSchemas = {
  register: Joi.object({
    email: Joi.string().email().required(),
    password: Joi.string().min(8).required(),
    role: Joi.string().valid('student', 'parent').required(),
    firstName: Joi.string().min(1).max(50).required(),
    lastName: Joi.string().min(1).max(50).required(),
    dateOfBirth: Joi.date().optional(),
    gradeLevel: Joi.number().integer().min(1).max(12).optional(),
    parentEmail: Joi.string().email().optional()
  }),
  
  login: Joi.object({
    email: Joi.string().email().required(),
    password: Joi.string().required()
  }),
  
  updateProfile: Joi.object({
    firstName: Joi.string().min(1).max(50).optional(),
    lastName: Joi.string().min(1).max(50).optional(),
    gradeLevel: Joi.number().integer().min(1).max(12).optional(),
    profileSettings: Joi.object().optional()
  })
};

// Archive validation schemas
const archiveSchemas = {
  createSession: Joi.object({
    subject: Joi.string().min(1).max(100).required(),
    title: Joi.string().max(200).optional(),
    originalImageUrl: Joi.string().uri().required(),
    thumbnailUrl: Joi.string().uri().optional(),
    aiParsingResult: Joi.object({
      questions: Joi.array().items(Joi.object({
        questionNumber: Joi.number().optional(),
        questionText: Joi.string().required(),
        answerText: Joi.string().required(),
        confidence: Joi.number().min(0).max(1).required(),
        hasVisualElements: Joi.boolean().optional()
      })).required(),
      questionCount: Joi.number().integer().min(0).required(),
      parsingMethod: Joi.string().optional(),
      processingTime: Joi.number().optional(),
      overallConfidence: Joi.number().min(0).max(1).optional()
    }).required(),
    processingTime: Joi.number().min(0).required(),
    overallConfidence: Joi.number().min(0).max(1).required(),
    studentAnswers: Joi.object().pattern(Joi.string(), Joi.string()).optional(),
    notes: Joi.string().max(1000).optional()
  })
};

const questionSchemas = {
  uploadQuestion: Joi.object({
    questionText: Joi.string().optional(),
    subject: Joi.string().max(50).optional(),
    topic: Joi.string().max(100).optional(),
    sessionId: Joi.string().uuid().optional()
  }),
  
  askHelp: Joi.object({
    question: Joi.string().required(),
    context: Joi.string().optional()
  })
};

const sessionSchemas = {
  createSession: Joi.object({
    sessionType: Joi.string().valid('homework', 'practice', 'mock_exam').required(),
    title: Joi.string().max(200).required(),
    description: Joi.string().optional()
  }),
  
  updateSession: Joi.object({
    title: Joi.string().max(200).optional(),
    description: Joi.string().optional(),
    status: Joi.string().valid('active', 'completed', 'paused').optional()
  })
};

const evaluationSchemas = {
  submitAnswer: Joi.object({
    questionId: Joi.string().uuid().required(),
    studentAnswer: Joi.string().required(),
    timeSpent: Joi.number().integer().min(0).optional()
  })
};

// Validation middleware
const validate = (schema) => {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body);
    
    if (error) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.details.map(detail => ({
          field: detail.path.join('.'),
          message: detail.message
        }))
      });
    }
    
    req.body = value;
    next();
  };
};

module.exports = {
  validateEnv,
  validate,
  schemas: {
    auth: authSchemas,
    archive: archiveSchemas,
    question: questionSchemas,
    session: sessionSchemas,
    evaluation: evaluationSchemas
  }
};