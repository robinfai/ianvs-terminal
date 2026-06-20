import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createServer } from '../src/server.mjs';
import {
  clearDynamicCompletionCache,
  complete,
  parseCommandLine,
} from '../src/fig_completion_engine.mjs';

test('parses current shell token and context tokens', () => {
  const parsed = parseCommandLine('git che', 7);

  assert.equal(parsed.contextTokens.length, 1);
  assert.equal(parsed.contextTokens[0].value, 'git');
  assert.equal(parsed.currentToken.value, 'che');
  assert.equal(parsed.currentToken.start, 4);
  assert.equal(parsed.currentToken.end, 7);
});

test('suggests git subcommands from Fig-style spec', () => {
  const result = complete({ text: 'git che', cursorOffset: 7 });
  const names = result.items.map((item) => item.name);

  assert.deepEqual(names.slice(0, 2), ['checkout', 'cherry-pick']);
  assert.equal(result.items[0].replaceStart, 4);
  assert.equal(result.items[0].replaceEnd, 7);
});

test('suggests command options at option position', () => {
  const result = complete({ text: 'git commit --', cursorOffset: 13 });
  const names = result.items.map((item) => item.name);

  assert.ok(names.includes('--message'));
  assert.ok(names.includes('--amend'));
});

test('suggests root commands and recent commands', () => {
  const result = complete({
    text: 'fl',
    cursorOffset: 2,
    recentCommands: ['flutter test', 'git status'],
  });
  const names = result.items.map((item) => item.name);

  assert.equal(names[0], 'flutter');
  assert.ok(names.includes('flutter test'));
});

test('suggests current directory child folders for ls ./', async () => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'ianvs-fig-ls-'));
  try {
    await fs.mkdir(path.join(fixture, 'alpha-dir'));
    await fs.mkdir(path.join(fixture, 'beta-dir'));
    await fs.mkdir(path.join(fixture, '.hidden-dir'));
    await fs.writeFile(path.join(fixture, 'z-file.txt'), 'file');

    const result = complete({ text: 'ls ./', cursorOffset: 5, cwd: fixture });
    const names = result.items.map((item) => item.name);

    assert.ok(names.includes('./alpha-dir/'));
    assert.ok(names.includes('./beta-dir/'));
    assert.equal(result.items[0].type, 'folder');
    assert.equal(result.items[1].type, 'folder');
    assert.ok(names.indexOf('./z-file.txt') > names.indexOf('./beta-dir/'));
    assert.ok(names.indexOf('./.hidden-dir/') > names.indexOf('./beta-dir/'));
  } finally {
    await fs.rm(fixture, { recursive: true, force: true });
  }
});

test('suggests kubectl subcommands and live cluster arguments', async () => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'ianvs-fig-kubectl-'));
  const bin = path.join(fixture, 'bin');
  const kubectl = path.join(bin, 'kubectl');
  const oldPath = process.env.PATH;
  await fs.mkdir(bin);
  await fs.writeFile(
    kubectl,
    `#!/bin/sh
case "$*" in
  "api-resources --verbs=list -o name")
    printf '%s\\n' pods deployments.apps services namespaces nodes
    ;;
  "config get-contexts -o name")
    printf '%s\\n' minikube colima-dev
    ;;
  "get namespaces -o json")
    printf '{"items":[{"metadata":{"name":"default"}},{"metadata":{"name":"kube-system"}}]}'
    ;;
  "get pods -A -o json")
    printf '{"items":[{"metadata":{"name":"coredns-abc","namespace":"kube-system"}},{"metadata":{"name":"web-123","namespace":"default"}}]}'
    ;;
  *)
    exit 1
    ;;
esac
`,
    { mode: 0o755 },
  );
  process.env.PATH = `${bin}${path.delimiter}${oldPath ?? ''}`;
  clearDynamicCompletionCache();

  try {
    const rootNames = complete({ text: 'kubectl ', cursorOffset: 8 }).items.map(
      (item) => item.name,
    );
    assert.ok(rootNames.includes('get'));
    assert.ok(rootNames.includes('logs'));

    const resourceNames = complete({
      text: 'kubectl get ',
      cursorOffset: 12,
    }).items.map((item) => item.name);
    assert.ok(resourceNames.includes('pods'));
    assert.ok(resourceNames.includes('deployments.apps'));

    const podNames = complete({
      text: 'kubectl get pods ',
      cursorOffset: 17,
    }).items.map((item) => item.name);
    assert.ok(podNames.includes('coredns-abc'));
    assert.ok(podNames.includes('web-123'));

    const namespaceNames = complete({
      text: 'kubectl -n ',
      cursorOffset: 11,
    }).items.map((item) => item.name);
    assert.ok(namespaceNames.includes('kube-system'));

    const contextNames = complete({
      text: 'kubectl --context ',
      cursorOffset: 18,
    }).items.map((item) => item.name);
    assert.ok(contextNames.includes('minikube'));
  } finally {
    process.env.PATH = oldPath;
    clearDynamicCompletionCache();
    await fs.rm(fixture, { recursive: true, force: true });
  }
});

test('serves completions over HTTP', async () => {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/complete`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ text: 'git che', cursorOffset: 7 }),
    });
    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.items[0].name, 'checkout');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
