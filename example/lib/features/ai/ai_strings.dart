String aiErrorText(String code, bool zh) {
  final messages = <String, (String, String)>{
    'configuration': (
      'Configure an endpoint, API key and model first.',
      '请先配置 Endpoint、API Key 和模型。',
    ),
    'storage': (
      'Could not access secure storage. Your previous configuration is preserved.',
      '无法访问安全存储，原配置已保留。',
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
      'The terminal changed. Send your request again to review a fresh proposal.',
      '终端状态已改变。请重新提问，获取基于当前状态的动作。',
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
      'Submission status is unknown. Inspect the terminal before trying again.',
      '命令提交状态未知，请先检查终端，再决定是否重试。',
    ),
    'input_rejected': ('The terminal did not accept the input.', '终端未接受这次输入。'),
    'no_failed_command': (
      'There is no completed failed command in this session.',
      '当前会话没有可纠正的已失败命令。',
    ),
    'step_limit': (
      'This turn reached its action limit. Send a follow-up to continue.',
      '本轮已达到动作上限，可发送后续请求继续。',
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
