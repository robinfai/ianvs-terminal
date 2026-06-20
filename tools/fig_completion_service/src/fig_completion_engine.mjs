import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { specs } from './specs.mjs';

const unsafeInsertText = /[\b\r\n]/;
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

export function complete(input, options = {}) {
  const text = stringValue(input.text);
  const cursorOffset = clampInt(input.cursorOffset, 0, text.length);
  const cwd = stringValue(input.cwd) || process.cwd();
  const recentCommands = Array.isArray(input.recentCommands)
    ? input.recentCommands.filter((item) => typeof item === 'string')
    : [];
  const parsed = parseCommandLine(text, cursorOffset);
  const currentToken = parsed.currentToken;
  const currentValue = currentToken.value;

  if (parsed.contextTokens.length === 0) {
    return responseForSuggestions(
      commandSuggestions(currentValue, currentToken, recentCommands),
      options.limit,
    );
  }

  const commandName = parsed.contextTokens[0].value;
  const rootSpec = findSpec(commandName);
  if (!rootSpec) {
    return responseForSuggestions(
      recentCommandSuggestions(currentValue, currentToken, recentCommands),
      options.limit,
    );
  }

  const resolved = resolveNode(rootSpec, parsed.contextTokens.slice(1));
  const node = resolved.node;
  const activeOption = optionExpectingArgument(
    rootSpec,
    node,
    parsed.contextTokens.slice(1),
  );
  const suggestions = activeOption
    ? argumentSuggestions(
        activeOption,
        currentValue,
        currentToken,
        cwd,
        recentCommands,
        0,
        { rootName: rootSpec.name, argumentTokens: [] },
      )
    : currentValue.startsWith('-')
    ? optionSuggestions(rootSpec, node, currentValue, currentToken)
    : [
        ...subcommandSuggestions(node, currentValue, currentToken, rootSpec.name),
        ...argumentSuggestions(
          node,
          currentValue,
          currentToken,
          cwd,
          recentCommands,
          resolved.argumentTokens.length,
          { rootName: rootSpec.name, argumentTokens: resolved.argumentTokens },
        ),
      ];
  return responseForSuggestions(suggestions, options.limit);
}

export function clearDynamicCompletionCache() {
  dynamicCache.clear();
}

export function parseCommandLine(text, cursorOffset) {
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
    return {
      tokens,
      contextTokens: tokens,
      currentToken: token,
    };
  }
  if (endedOnWhitespace) {
    return {
      tokens,
      contextTokens: tokens,
      currentToken: { value: '', start: cursorOffset, end: cursorOffset },
    };
  }
  return {
    tokens,
    contextTokens: tokens,
    currentToken: { value: '', start: cursorOffset, end: cursorOffset },
  };
}

function commandSuggestions(prefix, currentToken, recentCommands) {
  const normalizedPrefix = prefix.toLowerCase();
  return [
    ...Object.values(specs)
      .filter((spec) => matchesPrefix(spec.name, normalizedPrefix))
      .map((spec) =>
        makeSuggestion({
          name: firstName(spec.name),
          description: spec.description,
          type: 'subcommand',
          source: 'fig:root',
          currentToken,
          priority: 80,
        }),
      ),
    ...recentCommandSuggestions(prefix, currentToken, recentCommands),
  ];
}

function recentCommandSuggestions(prefix, currentToken, recentCommands) {
  const normalizedPrefix = prefix.toLowerCase();
  const seen = new Set();
  const suggestions = [];
  for (const command of recentCommands) {
    const first = command.trim().split(/\s+/, 1)[0] || '';
    if (!first || seen.has(command.toLowerCase())) {
      continue;
    }
    if (normalizedPrefix && !command.toLowerCase().startsWith(normalizedPrefix)) {
      continue;
    }
    seen.add(command.toLowerCase());
    suggestions.push(
      makeSuggestion({
        name: command,
        description: 'Recent command',
        type: 'history',
        source: 'fig:history',
        currentToken,
        priority: 30,
      }),
    );
    if (suggestions.length >= 6) {
      break;
    }
  }
  return suggestions;
}

function optionSuggestions(rootSpec, node, prefix, currentToken) {
  const normalizedPrefix = prefix.toLowerCase();
  const options = [
    ...asArray(rootSpec.options).filter((option) => option.isPersistent),
    ...asArray(node.options),
  ];
  return options.flatMap((option) =>
    namesOf(option.name)
      .filter((name) => matchesPrefix(name, normalizedPrefix))
      .map((name) =>
        makeSuggestion({
          name,
          description: option.description,
          type: 'option',
          source: `fig:${firstName(rootSpec.name)}`,
          currentToken,
          priority: option.priority ?? 70,
          isDangerous: option.isDangerous === true,
        }),
      ),
  );
}

function subcommandSuggestions(node, prefix, currentToken, rootName) {
  const normalizedPrefix = prefix.toLowerCase();
  return asArray(node.subcommands).flatMap((subcommand) =>
    namesOf(subcommand.name)
      .filter((name) => matchesPrefix(name, normalizedPrefix))
      .map((name) =>
        makeSuggestion({
          name,
          displayName: subcommand.displayName,
          description: subcommand.description,
          type: 'subcommand',
          source: `fig:${firstName(rootName)}`,
          currentToken,
          priority: subcommand.priority ?? 75,
          isDangerous: subcommand.isDangerous === true,
        }),
      ),
  );
}

function argumentSuggestions(
  node,
  prefix,
  currentToken,
  cwd,
  recentCommands,
  argumentIndex = 0,
  commandContext = {},
) {
  const args = argSpecsForIndex(node.args, argumentIndex);
  const suggestions = [];
  const rootName = node.name ?? commandContext.rootName;
  for (const arg of args) {
    suggestions.push(...staticArgSuggestions(arg, prefix, currentToken, rootName));
    suggestions.push(
      ...templateSuggestions(arg.template, prefix, currentToken, cwd, {
        ...commandContext,
        arg,
        argumentIndex,
      }),
    );
    if (arg.template === 'history') {
      suggestions.push(...recentCommandSuggestions(prefix, currentToken, recentCommands));
    }
  }
  if (!node.args) {
    suggestions.push(...templateSuggestions(node.template, prefix, currentToken, cwd, commandContext));
  }
  return suggestions;
}

function argSpecsForIndex(args, argumentIndex) {
  const specs = asArray(args);
  if (specs.length <= 1) {
    return specs;
  }
  if (argumentIndex < specs.length) {
    return [specs[argumentIndex]];
  }
  const last = specs[specs.length - 1];
  return last?.isVariadic ? [last] : [];
}

function staticArgSuggestions(arg, prefix, currentToken, rootName) {
  const normalizedPrefix = prefix.toLowerCase();
  return asArray(arg.suggestions)
    .map((suggestion) =>
      typeof suggestion === 'string' ? { name: suggestion } : suggestion,
    )
    .flatMap((suggestion) =>
      namesOf(suggestion.name)
        .filter((name) => matchesPrefix(name, normalizedPrefix))
        .map((name) =>
          makeSuggestion({
            name,
            displayName: suggestion.displayName,
            description: suggestion.description ?? arg.description,
            type: suggestion.type ?? 'arg',
            source: `fig:${firstName(rootName)}`,
            currentToken,
            priority: suggestion.priority ?? 55,
            isDangerous: suggestion.isDangerous === true || arg.isDangerous === true,
          }),
        ),
    );
}

function templateSuggestions(template, prefix, currentToken, cwd, commandContext = {}) {
  const templates = asArray(template);
  const suggestions = [];
  for (const templateName of templates) {
    if (templateName === 'filepaths' || templateName === 'folders') {
      suggestions.push(
        ...pathTemplateSuggestions({
          foldersOnly: templateName === 'folders',
          prefix,
          currentToken,
          cwd,
        }),
      );
      continue;
    }
    suggestions.push(
      ...dynamicTemplateSuggestions(templateName, prefix, currentToken, commandContext),
    );
  }
  return suggestions;
}

function pathTemplateSuggestions({ foldersOnly, prefix, currentToken, cwd }) {
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
    .filter((entry) => !normalizedBase || entry.name.toLowerCase().startsWith(normalizedBase))
    .sort(comparePathEntries)
    .slice(0, 16)
    .map((entry) => {
      const suffix = entry.isDirectory() ? '/' : '';
      const insertText = `${parsedPath.directory}${entry.name}${suffix}`;
      return makeSuggestion({
        name: insertText,
        description: entry.isDirectory() ? 'Folder' : 'File',
        type: entry.isDirectory() ? 'folder' : 'file',
        source: foldersOnly ? 'fig:folders' : 'fig:filepaths',
        currentToken,
        priority: entry.isDirectory() ? 70 : 45,
      });
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

function dynamicTemplateSuggestions(templateName, prefix, currentToken, commandContext) {
  if (templateName === 'kubeContexts') {
    return kubectlLineSuggestions({
      cacheKey: 'contexts',
      args: ['config', 'get-contexts', '-o', 'name'],
      prefix,
      currentToken,
      description: 'Kubernetes context',
      type: 'context',
      source: 'fig:kubectl',
      priority: 66,
    });
  }
  if (templateName === 'kubeNamespaces') {
    return kubectlJsonItemSuggestions({
      cacheKey: 'namespaces',
      args: ['get', 'namespaces', '-o', 'json'],
      prefix,
      currentToken,
      descriptionFor: () => 'Kubernetes namespace',
      type: 'namespace',
      priority: 66,
    });
  }
  if (templateName === 'kubeResourceTypes') {
    const suggestions = kubectlLineSuggestions({
      cacheKey: 'api-resources',
      args: ['api-resources', '--verbs=list', '-o', 'name'],
      prefix,
      currentToken,
      description: 'Kubernetes resource type',
      type: 'resource',
      source: 'fig:kubectl',
      priority: 64,
    });
    if (suggestions.length > 0) {
      return suggestions;
    }
    return fallbackKubeResources
      .filter((name) => matchesPrefix(name, prefix.toLowerCase()))
      .map((name) =>
        makeSuggestion({
          name,
          description: 'Kubernetes resource type',
          type: 'resource',
          source: 'fig:kubectl',
          currentToken,
          priority: 50,
        }),
      );
  }
  if (templateName === 'kubeResourceNames') {
    const resource = commandContext.argumentTokens?.[0]?.value;
    if (!resource || resource.startsWith('-')) {
      return [];
    }
    return kubectlJsonItemSuggestions({
      cacheKey: `resources:${resource}`,
      args: ['get', resource, '-A', '-o', 'json'],
      prefix,
      currentToken,
      descriptionFor: (item) =>
        item.metadata?.namespace
          ? `${resource} in ${item.metadata.namespace}`
          : resource,
      type: 'resource',
      priority: 58,
    });
  }
  if (templateName === 'kubePodNames') {
    return kubectlJsonItemSuggestions({
      cacheKey: 'pods',
      args: ['get', 'pods', '-A', '-o', 'json'],
      prefix,
      currentToken,
      descriptionFor: (item) =>
        item.metadata?.namespace
          ? `Pod in ${item.metadata.namespace}`
          : 'Kubernetes pod',
      type: 'pod',
      priority: 62,
    });
  }
  return [];
}

function kubectlLineSuggestions({
  cacheKey,
  args,
  prefix,
  currentToken,
  description,
  type,
  source,
  priority,
}) {
  const normalizedPrefix = prefix.toLowerCase();
  return cachedKubectlLines(cacheKey, args)
    .filter((name) => matchesPrefix(name, normalizedPrefix))
    .slice(0, 24)
    .map((name) =>
      makeSuggestion({
        name,
        description,
        type,
        source,
        currentToken,
        priority,
      }),
    );
}

function kubectlJsonItemSuggestions({
  cacheKey,
  args,
  prefix,
  currentToken,
  descriptionFor,
  type,
  priority,
}) {
  const normalizedPrefix = prefix.toLowerCase();
  return cachedKubectlJson(cacheKey, args)
    .filter((item) => typeof item.metadata?.name === 'string')
    .filter((item) => matchesPrefix(item.metadata.name, normalizedPrefix))
    .slice(0, 24)
    .map((item) =>
      makeSuggestion({
        name: item.metadata.name,
        description: descriptionFor(item),
        type,
        source: 'fig:kubectl',
        currentToken,
        priority,
      }),
    );
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

function resolveNode(rootSpec, tokens) {
  let node = rootSpec;
  const argumentTokens = [];
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!token.value || token.value.startsWith('-')) {
      const option = findOption(rootSpec, node, token.value);
      if (optionTakesSeparateArgument(option, token.value) && tokens[index + 1]) {
        index += 1;
      }
      continue;
    }
    const next = asArray(node.subcommands).find((candidate) =>
      namesOf(candidate.name).includes(token.value),
    );
    if (!next) {
      argumentTokens.push(token);
      continue;
    }
    node = next;
  }
  return { node, argumentTokens };
}

function optionExpectingArgument(rootSpec, node, tokens) {
  const previous = tokens[tokens.length - 1];
  if (!previous || previous.value.includes('=')) {
    return null;
  }
  const option = findOption(rootSpec, node, previous.value);
  return optionTakesSeparateArgument(option, previous.value) ? option.args : null;
}

function findOption(rootSpec, node, value) {
  const optionName = value.includes('=') ? value.slice(0, value.indexOf('=')) : value;
  return [...asArray(rootSpec.options).filter((option) => option.isPersistent), ...asArray(node.options)]
    .find((option) => namesOf(option.name).includes(optionName));
}

function optionTakesSeparateArgument(option, value) {
  return option?.args && !value.includes('=');
}

function findSpec(name) {
  return Object.values(specs).find((spec) => namesOf(spec.name).includes(name));
}

function responseForSuggestions(suggestions, limit = 12) {
  const seen = new Set();
  const items = suggestions
    .filter((item) => item && !unsafeInsertText.test(item.insertText ?? item.name))
    .sort((left, right) => (right.priority ?? 50) - (left.priority ?? 50))
    .filter((item) => {
      const key = `${item.insertText}|${item.type}`;
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    })
    .slice(0, limit);
  return { items };
}

function makeSuggestion({
  name,
  displayName,
  description,
  type,
  source,
  currentToken,
  priority = 50,
  isDangerous = false,
}) {
  const insertText = firstName(name);
  return {
    name: insertText,
    displayName,
    insertText,
    replaceStart: currentToken.start,
    replaceEnd: currentToken.end,
    cursorOffset: currentToken.start + insertText.length,
    description,
    type,
    source,
    priority,
    isDangerous,
  };
}

function matchesPrefix(name, normalizedPrefix) {
  if (!normalizedPrefix) {
    return true;
  }
  return firstName(name).toLowerCase().startsWith(normalizedPrefix);
}

function firstName(name) {
  return Array.isArray(name) ? name[0] : name;
}

function namesOf(name) {
  return asArray(name).filter((item) => typeof item === 'string' && item);
}

function asArray(value) {
  if (value == null) {
    return [];
  }
  return Array.isArray(value) ? value : [value];
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function clampInt(value, min, max) {
  const number = Number.isInteger(value) ? value : max;
  return Math.max(min, Math.min(max, number));
}
