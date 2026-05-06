const { Pool } = require('pg');
const p = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
Promise.all([
  p.query('SELECT COUNT(*) n FROM question_bank'),
  p.query('SELECT COUNT(*) n FROM question_bank WHERE figure_data IS NOT NULL'),
  p.query("SELECT COUNT(*) n FROM question_bank WHERE base_branch IS NULL OR base_branch = ''"),
  p.query('SELECT source, COUNT(*) n FROM question_bank GROUP BY source ORDER BY source'),
  p.query('SELECT subject, COUNT(*) n FROM question_bank GROUP BY subject ORDER BY n DESC'),
]).then(([total, figs, noTag, sources, subjects]) => {
  console.log('Total rows:   ', total.rows[0].n);
  console.log('With figures: ', figs.rows[0].n);
  console.log('Needs tagging:', noTag.rows[0].n);
  console.log('\nBy source:');
  console.table(sources.rows);
  console.log('By subject:');
  console.table(subjects.rows);
  p.end();
});
