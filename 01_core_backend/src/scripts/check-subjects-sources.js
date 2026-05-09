const { Pool } = require('pg');
const p = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
p.query(`
  SELECT subject, source, COUNT(*) n
  FROM question_bank
  GROUP BY subject, source
  ORDER BY subject, n DESC
`).then(r => {
  let lastSubject = '';
  r.rows.forEach(row => {
    if (row.subject !== lastSubject) { console.log(`\n${row.subject}`); lastSubject = row.subject; }
    console.log(`  ${String(row.n).padStart(5)} × ${row.source}`);
  });
  p.end();
});
