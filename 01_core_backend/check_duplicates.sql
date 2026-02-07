-- Check for existing duplicates before adding constraint
SELECT user_id, question_text, student_answer, COUNT(*) as count
FROM questions
WHERE question_text IS NOT NULL 
  AND student_answer IS NOT NULL
GROUP BY user_id, question_text, student_answer
HAVING COUNT(*) > 1
LIMIT 10;
