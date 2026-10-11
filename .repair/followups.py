from pathlib import Path

def change(path,old,new):
    p=Path(path);s=p.read_text()
    if s.count(old)!=1:raise SystemExit(f'followup anchor mismatch {path}: {old[:70]}')
    p.write_text(s.replace(old,new))

change('example/lib/features/ai/ai_api_client.dart',"import 'ai_models.dart';\nimport 'ai_chat_stream.dart';","import 'ai_chat_stream.dart';\nimport 'ai_models.dart';")
change('example/lib/features/ai/terminal_ai_workspace.dart',"import 'ai_response_activity.dart';\nimport 'ai_models.dart';","import 'ai_models.dart';\nimport 'ai_response_activity.dart';")
change('example/test/ai/ai_chat_stream_test.dart','final length = request.contentLength;','final length = request.headers.contentLength;')
change('example/lib/features/ai/terminal_ai_workspace.dart', '''    } else if (changed && _follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _latest());
    }''','''    } else if (changed && _follow) {
      final scheduledTaskId = c.taskId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && _follow && c.taskId == scheduledTaskId) {
          _latest();
        }
      });
    }''')
change('example/lib/features/ai/terminal_ai_workspace.dart',
       '      if (c.transcript.isEmpty && c.attachments.isEmpty) {',
       '      if (c.transcript.isEmpty && c.attachments.isEmpty && !c.busy) {')
