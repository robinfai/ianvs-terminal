import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const dynamicCache = new Map();
const dynamicCacheTtlMs = 2000;
const kubectlTimeoutMs = 900;
const fallbackKubeResources = [
  'pods',
  'deployments',
  'services',
  'namespaces',
  'nodes',
  'configmaps',
  'secrets',
  'ingresses',
  'jobs',
  'cronjobs',
  'statefulsets',
  'daemonsets',
];

export function clearHostProviderCache() {
  dynamicCache.clear();
}

export function collectHostTemplateSuggestions(input) {
  const text = stringValue(input.text);
  const cursorOffset = clampInt(input.cursorOffset, 0, text.length);
  const cwd = stringValue(input.cwd) || process.cwd();
  const parsed = parseCommandLine(text, cursorOffset);
  const prefix = parsed.currentToken.value;
  const hostTemplates = {
    filepaths: pathTemplateSuggestions({ foldersOnly: false, prefix, cwd }),
    folders: pathTemplateSuggestions({ foldersOnly: true, prefix, cwd }),
  };

  const rootCommand = parsed.contextTokens[0]?.value;
  if (rootCommand === 'kubectl' || rootCommand === 'k') {
    const resource = kubectlResourceFromContext(parsed.contextTokens.slice(1));
    hostTemplates.kubeContexts = kubectlLineSuggestions({
      cacheKey: 'contexts',
      args: ['config', 'get-contexts', '-o', 'name'],
      prefix,
      description: 'Kubernetes context',
      type: 'context',
      source: 'fig:kubectl',
      priority: 66,
    });
    hostTemplates.kubeNamespaces = kubectlJsonItemSuggestions({
      cacheKey: 'namespaces',
      args: ['get', 'namespaces', '-o', 'json'],
      prefix,
      descriptionFor: () => 'Kubernetes namespace',
      type: 'namespace',
      priority: 66,
    });
    hostTemplates.kubeResourceTypes = kubectlLineSuggestions({
      cacheKey: 'api-resources',
      args: ['api-resources', '--verbs=list', '-o', 'name'],
      prefix,
      description: 'Kubernetes resource type',
      type: 'resource',
      source: 'fig:kubectl',
      priority: 64,
    });
    if (hostTemplates.kubeResourceTypes.length === 0) {
      const normalizedPrefix = prefix.toLowerCase();
      hostTemplates.kubeResourceTypes = fallbackKubeResources
        .filter((name) => matchesPrefix(name, normalizedPrefix))
        .map((name) => ({
          name,
          description: 'Kubernetes resource type',
          type: 'resource',
          source: 'fig:kubectl',
          priority: 50,
        }));
    }
    if (resource && !resource.startsWith('-')) {
      hostTemplates.kubeResourceNames = kubectlJsonItemSuggestions({
        cacheKey: `resources:${resource}`,
        args: ['get', resource, '-A', '-o', 'json'],
        prefix,
        descriptionFor: (item) =>
          item.metadata?.namespace
            ? `${resource} in ${item.metadata.namespace}`
            : resource,
        type: 'resource',
        priority: 58,
      });
    }
    hostTemplates.kubePodNames = kubectlJsonItemSuggestions({
      cacheKey: 'pods',
      args: ['get', 'pods', '-A', '-o', 'json'],
      prefix,
      descriptionFor: (item) =>
        item.metadata?.namespace
          ? `Pod in ${item.metadata.namespace}`
          : 'Kubernetes pod',
      type: 'pod',
      priority: 62,
    });
  }

  return hostTemplates;
}

function parseCommandLine(text, cursorOffset) {
  const beforeCursor = text.slice(0, cursorOffset);
  const tokens = [];
  let token = null;
  let quote = null;
  let escaped = false;

  for (let index = 0; index < beforeCursor.length; index += 1) {
    const char = beforeCursor[index];
    if (!token) {
      if (/\s/.test(char)) {
        continue;
      }
      token = { value: '', start: index, end: index };
    }

    if (escaped) {
      token.value += char;
      token.end = index + 1;
      escaped = false;
      continue;
    }
    if (char === '\\' && quote !== "'") {
      token.end = index + 1;
      escaped = true;
      continue;
    }
    if (quote) {
      if (char === quote) {
        quote = null;
      } else {
        token.value += char;
      }
      token.end = index + 1;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      token.end = index + 1;
      continue;
    }
    if (/\s/.test(char)) {
      tokens.push(token);
      token = null;
      continue;
    }
    token.value += char;
    token.end = index + 1;
  }

  const endedOnWhitespace =
    beforeCursor.length > 0 && /\s/.test(beforeCursor[beforeCursor.length - 1]);
  if (token) {
    return { contextTokens: tokens, currentToken: token };
  }
  if (endedOnWhitespace) {
    return {
      contextTokens: tokens,
      currentToken: { value: '', start: cursorOffset, end: cursorOffset },
    };
  }
  return {
    contextTokens: tokens,
    currentToken: { value: '', start: cursorOffset, end: cursorOffset },
  };
}

function pathTemplateSuggestions({ foldersOnly, prefix, cwd }) {
  const parsedPath = splitPathPrefix(prefix);
  const directory = path.resolve(cwd, parsedPath.directory || '.');
  let entries = [];
  try {
    entries = fs.readdirSync(directory, { withFileTypes: true });
  } catch {
    return [];
  }
  const normalizedBase = parsedPath.base.toLowerCase();
  return entries
    .filter((entry) => !foldersOnly || entry.isDirectory())
    .filter(
      (entry) =>
        !normalizedBase || entry.name.toLowerCase().startsWith(normalizedBase),
    )
    .sort(comparePathEntries)
    .slice(0, 16)
    .map((entry) => {
      const suffix = entry.isDirectory() ? '/' : '';
      const name = `${parsedPath.directory}${entry.name}${suffix}`;
      return {
        name,
        description: entry.isDirectory() ? 'Folder' : 'File',
        type: entry.isDirectory() ? 'folder' : 'file',
        source: foldersOnly ? 'fig:folders' : 'fig:filepaths',
        priority: entry.isDirectory() ? 70 : 45,
      };
    });
}

function comparePathEntries(left, right) {
  if (left.isDirectory() !== right.isDirectory()) {
    return left.isDirectory() ? -1 : 1;
  }
  const leftHidden = left.name.startsWith('.');
  const rightHidden = right.name.startsWith('.');
  if (leftHidden !== rightHidden) {
    return leftHidden ? 1 : -1;
  }
  return left.name.localeCompare(right.name);
}

function splitPathPrefix(prefix) {
  if (!prefix || !prefix.includes('/')) {
    return { directory: '', base: prefix || '' };
  }
  const slash = prefix.lastIndexOf('/');
  return {
    directory: prefix.slice(0, slash + 1),
    base: prefix.slice(slash + 1),
  };
}

function kubectlResourceFromContext(tokens) {
  let sawResourceCommand = false;
  for (let index = 0; index < tokens.length; index += 1) {
    const value = tokens[index].value;
    if (!value) {
      continue;
    }
    if (value.startsWith('-')) {
      if (kubectlOptionTakesValue(value) && tokens[index + 1]) {
        index += 1;
      }
      continue;
    }
    if (!sawResourceCommand) {
      sawResourceCommand = ['get', 'describe', 'delete', 'scale'].includes(value);
      continue;
    }
    return value;
  }
  return null;
}

function kubectlOptionTakesValue(value) {
  const optionName = value.includes('=') ? value.slice(0, value.indexOf('=')) : value;
  return ['-n', '--namespace', '--context', '--kubeconfig', '-o', '--output'].includes(
    optionName,
  );
}

function kubectlLineSuggestions({
  cacheKey,
  args,
  prefix,
  description,
  type,
  source,
  priority,
}) {
  const normalizedPrefix = prefix.toLowerCase();
  return cachedKubectlLines(cacheKey, args)
    .filter((name) => matchesPrefix(name, normalizedPrefix))
    .slice(0, 24)
    .map((name) => ({
      name,
      description,
      type,
      source,
      priority,
    }));
}

function kubectlJsonItemSuggestions({
  cacheKey,
  args,
  prefix,
  descriptionFor,
  type,
  priority,
}) {
  const normalizedPrefix = prefix.toLowerCase();
  return cachedKubectlJson(cacheKey, args)
    .filter((item) => typeof item.metadata?.name === 'string')
    .filter((item) => matchesPrefix(item.metadata.name, normalizedPrefix))
    .slice(0, 24)
    .map((item) => ({
      name: item.metadata.name,
      description: descriptionFor(item),
      type,
      source: 'fig:kubectl',
      priority,
    }));
}

function cachedKubectlLines(cacheKey, args) {
  const value = cachedValue(`kubectl:${cacheKey}`, () =>
    execKubectl(args)
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean),
  );
  return Array.isArray(value) ? value : [];
}

function cachedKubectlJson(cacheKey, args) {
  const value = cachedValue(`kubectl:${cacheKey}`, () => {
    const payload = JSON.parse(execKubectl(args));
    return Array.isArray(payload.items) ? payload.items : [];
  });
  return Array.isArray(value) ? value : [];
}

function cachedValue(cacheKey, loader) {
  const now = Date.now();
  const existing = dynamicCache.get(cacheKey);
  if (existing && now - existing.timestamp < dynamicCacheTtlMs) {
    return existing.value;
  }
  try {
    const value = loader();
    dynamicCache.set(cacheKey, { timestamp: now, value });
    return value;
  } catch {
    dynamicCache.set(cacheKey, { timestamp: now, value: [] });
    return [];
  }
}

function execKubectl(args) {
  return execFileSync('kubectl', args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
    timeout: kubectlTimeoutMs,
  });
}

function matchesPrefix(name, normalizedPrefix) {
  return !normalizedPrefix || name.toLowerCase().startsWith(normalizedPrefix);
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function clampInt(value, min, max) {
  const number = Number.isInteger(value) ? value : max;
  return Math.max(min, Math.min(max, number));
}
