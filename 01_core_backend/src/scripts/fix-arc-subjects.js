const { Pool } = require('pg');
const p = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
Promise.all([
  p.query("UPDATE question_bank SET subject='Physics'  WHERE source='arc' AND subject IN ('Geology','Astronomy','Astrophysics')"),
  p.query("UPDATE question_bank SET subject='Chemistry' WHERE source='arc' AND subject IN ('Mineralogy','Biochemistry')"),
  p.query("UPDATE question_bank SET subject='Biology'   WHERE source='arc' AND subject='Scientific Method & Lab Skills'"),
]).then(([a, b, c]) => {
  console.log('Physics  fixed:', a.rowCount);
  console.log('Chemistry fixed:', b.rowCount);
  console.log('Biology  fixed:', c.rowCount);
  console.log('Total fixed:', a.rowCount + b.rowCount + c.rowCount);
  p.end();
});
