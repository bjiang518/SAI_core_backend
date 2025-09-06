const Joi = require('joi');

// Environment validation schema
const envSchema = Joi.object({
  NODE_ENV: Joi.string().valid('development', 'production', 'test').default('development'),
  PORT: Joi.number().default(3000),
  SUPABASE_URL: Joi.string().uri().required(),
  SUPABASE_ANON_KEY: Joi.string().required(),
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
    question: questionSchemas,
    session: sessionSchemas,
    evaluation: evaluationSchemas
  }
};