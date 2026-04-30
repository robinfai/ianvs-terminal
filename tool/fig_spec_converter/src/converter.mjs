import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";

const SOURCE_REPOSITORY = "withfig/autocomplete";

export async function convertFigSpecs({ inputDir, outputDir, revision }) {
  const sourceFiles = findSpecFiles(inputDir);
  const specsDir = path.join(outputDir, "specs");
  rmSync(outputDir, { recursive: true, force: true });
  mkdirSync(specsDir, { recursive: true });

  const commands = [];
  const diagnostics = {
    source: { repository: SOURCE_REPOSITORY, revision },
    unsupported: [],
    failed: [],
  };

  for (const file of sourceFiles) {
    const relative = path.relative(inputDir, file);
    try {
      const spec = loadSpecFile(file);
      const normalized = normalizeCommand(spec, {
        specPath: relative,
        diagnostics,
        path: "$",
      });
      if (normalized.name.length === 0) {
        diagnostics.unsupported.push({
          spec: relative,
          path: "$.name",
          reason: "missing command name",
        });
        continue;
      }
      const firstName = normalized.name[0];
      const outputName = safeSpecFileName(firstName);
      const outputPath = `specs/${outputName}`;
      writeJson(path.join(outputDir, outputPath), normalized);
      commands.push({
        name: firstName,
        aliases: normalized.name.slice(1),
        spec: outputPath,
        description: normalized.description,
      });
    } catch (error) {
      diagnostics.failed.push({
        spec: relative,
        reason: error instanceof Error ? error.message : String(error),
      });
    }
  }

  commands.sort((left, right) => left.name.localeCompare(right.name));
  writeJson(path.join(outputDir, "index.json"), {
    source: { repository: SOURCE_REPOSITORY, revision },
    commands,
  });
  writeJson(path.join(outputDir, "diagnostics.json"), diagnostics);

  return {
    converted: commands.length,
    failed: diagnostics.failed.length,
    unsupported: diagnostics.unsupported.length,
  };
}

function findSpecFiles(root) {
  const files = [];
  const visit = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        visit(fullPath);
      } else if (entry.isFile() && entry.name.endsWith(".ts")) {
        files.push(fullPath);
      }
    }
  };
  visit(root);
  return files.sort();
}

function loadSpecFile(file) {
  const source = readFileSync(file, "utf8");
  const transformed = source
    .replace(/^import\s+.*?;$/gm, "")
    .replace(/:\s*Fig\.Spec/g, "")
    .replace(/export\s+default\s+completionSpec\s*;?/g, "")
    .replace(/export\s+default\s+/g, "const completionSpec = ");
  const evaluator = new Function(
    "Fig",
    `${transformed}\nreturn completionSpec;`,
  );
  return evaluator({});
}

function normalizeCommand(command, context) {
  return compactObject({
    name: toNameList(command?.name),
    description: stringOrEmpty(command?.description),
    icon: stringOrNull(command?.icon),
    priority: numberOrNull(command?.priority),
    hidden: command?.hidden === true,
    deprecated: command?.deprecated === true,
    subcommands: normalizeCommandList(command?.subcommands, {
      ...context,
      path: `${context.path}.subcommands`,
    }),
    options: normalizeOptionList(command?.options, {
      ...context,
      path: `${context.path}.options`,
    }),
    args: normalizeArgList(command?.args, {
      ...context,
      path: `${context.path}.args`,
    }),
  });
}

function normalizeCommandList(value, context) {
  return toArray(value).map((entry, index) =>
    normalizeCommand(entry, { ...context, path: `${context.path}[${index}]` }),
  );
}

function normalizeOptionList(value, context) {
  return toArray(value).map((option, index) => {
    const optionPath = `${context.path}[${index}]`;
    return compactObject({
      name: toNameList(option?.name),
      description: stringOrEmpty(option?.description),
      icon: stringOrNull(option?.icon),
      insertValue: stringOrNull(option?.insertValue),
      priority: numberOrNull(option?.priority),
      hidden: option?.hidden === true,
      deprecated: option?.deprecated === true,
      args: normalizeArgList(option?.args, {
        ...context,
        path: `${optionPath}.args`,
      }),
    });
  });
}

function normalizeArgList(value, context) {
  return toArray(value).map((arg, index) => {
    const argPath = `${context.path}[${index}]`;
    return compactObject({
      name: firstString(arg?.name) ?? "",
      description: stringOrEmpty(arg?.description),
      isOptional: arg?.isOptional === true,
      isVariadic: arg?.isVariadic === true,
      suggestions: normalizeSuggestions(arg?.suggestions),
      templates: normalizeTemplates(arg),
      generators: normalizeGenerators(arg?.generators ?? arg?.generator, {
        ...context,
        path: `${argPath}.generators`,
      }),
    });
  });
}

function normalizeSuggestions(value) {
  return toArray(value)
    .map((suggestion) => {
      if (typeof suggestion === "string") {
        return { name: suggestion };
      }
      return compactObject({
        name: firstString(suggestion?.name) ?? "",
        insertValue: stringOrNull(suggestion?.insertValue),
        description: stringOrEmpty(suggestion?.description),
        icon: stringOrNull(suggestion?.icon),
        priority: numberOrNull(suggestion?.priority),
        hidden: suggestion?.hidden === true,
        deprecated: suggestion?.deprecated === true,
      });
    })
    .filter((suggestion) => suggestion.name);
}

function normalizeTemplates(arg) {
  return [
    ...toStringArray(arg?.template),
    ...toStringArray(arg?.templates),
  ].filter((entry, index, all) => all.indexOf(entry) === index);
}

function normalizeGenerators(value, context) {
  return toArray(value)
    .map((generator, index) => {
      const generatorPath = `${context.path}[${index}]`;
      if (!generator || typeof generator !== "object") {
        return null;
      }
      if (typeof generator.custom === "function") {
        context.diagnostics.unsupported.push({
          spec: context.specPath,
          path: `${generatorPath}.custom`,
          reason: "custom generator cannot run in Dart runtime",
        });
      }
      if (typeof generator.postProcess === "function") {
        context.diagnostics.unsupported.push({
          spec: context.specPath,
          path: `${generatorPath}.postProcess`,
          reason: "postProcess function cannot run in Dart runtime",
        });
      }
      if (generator.script != null && typeof generator.script !== "string") {
        context.diagnostics.unsupported.push({
          spec: context.specPath,
          path: `${generatorPath}.script`,
          reason: "function or non-string generator script cannot run in Dart runtime",
        });
        return null;
      }
      if (typeof generator.script !== "string") {
        return null;
      }
      return compactObject({
        script: generator.script,
        splitOn: typeof generator.splitOn === "string" ? generator.splitOn : "\n",
      });
    })
    .filter(Boolean);
}

function toArray(value) {
  if (value == null) {
    return [];
  }
  return Array.isArray(value) ? value : [value];
}

function toNameList(value) {
  return toStringArray(value).filter(Boolean);
}

function toStringArray(value) {
  return toArray(value).filter((entry) => typeof entry === "string");
}

function firstString(value) {
  return toStringArray(value)[0] ?? null;
}

function stringOrEmpty(value) {
  return typeof value === "string" ? value : "";
}

function stringOrNull(value) {
  return typeof value === "string" ? value : null;
}

function numberOrNull(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function compactObject(object) {
  const result = {};
  for (const [key, value] of Object.entries(object)) {
    if (value == null) {
      continue;
    }
    if (Array.isArray(value) && value.length === 0) {
      continue;
    }
    if (value === false || value === "") {
      continue;
    }
    result[key] = value;
  }
  return result;
}

function safeSpecFileName(name) {
  return `${name.replaceAll("/", "_").replaceAll(" ", "_")}.json`;
}

function writeJson(file, value) {
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}
