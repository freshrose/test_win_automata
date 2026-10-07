const fs = require('fs');
const f = 'C:/Users/rosa/.claude.json';
const j = JSON.parse(fs.readFileSync(f, 'utf8'));
const key = Object.keys(j.projects).find(k => k.replace(/\\/g, '/') === 'C:/Users/rosa/_rsm');
if (!key) { console.error('project _rsm not found'); process.exit(1); }
j.projects[key].mcpServers = j.projects[key].mcpServers || {};
j.projects[key].mcpServers.gitnexus = { type: 'stdio', command: 'cmd', args: ['/c', 'gitnexus', 'mcp'], env: {} };
fs.writeFileSync(f, JSON.stringify(j, null, 2));
console.log('fixed under project:', key);
console.log('now:', JSON.stringify(j.projects[key].mcpServers.gitnexus));
