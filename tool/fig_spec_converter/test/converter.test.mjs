import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { convertFigSpecs } from "../src/converter.mjs";

test("converts serializable Fig TypeScript specs into Ianvs JSON assets", async () => {
  const fixtureDir = path.join(import.meta.dirname, "fixtures", "src");
  const outDir = mkdtempSync(path.join(tmpdir(), "ianvs-fig-specs-"));

  const result = await convertFigSpecs({
    inputDir: fixtureDir,
    outputDir: outDir,
    revision: "fixture-revision",
  });

  assert.equal(result.converted, 1);
  assert.equal(result.failed, 0);

  const index = JSON.parse(readFileSync(path.join(outDir, "index.json"), "utf8"));
  assert.deepEqual(index.source, {
    repository: "withfig/autocomplete",
    revision: "fixture-revision",
  });
  assert.deepEqual(index.commands.map((command) => command.name), ["demo"]);
  assert.equal(index.commands[0].spec, "specs/demo.json");

  const spec = JSON.parse(
    readFileSync(path.join(outDir, "specs", "demo.json"), "utf8"),
  );
  assert.deepEqual(spec.name, ["demo"]);
  assert.equal(spec.subcommands[0].name[0], "run");
  assert.equal(spec.options[1].args[0].templates[0], "filepaths");
  assert.equal(spec.options[2].args[0].generators[0].script, "printf 'alpha\\nbeta\\n'");
});

test("records unsupported Fig functions and custom generators as diagnostics", async () => {
  const fixtureDir = path.join(import.meta.dirname, "fixtures", "src");
  const outDir = mkdtempSync(path.join(tmpdir(), "ianvs-fig-specs-"));

  await convertFigSpecs({
    inputDir: fixtureDir,
    outputDir: outDir,
    revision: "fixture-revision",
  });

  const diagnostics = JSON.parse(
    readFileSync(path.join(outDir, "diagnostics.json"), "utf8"),
  );

  assert.match(
    diagnostics.unsupported.map((entry) => entry.reason).join("\n"),
    /custom generator/,
  );
  assert.equal(diagnostics.failed.length, 0);
});
