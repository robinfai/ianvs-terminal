import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createServer } from '../src/server.mjs';
import {
  completeWithWasm,
  resetWasmInstanceForTests,
} from '../src/wasm_engine.mjs';
import { clearHostProviderCache } from '../src/host_providers.mjs';

test('suggests git subcommands from the WASM Fig core', async () => {
  const result = await completeWithWasm({ text: 'git che', cursorOffset: 7 });
  const names = result.items.map((item) => item.name);

  assert.deepEqual(names.slice(0, 2), ['checkout', 'cherry-pick']);
  assert.equal(result.items[0].replaceStart, 4);
  assert.equal(result.items[0].replaceEnd, 7);
});

test('uses host path templates for ls ./ folder suggestions', async () => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'ianvs-wasm-ls-'));
  try {
    await fs.mkdir(path.join(fixture, 'alpha-dir'));
    await fs.mkdir(path.join(fixture, 'beta-dir'));
    await fs.writeFile(path.join(fixture, 'z-file.txt'), 'file');

    const result = await completeWithWasm({
      text: 'ls ./',
      cursorOffset: 5,
      cwd: fixture,
    });
    const names = result.items.map((item) => item.name);

    assert.ok(names.includes('./alpha-dir/'));
    assert.ok(names.includes('./beta-dir/'));
    assert.ok(names.indexOf('./z-file.txt') > names.indexOf('./beta-dir/'));
  } finally {
    await fs.rm(fixture, { recursive: true, force: true });
  }
});

test('uses host kubectl templates for dynamic Kubernetes suggestions', async () => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'ianvs-wasm-kubectl-'));
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
  clearHostProviderCache();

  try {
    const resourceNames = (
      await completeWithWasm({ text: 'kubectl get ', cursorOffset: 12 })
    ).items.map((item) => item.name);
    assert.ok(resourceNames.includes('pods'));
    assert.ok(resourceNames.includes('deployments.apps'));

    const podNames = (
      await completeWithWasm({ text: 'kubectl get pods ', cursorOffset: 17 })
    ).items.map((item) => item.name);
    assert.ok(podNames.includes('coredns-abc'));
    assert.ok(podNames.includes('web-123'));

    const namespaceNames = (
      await completeWithWasm({ text: 'kubectl -n ', cursorOffset: 11 })
    ).items.map((item) => item.name);
    assert.ok(namespaceNames.includes('kube-system'));
  } finally {
    process.env.PATH = oldPath;
    clearHostProviderCache();
    await fs.rm(fixture, { recursive: true, force: true });
  }
});

test('serves WASM completions over HTTP', async () => {
  resetWasmInstanceForTests();
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
