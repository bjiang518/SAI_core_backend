/**
 * Request Validation Schemas
 * Joi schemas for validating API requests
 */

const Joi = require('joi');

// Common validation patterns
const patterns = {
  objectId: Joi.string().pattern(/^[a-fA-F0-9]{24}$/).message('Invalid ObjectId format'),
  uuid: Joi.string().uuid().message('Invalid UUID format'),
  email: Joi.string().email().message('Invalid email format'),
  subject: Joi.string().valid('mathematics', 'science', 'english', 'history', 'physics', 'chemistry', 'biology', 'calculus', 'algebra', 'geometry', 'other'),
  difficulty: Joi.string().valid('easy', 'medium', 'hard', 'beginner', 'intermediate', 'advanced'),
  imageFile: Joi.object({
    filename: Joi.string().required(),
    mimetype: Joi.string().valid('image/jpeg', 'image/png', 'image/webp').required(),
    encoding: Joi.string(),
    file: Joi.any().required()
  })
};

// AI Engine request schemas
const aiRequestSchemas = {
  processQuestion: Joi.object({
    question: Joi.string().min(3).max(2000).required()
      .messages({
        'string.min': 'Question must be at least 3 characters long',
        'string.max': 'Question cannot exceed 2000 characters',
        'any.required': 'Question is required'
      }),
    
    subject: patterns.subject.required()
      .messages({
        'any.required': 'Subject is required',
        'any.only': 'Subject must be one of: mathematics, science, english, history, physics, chemistry, biology, calculus, algebra, geometry, other'
      }),
    
    student_id: Joi.string().min(1).max(100).required()
      .messages({
        'string.min': 'Student ID cannot be empty',
        'string.max': 'Student ID cannot exceed 100 characters',
        'any.required': 'Student ID is required'
      }),
    
    context: Joi.string().max(5000).optional()
      .messages({
        'string.max': 'Context cannot exceed 5000 characters'
      })
  }),

  generatePractice: Joi.object({
    subject: patterns.subject.required(),
    
    topic: Joi.string().min(2).max(200).required()
      .messages({
        'string.min': 'Topic must be at least 2 characters long',
        'string.max': 'Topic cannot exceed 200 characters',
        'any.required': 'Topic is required'
      }),
    
    difficulty: patterns.difficulty.default('medium'),
    
    count: Joi.number().integer().min(1).max(10).default(5)
      .messages({
        'number.min': 'Count must be at least 1',
        'number.max': 'Count cannot exceed 10',
        'number.integer': 'Count must be a whole number'
      }),
    
    student_id: Joi.string().min(1).max(100).required()
  }),

  evaluateAnswer: Joi.object({
    question: Joi.string().min(3).max(2000).required(),
    
    student_answer: Joi.string().min(1).max(5000).required()
      .messages({
        'string.min': 'Student answer cannot be empty',
        'string.max': 'Student answer cannot exceed 5000 characters',
        'any.required': 'Student answer is required'
      }),
    
    correct_answer: Joi.string().max(5000).optional()
      .messages({
        'string.max': 'Correct answer cannot exceed 5000 characters'
      }),
    
    subject: patterns.subject.optional(),
    
    student_id: Joi.string().min(1).max(100).required()
  }),

  createSession: Joi.object({
    student_id: Joi.string().min(1).max(100).required(),
    
    subject: patterns.subject.optional(),
    
    session_type: Joi.string().valid('homework', 'practice', 'review', 'test').default('homework'),
    
    metadata: Joi.object({
      grade_level: Joi.string().max(50),
      school: Joi.string().max(200),
      teacher: Joi.string().max(100)
    }).optional()
  })
};

// File upload schemas
const uploadSchemas = {
  homeworkImage: Joi.object({
    image: patterns.imageFile.required(),
    student_id: Joi.string().min(1).max(100).required(),
    subject: patterns.subject.optional(),
    metadata: Joi.object({
      page_number: Joi.number().integer().min(1).max(100),
      total_pages: Joi.number().integer().min(1).max(100),
      assignment_name: Joi.string().max(200)
    }).optional()
  })
};

// User authentication schemas
const authSchemas = {
  login: Joi.object({
    email: patterns.email.required(),
    password: Joi.string().min(6).max(128).required()
      .messages({
        'string.min': 'Password must be at least 6 characters long',
        'string.max': 'Password cannot exceed 128 characters'
      })
  }),

  register: Joi.object({
    email: patterns.email.required(),
    password: Joi.string().min(6).max(128).required(),
    name: Joi.string().min(2).max(100).required()
      .messages({
        'string.min': 'Name must be at least 2 characters long',
        'string.max': 'Name cannot exceed 100 characters'
      }),
    grade_level: Joi.string().max(50).optional(),
    school: Joi.string().max(200).optional()
  })
};

// Common parameter schemas
const paramSchemas = {
  sessionId: Joi.object({
    sessionId: patterns.uuid.required()
      .messages({
        'any.required': 'Session ID is required'
      })
  }),

  userId: Joi.object({
    userId: patterns.objectId.required()
      .messages({
        'any.required': 'User ID is required'
      })
  })
};

// Query parameter schemas
const querySchemas = {
  pagination: Joi.object({
    page: Joi.number().integer().min(1).default(1),
    limit: Joi.number().integer().min(1).max(100).default(20),
    sort: Joi.string().valid('created_at', 'updated_at', 'name', 'subject').default('created_at'),
    order: Joi.string().valid('asc', 'desc').default('desc')
  }),

  search: Joi.object({
    q: Joi.string().min(1).max(200).required()
      .messages({
        'string.min': 'Search query cannot be empty',
        'string.max': 'Search query cannot exceed 200 characters'
      }),
    subject: patterns.subject.optional(),
    difficulty: patterns.difficulty.optional()
  })
};

// Export all schemas organized by category
module.exports = {
  ai: aiRequestSchemas,
  upload: uploadSchemas,
  auth: authSchemas,
  params: paramSchemas,
  query: querySchemas,
  patterns,
  
  // Helper function to get schema by endpoint
  getSchema: (category, schemaName) => {
    const categorySchemas = module.exports[category];
    if (!categorySchemas) {
      throw new Error(`Schema category '${category}' not found`);
    }
    
    const schema = categorySchemas[schemaName];
    if (!schema) {
      throw new Error(`Schema '${schemaName}' not found in category '${category}'`);
    }
    
    return schema;
  }
};