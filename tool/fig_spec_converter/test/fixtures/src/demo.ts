const completionSpec: Fig.Spec = {
  name: "demo",
  description: "Demo command",
  subcommands: [
    {
      name: "run",
      description: "Run a target",
      args: {
        name: "target",
        suggestions: [
          { name: "web", description: "Run web target" },
          "native",
        ],
      },
    },
  ],
  options: [
    {
      name: ["-v", "--verbose"],
      description: "Verbose output",
    },
    {
      name: "--config",
      description: "Config path",
      args: {
        name: "file",
        template: "filepaths",
      },
    },
    {
      name: "--generated",
      description: "Generated value",
      args: {
        name: "value",
        generators: {
          script: "printf 'alpha\\nbeta\\n'",
          splitOn: "\\n",
        },
      },
    },
    {
      name: "--custom",
      args: {
        name: "value",
        generators: {
          custom: async () => ["skip"],
        },
      },
    },
  ],
};

export default completionSpec;
