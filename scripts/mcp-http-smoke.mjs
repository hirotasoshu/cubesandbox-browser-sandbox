import { createHash } from 'node:crypto';

const endpoint = process.argv[2];
const trafficAccessToken = process.env.E2B_TRAFFIC_ACCESS_TOKEN;

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

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

async function request(payload, sessionId) {
  const headers = {
    accept: 'application/json, text/event-stream',
    'content-type': 'application/json',
  };
  if (sessionId) headers['mcp-session-id'] = sessionId;
  if (trafficAccessToken) headers['e2b-traffic-access-token'] = trafficAccessToken;

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
const manifest = tools.payload?.result?.tools || [];
const manifestSha256 = createHash('sha256')
  .update(JSON.stringify(stable(manifest)))
  .digest('hex');
if (manifestSha256 !== 'b75d4cd1bfc451bcd0ca4664183649d4b1ffa12403b5243c58de006e88563c1f') {
  throw new Error(`Unexpected Playwright MCP tool definitions: ${manifestSha256}`);
}
const expectedNames = [
  'browser_click',
  'browser_close',
  'browser_console_messages',
  'browser_drag',
  'browser_drop',
  'browser_evaluate',
  'browser_file_upload',
  'browser_fill_form',
  'browser_find',
  'browser_handle_dialog',
  'browser_hover',
  'browser_navigate',
  'browser_navigate_back',
  'browser_network_request',
  'browser_network_requests',
  'browser_press_key',
  'browser_resize',
  'browser_run_code_unsafe',
  'browser_select_option',
  'browser_snapshot',
  'browser_tabs',
  'browser_take_screenshot',
  'browser_type',
  'browser_wait_for',
].sort();
if (JSON.stringify(names.sort()) !== JSON.stringify(expectedNames)) {
  throw new Error(`Unexpected Playwright MCP tool manifest: ${JSON.stringify(names)}`);
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

// The default Playwright heartbeat closes POST-only sessions after five seconds.
await new Promise((resolve) => setTimeout(resolve, 6_000));

const runtime = await request(
  {
    jsonrpc: '2.0',
    id: 4,
    method: 'tools/call',
    params: {
      name: 'browser_run_code_unsafe',
      arguments: {
        code: 'async () => ({ uid: process.getuid?.(), envKeys: Object.keys(process.env) })',
      },
    },
  },
  initialized.sessionId,
);
const runtimeContent = JSON.stringify(runtime.payload?.result?.content || []);
const confinedProcessAccess = runtimeContent.includes('ReferenceError: process is not defined');
if (
  runtime.payload?.error ||
  (runtime.payload?.result?.isError && !confinedProcessAccess) ||
  runtimeContent.replaceAll(' ', '').includes('"uid":0')
) {
  throw new Error(`MCP unsafe runtime is root: ${JSON.stringify(runtime.payload)}`);
}
for (const forbidden of [
  'SANDBOX_API_KEY',
  'DATABASE_URL',
  'ARTIFACT_S3_SECRET_KEY',
  'LLM_API_KEY',
  'MCP_TOKEN_SECRET',
]) {
  if (runtimeContent.includes(forbidden)) {
    throw new Error(`MCP unsafe runtime exposes a forbidden environment key: ${forbidden}`);
  }
}

console.log('PLAYWRIGHT_MCP_OK');
