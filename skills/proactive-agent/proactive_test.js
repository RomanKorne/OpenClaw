// Minimal proactive agent test: fetch Tasks from Airtable if AIRTABLE_API_KEY present, otherwise simulate
const https = require('https');
const { execSync } = require('child_process');
const fs = require('fs');

const BASE = process.env.AIRTABLE_BASE || 'appB2VMy9GXqq0I8O';
const AIRTABLE_TOKEN = process.env.AIRTABLE_API_KEY || '';

async function fetchTasks() {
  if (!AIRTABLE_TOKEN) {
    console.log('No AIRTABLE_API_KEY found — simulating tasks');
    return [{id:'sim1', title:'Overdue: pay invoice', due:'2026-03-10'}];
  }
  const options = {
    method: 'GET',
    hostname: 'api.airtable.com',
    path: `/v0/${BASE}/Tasks?maxRecords=10`,
    headers: { Authorization: `Bearer ${AIRTABLE_TOKEN}` }
  };
  return new Promise((resolve, reject)=>{
    const req = https.request(options, res=>{
      let data=''; res.on('data',d=>data+=d); res.on('end',()=>{ const j=JSON.parse(data); resolve(j.records||[]); });
    });
    req.on('error',reject); req.end();
  });
}

(async ()=>{
  console.log('Proactive test start');
  const tasks = await fetchTasks();
  console.log('Found tasks:', tasks.length);
  for (const t of tasks) {
    const title = t.fields?.Title || t.title || 'no-title';
    console.log('- ', title);
  }
  console.log('Proactive test finished');
})();
