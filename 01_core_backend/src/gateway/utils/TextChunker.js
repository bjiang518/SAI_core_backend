/**
 * Text Chunker for Interactive TTS
 * Intelligently chunks streaming text at sentence boundaries for natural TTS
 *
 * Adapted from iOS StreamingMessageService.swift
 * Phase 2: Interactive Mode Implementation
 *
 * Created: 2026-02-03
 */

class TextChunker {
  constructor(options = {}) {
    // Configuration
    this.minChars = options.minChars || 30;
    this.maxChars = options.maxChars || 120;

    // Sentence-ending punctuation (priority 1)
    this.sentenceEnders = new Set(['.', '!', '?', '。', '！', '？', '\n']);

    // Word boundary characters (fallback)
    this.wordBoundaries = new Set([' ', ',', '，', ';', '；', ':', '：']);

    // State
    this.buffer = '';
    this.processedLength = 0;
    this.totalChunks = 0;
  }

  /**
   * Process new accumulated text and extract ready chunks
   * @param {string} accumulatedText - Full text received from OpenAI so far
   * @returns {Array<string>} - Array of completed chunks ready for TTS
   */
  processNewText(accumulatedText) {
    // Extract only NEW text since last processing
    const unprocessed = accumulatedText.substring(this.processedLength);
    this.buffer += unprocessed;
    this.processedLength = accumulatedText.length;

    const readyChunks = [];

    // Extract chunks while buffer has enough text
    while (this.buffer.length >= this.minChars) {
      const cutPoint = this.findBoundary();

      if (cutPoint > 0) {
        const chunk = this.buffer.substring(0, cutPoint).trim();

        if (chunk.length > 0) {
          readyChunks.push(chunk);
          this.totalChunks++;
        }

        this.buffer = this.buffer.substring(cutPoint).trimStart();
      } else {
        // No suitable boundary found, wait for more text
        break;
      }
    }

    return readyChunks;
  }

  /**
   * Find optimal chunk boundary
   * @returns {number} - Character index to cut at, or -1 if no boundary found
   */
  findBoundary() {
    // Strategy 1: Look for sentence-ending punctuation within optimal range
    const searchEnd = Math.min(this.buffer.length, this.maxChars);

    for (let i = this.minChars; i < searchEnd; i++) {
      if (this.sentenceEnders.has(this.buffer[i])) {
        // Found sentence ender! Cut after it (include the punctuation)
        return i + 1;
      }
    }

    // Strategy 2: If buffer exceeds maxChars, find word boundary
    if (this.buffer.length >= this.maxChars) {
      // Search backwards from maxChars to minChars
      for (let i = this.maxChars - 1; i >= this.minChars; i--) {
        if (this.wordBoundaries.has(this.buffer[i])) {
          // Found word boundary, cut after it
          return i + 1;
        }
      }

      // Strategy 3: Hard cut at maxChars (last resort)
      return this.maxChars;
    }

    // No boundary found, wait for more text
    return -1;
  }

  /**
   * Flush remaining buffer (call at end of stream)
   * @returns {Array<string>} - Final chunk(s)
   */
  flush() {
    const finalChunks = [];

    if (this.buffer.trim().length > 0) {
      finalChunks.push(this.buffer.trim());
      this.totalChunks++;
      this.buffer = '';
    }

    return finalChunks;
  }

  /**
   * Reset chunker state (for new conversation)
   */
  reset() {
    this.buffer = '';
    this.processedLength = 0;
    this.totalChunks = 0;
  }

  /**
   * Get chunker statistics
   * @returns {object} - Stats object
   */
  getStats() {
    return {
      totalChunks: this.totalChunks,
      bufferLength: this.buffer.length,
      processedLength: this.processedLength
    };
  }
}

module.exports = TextChunker;
