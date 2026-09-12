import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'shell_connection_chain.dart';
import 'shell_integration_capabilities.dart';

/// A live view receives the originating pane's capabilities from its caller.
/// It never changes injection settings or starts remote commands.
class ShellCapabilitiesDialog extends StatelessWidget {
  const ShellCapabilitiesDialog({
    super.key,
    required this.sessionTitle,
    required this.capabilities,
    required this.onClose,
    this.bootstrapPhase,
    this.bootstrapSource,
    this.registrationChecks = const {},
    this.connectionChain = const [],
    this.sessionExited = false,
  });

  final String sessionTitle;
  final ShellIntegrationCapabilities capabilities;
  final VoidCallback onClose;
  final String? bootstrapPhase;
  final String? bootstrapSource;
  final Map<String, String> registrationChecks;
  final List<ShellConnectionHop> connectionChain;
  final bool sessionExited;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appTheme.spacing;
    final media = MediaQuery.of(context);
    final active = capabilities.entries.values
        .where((entry) => entry.isActive)
        .length;
    final phase = switch (bootstrapPhase) {
      'checking' => l10n.shellBootstrapChecking,
      'ready' => l10n.shellBootstrapReady,
      'degraded' => l10n.shellBootstrapDegraded,
      _ => l10n.shellCapabilityPending,
    };
    final source = switch (bootstrapSource) {
      'installed' => l10n.shellBootstrapInstalled,
      'checked' => l10n.shellBootstrapChecked,
      'reused' => l10n.shellBootstrapReused,
      'timeout' => l10n.shellBootstrapTimeout,
      'unsupported' => l10n.shellBootstrapUnsupported,
      'hook_conflict' => l10n.shellBootstrapConflict,
      'helpers_missing' => l10n.shellBootstrapMissingHelpers,
      _ => null,
    };
    return AppDialogScaffold(
      title: l10n.shellCapabilities,
      onClose: onClose,
      width: 620,
      height:
          (media.size.height -
                  media.viewInsets.bottom -
                  media.padding.vertical -
                  spacing.lg * 2)
              .clamp(0.0, 720.0),
      insetPadding: EdgeInsets.all(spacing.lg),
      expandBody: true,
      body: SingleChildScrollView(
        key: const Key('shell-capabilities-list'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sessionTitle, style: Theme.of(context).textTheme.titleSmall),
            SizedBox(height: spacing.sm),
            if (connectionChain.isNotEmpty) ...[
              _ConnectionChain(hops: connectionChain, exited: sessionExited),
              SizedBox(height: spacing.lg),
            ],
            if (bootstrapPhase != null) ...[
              Text(
                phase,
                key: const Key('shell-bootstrap-status'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (source != null)
                Text(source, style: Theme.of(context).textTheme.bodySmall),
              SizedBox(height: spacing.sm),
            ],
            Text(
              l10n.shellCapabilitiesCount(
                active,
                ShellIntegrationCapability.values.length,
              ),
            ),
            SizedBox(height: spacing.sm),
            Text(
              l10n.shellCapabilitiesExplanation,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final localHook in [true, false]) ...[
              Padding(
                padding: EdgeInsets.only(top: spacing.lg, bottom: spacing.sm),
                child: Text(
                  localHook
                      ? l10n.shellCapabilitiesBuiltIn
                      : l10n.shellCapabilitiesExtensions,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final capability in ShellIntegrationCapability.values.where(
                (capability) => capability.localHook == localHook,
              )) ...[
                _CapabilityRow(
                  capability: capability,
                  activation: capabilities[capability],
                  registration: registrationChecks[capability.id],
                ),
                const Divider(),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionChain extends StatelessWidget {
  const _ConnectionChain({required this.hops, required this.exited});

  final List<ShellConnectionHop> hops;
  final bool exited;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final tokens = context.appTheme;
    final spacing = tokens.spacing;
    final sshCount = hops
        .where(
          (hop) =>
              hop.kind == ShellConnectionHopKind.sshShell ||
              hop.kind == ShellConnectionHopKind.jump,
        )
        .length;
    return Column(
      key: const Key('shell-connection-chain'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: spacing.md,
          runSpacing: spacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.shellConnectionChain, style: theme.textTheme.titleSmall),
            if (sshCount > 0)
              Text(
                l10n.shellChainJumpCount(sshCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        SizedBox(height: spacing.sm),
        for (var index = 0; index < hops.length; index++)
          _ConnectionHopRow(
            hop: hops[index],
            index: index,
            first: index == 0,
            current: index == hops.length - 1,
            exited: exited,
          ),
        SizedBox(height: spacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: l10n.shellConnectionChainHelp,
              child: Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                l10n.shellChainScope,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConnectionHopRow extends StatelessWidget {
  const _ConnectionHopRow({
    required this.hop,
    required this.index,
    required this.first,
    required this.current,
    required this.exited,
  });

  final ShellConnectionHop hop;
  final int index;
  final bool first;
  final bool current;
  final bool exited;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final tokens = context.appTheme;
    final spacing = tokens.spacing;
    final highlighted = current && !exited;
    final foreground = highlighted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final background = highlighted
        ? Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: .08),
            theme.colorScheme.surface,
          )
        : theme.colorScheme.surface;
    final icon = switch (hop.kind) {
      ShellConnectionHopKind.localShell ||
      ShellConnectionHopKind.localClient => Icons.terminal_rounded,
      ShellConnectionHopKind.proxy => Icons.alt_route_rounded,
      _ => Icons.dns_outlined,
    };
    final label = switch (hop.kind) {
      ShellConnectionHopKind.localShell => l10n.shellChainLocalShell,
      ShellConnectionHopKind.localClient => l10n.shellChainLocalClient,
      ShellConnectionHopKind.proxy => l10n.shellChainProxy,
      _ => hop.address.isEmpty ? l10n.shellChainUnknownHost : hop.address,
    };
    final role = current
        ? (exited ? l10n.shellChainLastShell : l10n.shellChainCurrentShell)
        : switch (hop.kind) {
            ShellConnectionHopKind.jump => l10n.shellChainJump,
            ShellConnectionHopKind.proxy => l10n.shellChainProxyUnknown,
            _ => first ? l10n.shellChainOrigin : l10n.shellChainIntermediate,
          };
    return LayoutBuilder(
      builder: (context, rowConstraints) {
        return Semantics(
          container: true,
          child: DecoratedBox(
            key: ValueKey('shell-connection-hop-$index'),
            decoration: BoxDecoration(
              color: highlighted ? background : null,
              borderRadius: BorderRadius.circular(tokens.radius.md),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 40,
                        child: Column(
                          children: [
                            Expanded(
                              child: SizedBox(
                                width: 1.5,
                                child: ColoredBox(
                                  color: first
                                      ? Colors.transparent
                                      : tokens.border,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: spacing.xs,
                              ),
                              child: Icon(icon, size: 20, color: foreground),
                            ),
                            Expanded(
                              child: SizedBox(
                                width: 1.5,
                                child: ColoredBox(
                                  color: current
                                      ? Colors.transparent
                                      : tokens.border,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: spacing.sm,
                          bottom: spacing.sm,
                          right: spacing.md,
                        ),
                        child: Builder(
                          builder: (context) {
                            final portSuffix = hop.port != null && hop.port! > 0
                                ? ':${hop.port}'
                                : '';
                            final address = Text.rich(
                              TextSpan(
                                children: [
                                  if (portSuffix.isNotEmpty &&
                                      label.endsWith(portSuffix)) ...[
                                    TextSpan(
                                      text: label.substring(
                                        0,
                                        label.length - portSuffix.length,
                                      ),
                                    ),
                                    TextSpan(
                                      text: portSuffix,
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ] else
                                    TextSpan(text: label),
                                ],
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: current ? FontWeight.w500 : null,
                              ),
                            );
                            final status = Text(
                              role,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: foreground,
                                fontWeight: highlighted
                                    ? FontWeight.w600
                                    : null,
                              ),
                            );
                            final stacked =
                                rowConstraints.maxWidth < 420 ||
                                MediaQuery.textScalerOf(context).scale(14) > 20;
                            return stacked
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      address,
                                      SizedBox(height: spacing.xs),
                                      status,
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: address),
                                      SizedBox(width: spacing.md),
                                      status,
                                    ],
                                  );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.capability,
    required this.activation,
    this.registration,
  });

  final ShellIntegrationCapability capability;
  final ShellCapabilityActivation activation;
  final String? registration;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final spacing = context.appTheme.spacing;
    final (label, description) = switch (capability) {
      ShellIntegrationCapability.currentDirectory => (
        l10n.shellCapabilityDirectory,
        l10n.shellCapabilityDirectoryHelp,
      ),
      ShellIntegrationCapability.promptLifecycle => (
        l10n.shellCapabilityPrompt,
        l10n.shellCapabilityPromptHelp,
      ),
      ShellIntegrationCapability.commandStart => (
        l10n.shellCapabilityStart,
        l10n.shellCapabilityStartHelp,
      ),
      ShellIntegrationCapability.commandText => (
        l10n.shellCapabilityCommand,
        l10n.shellCapabilityCommandHelp,
      ),
      ShellIntegrationCapability.commandFinish => (
        l10n.shellCapabilityFinish,
        l10n.shellCapabilityFinishHelp,
      ),
      ShellIntegrationCapability.exitCode => (
        l10n.shellCapabilityExitCode,
        l10n.shellCapabilityExitCodeHelp,
      ),
      ShellIntegrationCapability.shellIdentity => (
        l10n.shellCapabilityShell,
        l10n.shellCapabilityShellHelp,
      ),
      ShellIntegrationCapability.hostname => (
        l10n.shellCapabilityHost,
        l10n.shellCapabilityHostHelp,
      ),
      ShellIntegrationCapability.username => (
        l10n.shellCapabilityUser,
        l10n.shellCapabilityUserHelp,
      ),
      ShellIntegrationCapability.integrationVersion => (
        l10n.shellCapabilityVersion,
        l10n.shellCapabilityVersionHelp,
      ),
      ShellIntegrationCapability.promptNavigation => (
        l10n.shellCapabilityNavigation,
        l10n.shellCapabilityNavigationHelp,
      ),
      ShellIntegrationCapability.commandOutputRanges => (
        l10n.shellCapabilityOutput,
        l10n.shellCapabilityOutputHelp,
      ),
      ShellIntegrationCapability.userVariables => (
        l10n.shellCapabilityVariables,
        l10n.shellCapabilityVariablesHelp,
      ),
    };
    final (status, icon, color) = switch (activation.status) {
      ShellCapabilityStatus.pending => (
        l10n.shellCapabilityPending,
        Icons.schedule_rounded,
        theme.colorScheme.onSurfaceVariant,
      ),
      ShellCapabilityStatus.active => (
        l10n.shellCapabilityActive,
        Icons.check_circle_outline_rounded,
        theme.colorScheme.primary,
      ),
      ShellCapabilityStatus.disabled => (
        l10n.shellCapabilityDisabled,
        Icons.pause_circle_outline_rounded,
        theme.colorScheme.onSurfaceVariant,
      ),
      ShellCapabilityStatus.unavailable => (
        l10n.shellCapabilityUnavailable,
        Icons.info_outline_rounded,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    final reason = switch (activation.reason) {
      ShellCapabilityReason.awaitingEvidence =>
        l10n.shellCapabilityAwaitingEvidence,
      ShellCapabilityReason.initializationChecked =>
        l10n.shellCapabilityInitializationChecked,
      ShellCapabilityReason.initializationFailed =>
        l10n.shellCapabilityInitializationFailed,
      ShellCapabilityReason.observed => l10n.shellCapabilityObserved,
      ShellCapabilityReason.disabledByProfile =>
        l10n.shellCapabilityDisabledReason,
      ShellCapabilityReason.unsupportedEmulation =>
        l10n.shellCapabilityEmulationReason,
      ShellCapabilityReason.sessionExited => l10n.shellCapabilityExitedReason,
    };
    return Semantics(
      container: true,
      child: Padding(
        key: ValueKey('shell-capability-${capability.id}'),
        padding: EdgeInsets.symmetric(vertical: spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            if (registration != null)
              Text(switch (registration) {
                'registered' => l10n.shellCapabilityRegistered,
                'unavailable' => l10n.shellCapabilityNotRegistered,
                _ => l10n.shellCapabilityUnchecked,
              }, style: theme.textTheme.bodySmall),
            SizedBox(height: spacing.xs),
            Row(
              children: [
                ExcludeSemantics(child: Icon(icon, color: color, size: 18)),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: Text(
                    status,
                    style: theme.textTheme.labelLarge?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xs),
            Text(description, style: theme.textTheme.bodyMedium),
            SizedBox(height: spacing.xs),
            Text(
              reason,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
