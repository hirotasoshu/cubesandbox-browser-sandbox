const endpoint = process.argv[2];

if (!endpoint) {
  throw new Error('MCP endpoint argument is required');
}

function decodePayload(text) {
  if (!text.trim()) return null;
  if (text.trimStart().startsWith('{')) return JSON.parse(text);

  const data = text
    .split('\n')
    .filter((line) => line.startsWith('data:'))
    .map((line) => line.slice(5).trim())
    .filter(Boolean);
  if (!data.length) throw new Error(`Missing SSE data in response: ${text}`);
  return JSON.parse(data.at(-1));
}

async function request(payload, sessionId) {
  const headers = {
    accept: 'application/json, text/event-stream',
    'content-type': 'application/json',
  };
  if (sessionId) headers['mcp-session-id'] = sessionId;

  const response = await fetch(endpoint, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`MCP HTTP ${response.status}: ${text}`);
  }
  return {
    payload: decodePayload(text),
    sessionId: response.headers.get('mcp-session-id') || sessionId,
  };
}

const initialized = await request({
  jsonrpc: '2.0',
  id: 1,
  method: 'initialize',
  params: {
    protocolVersion: '2025-03-26',
    capabilities: {},
    clientInfo: { name: 'browser-sandbox-smoke', version: '1.0.0' },
  },
});

if (!initialized.sessionId || initialized.payload?.error) {
  throw new Error(`MCP initialize failed: ${JSON.stringify(initialized.payload)}`);
}

await request({ jsonrpc: '2.0', method: 'notifications/initialized' }, initialized.sessionId);

const tools = await request(
  { jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} },
  initialized.sessionId,
);
const names = tools.payload?.result?.tools?.map((tool) => tool.name) || [];
if (!names.includes('browser_navigate')) {
  throw new Error('browser_navigate is missing from Playwright MCP tools');
}

const navigation = await request(
  {
    jsonrpc: '2.0',
    id: 3,
    method: 'tools/call',
    params: {
      name: 'browser_navigate',
      arguments: { url: 'https://example.com' },
    },
  },
  initialized.sessionId,
);
const content = JSON.stringify(navigation.payload?.result?.content || []);
if (navigation.payload?.error || !content.includes('Example Domain')) {
  throw new Error(`MCP navigation failed: ${JSON.stringify(navigation.payload)}`);
}

console.log('PLAYWRIGHT_MCP_OK');
