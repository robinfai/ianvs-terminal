export const specs = {
  cd: {
    name: 'cd',
    description: 'Change directory',
    args: { name: 'directory', template: 'folders' },
  },
  ls: {
    name: 'ls',
    description: 'List directory contents',
    options: [
      { name: ['-a', '--all'], description: 'Show hidden entries' },
      { name: ['-l'], description: 'Use long listing format' },
      { name: ['-h', '--human-readable'], description: 'Human sizes' },
      { name: ['-R', '--recursive'], description: 'List recursively' },
    ],
    args: { name: 'path', template: ['filepaths', 'folders'], isVariadic: true },
  },
  cat: {
    name: 'cat',
    description: 'Print files',
    options: [
      { name: ['-n', '--number'], description: 'Number output lines' },
      { name: ['-b', '--number-nonblank'], description: 'Number non-empty lines' },
    ],
    args: { name: 'file', template: 'filepaths', isVariadic: true },
  },
  git: {
    name: 'git',
    description: 'Distributed version control',
    options: [
      { name: ['-C'], description: 'Run as if git was started in path', args: { template: 'folders' } },
      { name: ['--help'], description: 'Show help' },
      { name: ['--version'], description: 'Show version' },
    ],
    subcommands: [
      {
        name: 'add',
        description: 'Add file contents to the index',
        options: [
          { name: ['-A', '--all'], description: 'Add all changes' },
          { name: ['-p', '--patch'], description: 'Interactively choose hunks' },
        ],
        args: { name: 'pathspec', template: 'filepaths', isVariadic: true },
      },
      {
        name: ['checkout', 'co'],
        description: 'Switch branches or restore files',
        options: [
          { name: ['-b'], description: 'Create and checkout a new branch' },
          { name: ['--detach'], description: 'Detach HEAD' },
          { name: ['--track'], description: 'Set up upstream tracking' },
        ],
        args: {
          name: 'branch',
          suggestions: ['main', 'master', 'develop', 'HEAD'],
        },
      },
      {
        name: 'cherry-pick',
        description: 'Apply changes introduced by commits',
        options: [
          { name: ['--continue'], description: 'Continue after resolving conflicts' },
          { name: ['--abort'], description: 'Cancel the operation' },
          { name: ['-n', '--no-commit'], description: 'Do not automatically commit' },
        ],
      },
      {
        name: 'commit',
        description: 'Record changes to the repository',
        options: [
          { name: ['-m', '--message'], description: 'Use the given commit message', args: { name: 'message' } },
          { name: ['--amend'], description: 'Amend the previous commit' },
          { name: ['--no-edit'], description: 'Reuse the selected commit message' },
          { name: ['-s', '--signoff'], description: 'Add Signed-off-by trailer' },
        ],
      },
      {
        name: 'diff',
        description: 'Show changes',
        options: [
          { name: ['--cached', '--staged'], description: 'Compare staged changes' },
          { name: ['--stat'], description: 'Generate a diffstat' },
          { name: ['--name-only'], description: 'Show only changed names' },
        ],
        args: { name: 'path', template: 'filepaths', isVariadic: true },
      },
      {
        name: 'log',
        description: 'Show commit logs',
        options: [
          { name: ['--oneline'], description: 'Show one commit per line' },
          { name: ['--graph'], description: 'Draw commit graph' },
          { name: ['--decorate'], description: 'Print ref names' },
        ],
      },
      {
        name: 'push',
        description: 'Update remote refs',
        options: [
          { name: ['-u', '--set-upstream'], description: 'Set upstream for git pull/status' },
          { name: ['--force-with-lease'], description: 'Force safely if remote did not move', isDangerous: true },
          { name: ['--tags'], description: 'Push tags' },
        ],
      },
      { name: 'pull', description: 'Fetch from and integrate with another repository' },
      { name: 'status', description: 'Show working tree status' },
      { name: 'switch', description: 'Switch branches', args: { suggestions: ['main', 'master', 'develop'] } },
      { name: 'restore', description: 'Restore working tree files', args: { template: 'filepaths' } },
      { name: 'stash', description: 'Stash local changes' },
      { name: 'branch', description: 'List, create, or delete branches' },
    ],
  },
  flutter: {
    name: 'flutter',
    description: 'Flutter command-line tool',
    options: [
      { name: ['--version'], description: 'Show Flutter version' },
      { name: ['-v', '--verbose'], description: 'Verbose logging' },
      { name: ['--suppress-analytics'], description: 'Suppress analytics for this run' },
    ],
    subcommands: [
      {
        name: 'test',
        description: 'Run Flutter tests',
        options: [
          { name: ['--plain-name'], description: 'Run tests matching a name' },
          { name: ['--coverage'], description: 'Collect coverage' },
          { name: ['-d', '--device-id'], description: 'Target device id', args: { suggestions: ['macos', 'chrome'] } },
        ],
        args: { template: 'filepaths', isOptional: true },
      },
      { name: 'analyze', description: 'Analyze project Dart code' },
      { name: 'doctor', description: 'Show Flutter installation status' },
      { name: 'devices', description: 'List connected devices' },
      {
        name: 'run',
        description: 'Run the app',
        options: [
          { name: ['-d', '--device-id'], description: 'Target device id', args: { suggestions: ['macos', 'chrome'] } },
          { name: ['--dart-define'], description: 'Define a compile-time variable' },
        ],
      },
      {
        name: 'pub',
        description: 'Work with packages',
        subcommands: [
          { name: 'add', description: 'Add dependencies', args: { name: 'package' } },
          { name: 'get', description: 'Get packages' },
          { name: 'upgrade', description: 'Upgrade packages' },
          { name: 'run', description: 'Run an executable from a package' },
        ],
      },
      { name: 'build', description: 'Build an executable app' },
    ],
  },
  dart: {
    name: 'dart',
    description: 'Dart command-line tool',
    subcommands: [
      { name: 'analyze', description: 'Analyze Dart code' },
      { name: 'format', description: 'Format Dart code', args: { template: 'filepaths', isVariadic: true } },
      { name: 'test', description: 'Run tests', args: { template: 'filepaths', isOptional: true } },
      { name: 'run', description: 'Run a Dart program' },
      {
        name: 'pub',
        description: 'Work with packages',
        subcommands: [
          { name: 'add', description: 'Add dependencies' },
          { name: 'get', description: 'Get packages' },
          { name: 'upgrade', description: 'Upgrade dependencies' },
        ],
      },
    ],
  },
  kubectl: {
    name: ['kubectl', 'k'],
    description: 'Kubernetes command-line tool',
    options: [
      {
        name: ['-n', '--namespace'],
        description: 'Target namespace',
        args: { name: 'namespace', template: 'kubeNamespaces' },
        isPersistent: true,
      },
      {
        name: ['--context'],
        description: 'Target kubeconfig context',
        args: { name: 'context', template: 'kubeContexts' },
        isPersistent: true,
      },
      {
        name: ['--kubeconfig'],
        description: 'Path to the kubeconfig file',
        args: { name: 'file', template: 'filepaths' },
        isPersistent: true,
      },
      {
        name: ['-A', '--all-namespaces'],
        description: 'List resources across all namespaces',
        isPersistent: true,
      },
      {
        name: ['-o', '--output'],
        description: 'Output format',
        args: {
          name: 'format',
          suggestions: ['wide', 'yaml', 'json', 'name', 'jsonpath='],
        },
        isPersistent: true,
      },
      { name: ['--help'], description: 'Show help', isPersistent: true },
    ],
    subcommands: [
      {
        name: 'get',
        description: 'Display one or many resources',
        options: [
          { name: ['--watch', '-w'], description: 'Watch changes' },
          { name: ['--show-labels'], description: 'Show labels as columns' },
          { name: ['--selector', '-l'], description: 'Filter by label selector', args: { name: 'selector' } },
        ],
        args: [
          { name: 'resource', template: 'kubeResourceTypes' },
          { name: 'name', template: 'kubeResourceNames', isOptional: true, isVariadic: true },
        ],
      },
      {
        name: 'describe',
        description: 'Show details of a resource',
        args: [
          { name: 'resource', template: 'kubeResourceTypes' },
          { name: 'name', template: 'kubeResourceNames', isOptional: true, isVariadic: true },
        ],
      },
      {
        name: 'delete',
        description: 'Delete resources',
        isDangerous: true,
        options: [
          { name: ['--dry-run'], description: 'Preview the delete request' },
          { name: ['--force'], description: 'Force immediate deletion', isDangerous: true },
        ],
        args: [
          { name: 'resource', template: 'kubeResourceTypes' },
          { name: 'name', template: 'kubeResourceNames', isOptional: true, isVariadic: true },
        ],
      },
      {
        name: 'logs',
        description: 'Print pod logs',
        options: [
          { name: ['-f', '--follow'], description: 'Follow log output' },
          { name: ['--previous', '-p'], description: 'Print logs from the previous container' },
          { name: ['--tail'], description: 'Number of recent lines to show', args: { name: 'lines' } },
        ],
        args: { name: 'pod', template: 'kubePodNames' },
      },
      {
        name: 'exec',
        description: 'Execute a command in a container',
        options: [
          { name: ['-it'], description: 'Use stdin and a TTY' },
          { name: ['--container', '-c'], description: 'Container name', args: { name: 'container' } },
        ],
        args: { name: 'pod', template: 'kubePodNames' },
      },
      {
        name: 'apply',
        description: 'Apply a configuration to a resource',
        options: [
          { name: ['-f', '--filename'], description: 'File, directory, or URL', args: { template: ['filepaths', 'folders'] } },
          { name: ['--server-side'], description: 'Use server-side apply' },
          { name: ['--dry-run'], description: 'Preview the apply request' },
        ],
        args: { name: 'file', template: ['filepaths', 'folders'], isOptional: true },
      },
      {
        name: 'create',
        description: 'Create resources',
        subcommands: [
          { name: 'deployment', description: 'Create a deployment', args: { name: 'name' } },
          { name: 'service', description: 'Create a service' },
          { name: 'namespace', description: 'Create a namespace', args: { name: 'name' } },
          { name: 'configmap', description: 'Create a config map', args: { name: 'name' } },
          { name: 'secret', description: 'Create a secret' },
        ],
      },
      {
        name: 'config',
        description: 'Modify kubeconfig files',
        subcommands: [
          { name: 'get-contexts', description: 'Display contexts' },
          { name: 'current-context', description: 'Display the current context' },
          { name: 'use-context', description: 'Set the current context', args: { name: 'context', template: 'kubeContexts' } },
          { name: 'set-context', description: 'Set a context entry', args: { name: 'context', template: 'kubeContexts' } },
        ],
      },
      {
        name: 'rollout',
        description: 'Manage rollout state',
        subcommands: [
          { name: 'status', description: 'Show rollout status', args: { name: 'resource', suggestions: ['deployment', 'daemonset', 'statefulset'] } },
          { name: 'restart', description: 'Restart a resource', args: { name: 'resource', suggestions: ['deployment', 'daemonset', 'statefulset'] } },
          { name: 'history', description: 'View rollout history', args: { name: 'resource', suggestions: ['deployment', 'daemonset', 'statefulset'] } },
          { name: 'undo', description: 'Undo a rollout', args: { name: 'resource', suggestions: ['deployment', 'daemonset', 'statefulset'] } },
        ],
      },
      {
        name: 'scale',
        description: 'Set a new size for resources',
        args: [
          { name: 'resource', template: 'kubeResourceTypes' },
          { name: 'name', template: 'kubeResourceNames', isOptional: true },
        ],
      },
      { name: 'port-forward', description: 'Forward local ports to a pod', args: { name: 'pod', template: 'kubePodNames' } },
      { name: 'top', description: 'Display resource usage', subcommands: [{ name: 'pod', description: 'Display pod usage' }, { name: 'node', description: 'Display node usage' }] },
      { name: 'explain', description: 'Get documentation for a resource', args: { name: 'resource', template: 'kubeResourceTypes' } },
      { name: 'api-resources', description: 'Print supported API resources' },
      { name: 'cluster-info', description: 'Display cluster information' },
      { name: 'version', description: 'Print client and server version' },
    ],
  },
  npm: {
    name: 'npm',
    description: 'Node package manager',
    subcommands: [
      { name: 'install', description: 'Install packages', args: { name: 'package', isVariadic: true } },
      { name: 'run', description: 'Run a package script', args: { suggestions: ['dev', 'build', 'test', 'lint', 'start'] } },
      { name: 'test', description: 'Run package tests' },
      { name: 'start', description: 'Start package' },
      { name: 'exec', description: 'Run a package binary' },
      { name: 'update', description: 'Update packages' },
    ],
    options: [
      { name: ['--workspace'], description: 'Run in a workspace' },
      { name: ['--prefix'], description: 'Run command in path', args: { template: 'folders' } },
      { name: ['--global', '-g'], description: 'Use global mode' },
    ],
  },
};
