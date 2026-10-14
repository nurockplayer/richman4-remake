// One-off comparison probe. Runs only in ephemeral Actions runner on an experimental branch.
// No production checkout writes; scene mutations go to a fresh OS temp directory.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const repo = resolve('.');
const scratch = mkdtempSync(join(tmpdir(), 'godot-mcp-scratch-'));
const child = spawn('pnpm', ['dlx', '@coding-solo/godot-mcp@0.1.1'], {
  cwd: scratch,
  env: { ...process.env, GODOT_PATH: '/usr/local/bin/godot', DEBUG: 'false' },
  stdio: ['pipe', 'pipe', 'pipe'],
});
let requestId = 0;
let buffer = '';
const pending = new Map();
let stderrBytes = 0;
child.stdout.setEncoding('utf8');
child.stdout.on('data', part => {
  buffer += part;
  for (;;) {
    const end = buffer.indexOf('\n');
    if (end < 0) break;
    const line = buffer.slice(0, end).trim();
    buffer = buffer.slice(end + 1);
    if (!line) continue;
    let message;
    try { message = JSON.parse(line); }
    catch { console.log('MCP non-JSON stdout (first 140 chars): ' + line.slice(0, 140)); continue; }
    const slot = pending.get(message.id);
    if (slot) {
      clearTimeout(slot.timer);
      pending.delete(message.id);
      if (message.error) slot.reject(new Error(JSON.stringify(message.error)));
      else slot.resolve(message.result);
    }
  }
});
child.stderr.on('data', part => {
  // Failure details only, bounded to avoid log spam. No secrets exposed to this runner.
  if (stderrBytes < 2500) process.stderr.write(String(part).slice(0, 2500 - stderrBytes));
  stderrBytes += part.length;
});
child.on('exit', (code, signal) => {
  for (const slot of pending.values()) {
    clearTimeout(slot.timer);
    slot.reject(new Error('MCP process exited: code=' + code + ' signal=' + signal));
  }
  pending.clear();
});

function request(method, params, timeoutMs = 60000) {
  return new Promise((resolveRequest, reject) => {
    const id = ++requestId;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error('Timed out: ' + method + ', request ' + id));
    }, timeoutMs);
    pending.set(id, { timer, resolve: resolveRequest, reject });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
function notify(method, params = {}) {
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n');
}
async function tool(name, args) {
  const result = await request('tools/call', { name, arguments: args });
  const summary = JSON.stringify(result).slice(0, 1600);
  assert.equal(result.isError, undefined, name + ' reported MCP error: ' + summary);
  console.log('MCP ' + name + ': ' + summary.slice(0, 550));
  return result;
}

let verdict = 'FAIL';
try {
  console.log('POC target: Richman4 main 961bdf47389a08e3143c0340490896b50edef9');
  console.log('POC scope: Godot 4.7.2 + published Coding-Solo npm 0.1.1 + disposable scene');
  writeFileSync(join(scratch, 'project.godot'),
    'config_version=5\n[application]\nconfig/name="Isolated MCP Probe"\nconfig/features=PackedStringArray("4.7")\n');
  const hello = await request('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'richman-isolated-probe', version: '1.0.0' },
  }, 180000);
  console.log('MCP initialized: ' + JSON.stringify(hello).slice(0, 400));
  notify('notifications/initialized');
  const listing = await request('tools/list', {});
  const names = listing.tools.map(x => x.name);
  console.log('MCP tool count: ' + names.length + '; names: ' + names.join(', '));
  const interactive = names.filter(x => /input|click|mouse|keyboard|screenshot|snapshot|scenario|assert/i.test(x));
  console.log('MCP player-input/screenshot/assertion tools: ' + JSON.stringify(interactive));
  assert.ok(names.includes('create_scene') && names.includes('get_godot_version'));
  await tool('get_godot_version', {});
  await tool('get_project_info', { projectPath: repo });
  await tool('create_scene', {
    projectPath: scratch, scenePath: 'PoCScene.tscn', rootNodeType: 'Node2D',
  });
  const scene = join(scratch, 'PoCScene.tscn');
  assert.ok(existsSync(scene), 'MCP returned but scene file was not created');
  assert.match(readFileSync(scene, 'utf8'), /gd_scene/, 'scene must be a real Godot resource');
  await tool('add_node', {
    projectPath: scratch, scenePath: 'PoCScene.tscn', parentNodePath: 'root',
    nodeType: 'Label', nodeName: 'ProbeLabel',
  });
  assert.match(readFileSync(scene, 'utf8'), /ProbeLabel/, 'node must be serialized');
  verdict = 'PASS';
  console.log('RESULT: PASS for MCP/4.7.2 scene API; NOT RUN for real player input, visual screenshot, native macOS');
} catch (error) {
  console.error('RESULT: FAIL at: ' + (error?.stack ?? error));
  process.exitCode = 1;
} finally {
  child.kill('SIGTERM');
  rmSync(scratch, { recursive: true, force: true });
  console.log('Scratch project removed. POC verdict=' + verdict);
}
