import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../../features/ai/ai_connection_test.dart';
import '../../features/ai/ai_connection_test_panel.dart';
import '../../features/ai/ai_models.dart';
import '../app_ui.dart';

@Preview(
  name: 'Connection test · Running',
  group: 'AI settings',
  size: Size(680, 540),
)
Widget connectionTestRunningPreview() =>
    const AiConnectionTestPreview(status: AiConnectionTestStatus.running);
@Preview(
  name: 'Connection test · Success',
  group: 'AI settings',
  size: Size(680, 540),
)
Widget connectionTestSuccessPreview() =>
    const AiConnectionTestPreview(status: AiConnectionTestStatus.success);
@Preview(
  name: 'Connection test · Timeout',
  group: 'AI settings',
  size: Size(680, 540),
)
Widget connectionTestTimeoutPreview() =>
    const AiConnectionTestPreview(status: AiConnectionTestStatus.timedOut);
@Preview(
  name: 'Connection test · Dark',
  group: 'AI settings',
  size: Size(680, 540),
)
Widget connectionTestDarkPreview() => const AiConnectionTestPreview(
  status: AiConnectionTestStatus.failed,
  brightness: Brightness.dark,
);

/// Uses the production panel and deterministic sample results, without native ACP.
class AiConnectionTestPreview extends StatefulWidget {
  const AiConnectionTestPreview({
    required this.status,
    this.brightness = Brightness.light,
    this.fontFamily,
    super.key,
  });
  final AiConnectionTestStatus status;
  final Brightness brightness;
  final String? fontFamily;
  @override
  State<AiConnectionTestPreview> createState() =>
      _AiConnectionTestPreviewState();
}

class _AiConnectionTestPreviewState extends State<AiConnectionTestPreview> {
  late final AiConnectionTestController test;
  @override
  void initState() {
    super.initState();
    test =
        AiConnectionTestController(
            runner: (_, _, _) => Completer<void>().future,
          )
          ..status = widget.status
          ..backend = AiBackendKind.acp
          ..model = 'gpt-6.1-sol'
          ..stages = const [
            AiConnectionStage.launch,
            AiConnectionStage.handshake,
            AiConnectionStage.session,
            AiConnectionStage.model,
            AiConnectionStage.reply,
          ]
          ..stage = AiConnectionStage.reply
          ..elapsed = Duration(
            seconds: widget.status == AiConnectionTestStatus.timedOut ? 60 : 12,
          );
    for (final stage in test.stages.take(4)) {
      test.completed[stage] = const Duration(milliseconds: 800);
    }
    if (widget.status == AiConnectionTestStatus.success) {
      test.completed[AiConnectionStage.reply] = const Duration(seconds: 8);
    }
    if (widget.status == AiConnectionTestStatus.failed) {
      test.error = 'acp_authentication';
    }
  }

  @override
  void dispose() {
    test.dispose();
    super.dispose();
  }

  ThemeData _theme() {
    final base = buildIanvsTerminalTheme(
      widget.brightness,
      platform: TargetPlatform.macOS,
    );
    if (widget.fontFamily == null) return base;
    final label = WidgetStatePropertyAll(
      base.textTheme.labelLarge?.copyWith(fontFamily: widget.fontFamily),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: widget.fontFamily),
      textButtonTheme: TextButtonThemeData(
        style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          textStyle: label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          textStyle: label,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: _theme(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: AiConnectionTestPanel(
          controller: test,
          onTest: () => test.start(
            const AiConfiguration.acp(
              agentCommand: '/node',
              agentArguments: [],
              model: 'gpt-6.1-sol',
            ),
          ),
          saved: false,
        ),
      ),
    ),
  );
}
