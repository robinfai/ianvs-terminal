import { convertFigSpecs } from "./converter.mjs";

const inputDir = process.env.FIG_AUTOCOMPLETE_DIR;
const outputDir = process.env.FIG_SPECS_OUTPUT_DIR ?? "assets/fig_specs";
const revision =
  process.env.FIG_AUTOCOMPLETE_REVISION ??
  "aef52acff84c45edde61ae610cc2c964802b9a38";

if (!inputDir) {
  console.error("FIG_AUTOCOMPLETE_DIR is required");
  process.exitCode = 2;
} else {
  const result = await convertFigSpecs({ inputDir, outputDir, revision });
  console.log(
    `Converted ${result.converted} Fig specs, failed ${result.failed}.`,
  );
}
