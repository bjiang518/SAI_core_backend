'use strict';
require('dotenv').config();
const https = require('https');
function fetchJson(url) {
  return new Promise((resolve, reject) => {
    const h = { 'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json' };
    if (process.env.HF_TOKEN) h['Authorization'] = 'Bearer ' + process.env.HF_TOKEN;
    const req = https.get(url, { headers: h }, res => {
      const c = []; res.on('data', d => c.push(d));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(c).toString() }));
      res.on('error', e => reject(new Error('res error: ' + JSON.stringify(e, Object.getOwnPropertyNames(e)))));
    });
    req.on('error', e => reject(new Error('req error: ' + JSON.stringify(e, Object.getOwnPropertyNames(e)))));
    req.setTimeout(10000, () => { req.destroy(); reject(new Error('timeout')); });
  });
}
(async () => {
  // Test basic connectivity first
  try {
    const r = await fetchJson('https://datasets-server.huggingface.co/validity?dataset=qualcomm%2FM3Kang');
    console.log('validity [' + r.status + ']:', r.body.slice(0, 400));
  } catch(e) { console.log('validity FAIL:', e.message.slice(0, 300)); }
  
  // Try the HF API 
  try {
    const r = await fetchJson('https://huggingface.co/api/datasets/qualcomm/M3Kang');
    console.log('hf-api [' + r.status + ']:', r.body.slice(0, 400));
  } catch(e) { console.log('hf-api FAIL:', e.message.slice(0, 300)); }
})();
