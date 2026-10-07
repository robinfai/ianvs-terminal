String aiErrorText(String code, bool zh) {
  final messages = <String, (String, String)>{
    'configuration_changed': (
      'The AI connection changed. Start a new task; this task is retained for reference.',
      'AI 连接已改变。请开始新任务，原任务保留供查看。',
    ),
    'acp_authentication': (
      'Sign in with Codex on this Mac, then reconnect.',
      '请先在本机登录 Codex，然后重新连接。',
    ),
    'acp_desktop_only': (
      'Local ACP agents require the desktop app.',
      '本地 ACP Agent 需要在桌面端运行。',
    ),
    'acp_discovery_platform': (
      'Automatic detection is available on macOS and Linux.',
      '自动检测目前支持 macOS 和 Linux。',
    ),
    'acp_discovery_found': (
      'Launch settings filled in. Test the connection, then save.',
      '已填入启动配置。请测试连接后保存。',
    ),
    'acp_discovery_edited': (
      'Your edits were kept. Auto-detect again to replace the launch settings.',
      '已保留你刚才的编辑。再次点击自动检测可重新填入启动配置。',
    ),
    'acp_node_missing': (
      'Codex ACP was found, but Node.js was not. Install Node.js or enter its executable path.',
      '已找到 Codex ACP，但未找到 Node.js。请安装 Node.js，或手动填写其可执行文件路径。',
    ),
    'acp_adapter_missing': (
      'Codex ACP was not found. With Node.js installed, run npm install -g @agentclientprotocol/codex-acp@2.1.1, then detect again. For a custom installation, enter its paths below.',
      '未找到 Codex ACP。安装 Node.js 后，运行 npm install -g @agentclientprotocol/codex-acp@2.1.1，再点击自动检测；自定义安装可在下方手动填写路径。',
    ),
    'acp_discovery_failed': (
      'Detection could not finish. Try again or enter the launch settings manually.',
      '未能完成检测。请重试，或手动填写启动配置。',
    ),
    'acp_capability': (
      'This adapter does not support the required Trail terminal integration.',
      '适配器不支持 Trail 所需的终端工具能力。',
    ),
    'acp_model': (
      'The agent could not confirm the requested model. No fallback was used.',
      'Agent 无法确认所选模型，没有自动替换模型。',
    ),
    'acp_request': (
      'The agent rejected the request. Check its connection and model.',
      'Agent 拒绝了请求，请检查连接和模型。',
    ),
    'acp_disconnected': (
      'Agent disconnected. Terminal commands were not replayed.',
      'Agent 连接中断，没有重发终端命令。',
    ),
    'acp_timeout': (
      'Agent connection timed out. No terminal action was retried.',
      'Agent 连接超时，没有重试终端动作。',
    ),
    'acp_busy': ('Wait for the current terminal operation.', '请等待当前终端操作完成。'),
    'target_changed': (
      'The target changed. Choose whether to continue on the current target.',
      '执行目标已改变，请明确选择是否在当前目标继续。',
    ),
    'context_limit': ('Attach at most eight output ranges.', '一次最多附加八段输出。'),
    'block_unavailable': ('This output is no longer available.', '这段输出已不可读取。'),
    'invalid_range': ('The requested output range is invalid.', '请求的输出范围无效。'),
    'configuration': (
      'Check the selected connection and model in AI settings.',
      '请在 AI 设置中检查所选连接及模型。',
    ),
    'storage': (
      'Could not access saved configuration. Your previous configuration is preserved.',
      '无法访问已保存的配置，原配置已保留。',
    ),
    'configuration_save': (
      'Could not save configuration. Your edits are kept here. Try again.',
      '无法保存配置。编辑内容已保留，请重试。',
    ),
    'configuration_remove': (
      'Could not remove configuration. Your saved configuration is unchanged.',
      '无法移除配置。已保存的配置未改变。',
    ),
    'authentication': (
      'API key was rejected. Check your AI settings.',
      'API Key 验证失败，请检查 AI 设置。',
    ),
    'rate_limit': (
      'The provider is rate limiting requests. Try again later.',
      '服务正在限流，请稍后重试。',
    ),
    'timeout': (
      'The AI request timed out. No terminal action was retried.',
      'AI 请求超时，没有重试终端动作。',
    ),
    'connection': (
      'Cannot connect to the endpoint. Check the URL and network.',
      '无法连接 Endpoint，请检查地址和网络。',
    ),
    'response_format': (
      'The endpoint returned an unsupported response.',
      'Endpoint 返回了不支持的响应格式。',
    ),
    'invalid_action': (
      'The proposed terminal action is invalid. No input was sent.',
      '模型返回的终端动作无效，没有发送输入。',
    ),
    'empty_response': ('The model returned an empty response.', '模型返回了空响应。'),
    'response_too_large': (
      'The model response exceeds the size limit.',
      '模型响应超过大小限制。',
    ),
    'prompt_too_large': (
      'Shorten your request to 16,000 characters.',
      '请将请求缩短到 16,000 字符以内。',
    ),
    'stale_context': (
      'The terminal changed. Continue the task to review a fresh proposal.',
      '终端状态已改变。点击“继续任务”，重新读取状态并确认新的动作。',
    ),
    'session_unavailable': (
      'This terminal session is no longer available.',
      '当前终端会话已不可用。',
    ),
    'screen_unavailable': (
      'The current terminal screen could not be read.',
      '无法读取当前终端屏幕。',
    ),
    'read_only': (
      'This terminal cannot accept input right now.',
      '当前终端暂时不能接受输入。',
    ),
    'shell_not_ready': (
      'The shell is not ready for a new command.',
      'Shell 尚未就绪，不能提交新命令。',
    ),
    'submission_rejected': (
      'The shell rejected this submission. Request a new proposal.',
      'Shell 拒绝了这次提交，请重新提问。',
    ),
    'submission_unknown': (
      'Submission status is unknown. Check the original receipt; if it remains unknown, inspect the terminal manually. The command will not be resent.',
      '命令提交状态未知。请检查原回执；若仍未知，请返回终端人工检查。不会重发该命令。',
    ),
    'input_rejected': ('The terminal did not accept the input.', '终端未接受这次输入。'),
    'no_failed_command': (
      'There is no completed failed command in this session.',
      '当前会话没有可纠正的已失败命令。',
    ),
    'step_limit': (
      'This turn reached its action limit. Continue the task from the current terminal state.',
      '本轮已达到交互上限。点击“继续任务”，从当前终端状态接着处理。',
    ),
    'conversation_limit': (
      'This conversation is full. Start a new conversation with your goal and constraints to continue.',
      '当前对话已满。请新建对话，写明目标和约束后继续。',
    ),
    'execution': (
      'The action could not be verified. Inspect the terminal before continuing.',
      '无法验证动作结果，请检查终端后继续。',
    ),
  };
  final message = messages[code];
  return message == null
      ? (zh ? 'AI 服务请求失败（$code）。' : 'AI request failed ($code).')
      : (zh ? message.$2 : message.$1);
}
