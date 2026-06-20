import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { specs } from '../../fig_completion_service/src/specs.mjs';
import { collectHostTemplateSuggestions } from './host_providers.mjs';

const defaultWasmPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../dist/fig_completion_core.wasm',
);
const encoder = new TextEncoder();
const decoder = new TextDecoder();
let instancePromise = null;

export async function completeWithWasm(input, options = {}) {
  const instance = await loadWasmInstance(options.wasmPath);
  const payload = {
    ...input,
    specs: Object.values(specs),
    hostTemplates: collectHostTemplateSuggestions(input ?? {}),
    ...(Number.isInteger(options.limit) ? { limit: options.limit } : {}),
  };
  const requestBytes = encoder.encode(JSON.stringify(payload));
  const requestPtr = instance.exports.ianvs_alloc(requestBytes.length);
  if (!requestPtr) {
    return { items: [] };
  }
  new Uint8Array(
    instance.exports.memory.buffer,
    requestPtr,
    requestBytes.length,
  ).set(requestBytes);

  const responsePtr = instance.exports.ianvs_complete(
    requestPtr,
    requestBytes.length,
  );
  instance.exports.ianvs_free(requestPtr, requestBytes.length);
  const responseLength = instance.exports.ianvs_last_len();
  if (!responsePtr || responseLength === 0) {
    return { items: [] };
  }
  const responseBytes = new Uint8Array(
    instance.exports.memory.buffer,
    responsePtr,
    responseLength,
  ).slice();
  instance.exports.ianvs_free(responsePtr, responseLength);
  return JSON.parse(decoder.decode(responseBytes));
}

export function resetWasmInstanceForTests() {
  instancePromise = null;
}

async function loadWasmInstance(configuredPath) {
  if (!instancePromise || configuredPath) {
    const wasmPath =
      configuredPath ??
      process.env.IANVS_FIG_COMPLETION_WASM_PATH ??
      defaultWasmPath;
    instancePromise = instantiateWasm(wasmPath);
  }
  return instancePromise;
}

async function instantiateWasm(wasmPath) {
  const bytes = await fs.readFile(wasmPath);
  const { instance } = await WebAssembly.instantiate(bytes, {});
  for (const name of ['memory', 'ianvs_alloc', 'ianvs_free', 'ianvs_complete']) {
    if (!instance.exports[name]) {
      throw new Error(`Fig completion WASM export is missing: ${name}`);
    }
  }
  return instance;
}
