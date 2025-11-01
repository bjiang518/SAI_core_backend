/**
 * Input Validation Utility
 * Provides validation functions to prevent SQL injection and XSS attacks
 * Ensures OWASP compliance for user input handling
 */

class InputValidation {
  /**
   * Sanitize search query input
   * Removes SQL injection attack patterns while preserving search functionality
   * @param {string} searchTerm - User search input
   * @param {number} maxLength - Maximum allowed length (default 100)
   * @returns {string} Sanitized search term
   */
  static sanitizeSearchTerm(searchTerm, maxLength = 100) {
    if (!searchTerm || typeof searchTerm !== 'string') {
      return '';
    }

    // Trim and limit length
    let sanitized = searchTerm.trim().substring(0, maxLength);

    // Remove SQL injection patterns
    // Block: --, /*, */, ;, UNION, SELECT, DROP, DELETE, INSERT, UPDATE, etc.
    const sqlInjectionPatterns = [
      /--/gi,           // SQL comments
      /\/\*/gi,         // Block comment start
      /\*\//gi,         // Block comment end
      /;\s*(DROP|DELETE|INSERT|UPDATE|ALTER|CREATE|EXEC|EXECUTE)/gi,  // Dangerous SQL commands
      /UNION\s+SELECT/gi,  // Union-based injection
      /'\s*OR\s+'1'\s*=\s*'1/gi,  // Classic OR injection
      /'\s*OR\s+1\s*=\s*1/gi,     // OR 1=1 injection
      /xp_/gi,          // SQL Server extended procedures
      /sp_/gi,          // SQL Server stored procedures
      /WAITFOR\s+DELAY/gi,  // Time-based injection
      /BENCHMARK/gi,    // MySQL time-based injection
      /SLEEP\s*\(/gi,   // Sleep-based injection
      /\bCHR\s*\(/gi,   // Character encoding bypass
      /\bCONCAT\s*\(/gi  // Concatenation bypass attempts
    ];

    // Check for SQL injection patterns
    for (const pattern of sqlInjectionPatterns) {
      if (pattern.test(sanitized)) {
        throw new Error('Invalid search term: contains prohibited SQL patterns');
      }
    }

    // Remove potentially dangerous special characters for ILIKE
    // Keep: alphanumeric, spaces, basic punctuation
    // Remove: quotes, semicolons, backslashes, etc.
    sanitized = sanitized.replace(/['"`;\\]/g, '');

    return sanitized;
  }

  /**
   * Validate date pattern input
   * Only allows whitelisted date patterns
   * @param {string} datePattern - Date pattern input
   * @returns {string} Validated date pattern
   */
  static validateDatePattern(datePattern) {
    const validPatterns = [
      'today',
      'yesterday',
      'this_week',
      'last_week',
      'this_month',
      'last_month',
      'this_year',
      'last_year',
      'all'
    ];

    if (!datePattern || typeof datePattern !== 'string') {
      return 'all';  // Default to 'all' if no pattern provided
    }

    const normalized = datePattern.toLowerCase().trim();

    if (!validPatterns.includes(normalized)) {
      throw new Error(`Invalid date pattern. Allowed: ${validPatterns.join(', ')}`);
    }

    return normalized;
  }

  /**
   * Validate numeric input (for user IDs, limits, offsets)
   * @param {any} value - Input value
   * @param {object} options - Validation options
   * @returns {number} Validated number
   */
  static validateNumber(value, options = {}) {
    const {
      min = 0,
      max = Number.MAX_SAFE_INTEGER,
      defaultValue = 0,
      fieldName = 'value'
    } = options;

    // Handle null/undefined
    if (value === null || value === undefined) {
      return defaultValue;
    }

    // Convert to number
    const num = Number(value);

    // Check if valid number
    if (isNaN(num) || !isFinite(num)) {
      throw new Error(`Invalid ${fieldName}: must be a valid number`);
    }

    // Check range
    if (num < min || num > max) {
      throw new Error(`Invalid ${fieldName}: must be between ${min} and ${max}`);
    }

    // Return integer
    return Math.floor(num);
  }

  /**
   * Validate email format
   * @param {string} email - Email address
   * @returns {boolean} True if valid email
   */
  static isValidEmail(email) {
    if (!email || typeof email !== 'string') {
      return false;
    }

    // RFC 5322 compliant email regex (simplified)
    const emailRegex = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/;

    return emailRegex.test(email) && email.length <= 254;
  }

  /**
   * Validate UUID format
   * @param {string} uuid - UUID string
   * @returns {boolean} True if valid UUID
   */
  static isValidUUID(uuid) {
    if (!uuid || typeof uuid !== 'string') {
      return false;
    }

    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    return uuidRegex.test(uuid);
  }

  /**
   * Sanitize SQL order by clause
   * Only allows whitelisted column names and directions
   * @param {string} orderBy - Order by clause
   * @param {array} allowedColumns - Whitelisted column names
   * @returns {object} Sanitized order by {column, direction}
   */
  static sanitizeOrderBy(orderBy, allowedColumns = []) {
    if (!orderBy || typeof orderBy !== 'string') {
      return { column: allowedColumns[0] || 'created_at', direction: 'DESC' };
    }

    const parts = orderBy.trim().split(/\s+/);
    const column = parts[0]?.toLowerCase();
    const direction = (parts[1]?.toUpperCase() === 'ASC') ? 'ASC' : 'DESC';

    // Validate column is in whitelist
    if (!allowedColumns.includes(column)) {
      throw new Error(`Invalid order by column. Allowed: ${allowedColumns.join(', ')}`);
    }

    return { column, direction };
  }

  /**
   * Sanitize subject name input
   * @param {string} subject - Subject name
   * @returns {string} Sanitized subject
   */
  static sanitizeSubject(subject) {
    if (!subject || typeof subject !== 'string') {
      return 'general';
    }

    const validSubjects = [
      'mathematics',
      'math',
      'physics',
      'chemistry',
      'biology',
      'history',
      'literature',
      'english',
      'computer science',
      'cs',
      'economics',
      'general'
    ];

    const normalized = subject.toLowerCase().trim();

    // If subject is in valid list, return it
    if (validSubjects.includes(normalized)) {
      return normalized;
    }

    // Otherwise return general
    return 'general';
  }

  /**
   * Validate pagination parameters
   * @param {number} limit - Limit value
   * @param {number} offset - Offset value
   * @returns {object} Validated {limit, offset}
   */
  static validatePagination(limit, offset) {
    return {
      limit: this.validateNumber(limit, { min: 1, max: 100, defaultValue: 20, fieldName: 'limit' }),
      offset: this.validateNumber(offset, { min: 0, max: 10000, defaultValue: 0, fieldName: 'offset' })
    };
  }
}

module.exports = InputValidation;
