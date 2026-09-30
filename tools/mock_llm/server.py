#!/usr/bin/env python3
"""Local, deterministic OpenAI-compatible terminal agent for development.

This is a mock model, not a replacement for an LLM. It reads the same context
and produces the same tool-call protocol as an external inference service.
No command is executed by this server; all actions go through Trail approval.
"""

import argparse
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock


def tool(name, arguments, serial):
    return {"role": "assistant", "content": None, "tool_calls": [{
        "id": f"mock-{serial}", "type": "function",
        "function": {"name": name, "arguments": json.dumps(arguments, ensure_ascii=False)},
    }]}


def decode_content(message):
    try:
        return json.loads(message.get("content") or "{}")
    except (ValueError, TypeError):
        return {}


def reply_for(messages, serial):
    user_index = next((i for i in range(len(messages) - 1, -1, -1) if messages[i].get("role") == "user"), -1)
    user = messages[user_index] if user_index >= 0 else {}
    payload = decode_content(user)
    request = payload.get("request", user.get("content", ""))
    context = payload.get("terminal_context", {})
    lower = request.lower()
    if messages[-1].get("role") == "tool":
        result = decode_content(messages[-1])
        observed = result.get("terminal_context", result)
        if result.get("error") or result.get("cancelled"):
            return {"role": "assistant", "content": "Mock：动作未确认完成，请检查终端后再继续。"}
        screen = observed.get("screen", "")
        if re.search(r"\b(?:vi|vim)\b", context.get("running_command") or ""):
            calls = [m for m in messages[user_index + 1:] if m.get("tool_calls")]
            if len(calls) == 1 and ("保存" in request or "save" in lower) and "退出" not in request and "quit" not in lower:
                return tool("send_keys", {"reason": "保存刚才插入的内容。", "keys": [
                    {"key": "ESC"}, {"text": ":w"}, {"key": "ENTER"},
                ]}, serial)
        last = observed.get("last_command") or {}
        status = (f"退出码：{last['exit_code']}。" if last.get("exit_code") is not None
                  else "应用仍在运行。")
        useful_lines = [line.rstrip() for line in screen.splitlines()
                        if any(character.isalnum() for character in line)]
        excerpt = '\n'.join(useful_lines[-12:])[-1200:]
        return {"role": "assistant", "content": f"Mock 已收到真实终端反馈。{status}\n{excerpt}"}
    if "connection check" in lower:
        return {"role": "assistant", "content": "Trail mock connection OK"}
    selected = payload.get("selected_block") or context.get("last_command") or {}
    if any(word in lower for word in ["纠正", "修正", "correct", "fix "]):
        command = selected.get("command", "")
        corrected = re.sub(r"^gti\b", "git", command)
        corrected = re.sub(r"^sl\b", "ls", corrected)
        corrected = re.sub(r"\s+--(?:bad|invalid|not-a-real-option)\S*", "", corrected)
        if corrected and corrected != command:
            return tool("run_command", {"command": corrected,
                "reason": f"根据退出码 {selected.get('exit_code')} 和错误输出修正命令：{command}"}, serial)
        return {"role": "assistant", "content": "Mock 没有这类纠错规则。真实模型会收到命令、输出和退出码；请配置实际 LLM 继续分析。"}
    running = context.get("running_command") or ""
    if re.search(r"\b(?:vi|vim)\b", running) or "vim" in lower or re.search(r"\bvi\b", lower):
        if any(word in lower for word in ["退出", "quit", "exit"]):
            keys = [{"key": "ESC"}, {"text": ":wq" if "保存" in request or "save" in lower else ":q!"}, {"key": "ENTER"}]
        else:
            quoted = re.search(r'["“「](.*?)["”」]', request, re.DOTALL)
            if not quoted:
                return {"role": "assistant", "content": "请用引号写出要插入的文本，例如：在 vim 第一行插入 \"Hello Trail\" 并保存。"}
            keys = [{"key": "ESC"}, {"text": "ggO"}, {"text": quoted.group(1)}, {"key": "ESC"}]
        return tool("send_keys", {"reason": "在当前 vi/vim 会话中发送以下按键；先按 Esc 确认普通模式。", "keys": keys}, serial)
    if "k9s" in running or "k9s" in lower:
        resource = "namespaces" if "namespace" in lower or "命名空间" in request else "pods"
        return tool("send_keys", {"reason": f"在当前 k9s 中打开 {resource} 列表。", "keys": [
            {"key": "ESC"}, {"text": f":{resource}"}, {"key": "ENTER"},
        ]}, serial)
    if any(word in lower for word in ["列出", "查看文件", "list", "show me", "显示文件"]):
        return tool("run_command", {"reason": "列出当前目录的文件，包括隐藏文件。", "command": "ls -la"}, serial)
    return tool("read_screen", {"reason": "先读取当前终端屏幕，再解释应用状态。"}, serial)


class MockServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, api_key="trail-local-mock", audit=None):
        super().__init__(address, Handler)
        self.api_key = api_key
        self.audit = audit
        self.serial = 0
        self.lock = Lock()


class Handler(BaseHTTPRequestHandler):
    server: MockServer

    def log_message(self, *args):
        pass

    def respond(self, status, data):
        raw = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        try:
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def authorized(self):
        if self.headers.get("Authorization") != f"Bearer {self.server.api_key}":
            self.respond(401, {"error": {"message": "Invalid mock API key"}})
            return False
        return True

    def do_GET(self):
        if self.path == "/health":
            return self.respond(200, {"status": "ok", "mock": True})
        if not self.authorized():
            return
        if self.path == "/v1/models":
            return self.respond(200, {"object": "list", "data": [{"id": "trail-mock", "object": "model", "owned_by": "local"}]})
        self.respond(404, {"error": {"message": "Not found"}})

    def do_POST(self):
        if not self.authorized():
            return
        if self.path != "/v1/chat/completions":
            return self.respond(404, {"error": {"message": "Not found"}})
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length <= 0 or length > 1024 * 1024:
                return self.respond(413, {"error": {"message": "Request too large"}})
            payload = json.loads(self.rfile.read(length))
            messages = payload["messages"]
            if payload.get("model") != "trail-mock" or not isinstance(messages, list) or not messages:
                return self.respond(400, {"error": {"message": "Use model trail-mock and nonempty messages"}})
            with self.server.lock:
                self.server.serial += 1
                serial = self.server.serial
                if self.server.audit:
                    # Do not persist API keys, prompts, screen text or file contents.
                    record = {"request": serial, "model": payload["model"],
                        "roles": [m.get("role") for m in messages],
                        "tool_results": sum(m.get("role") == "tool" for m in messages)}
                    with Path(self.server.audit).open("a") as output:
                        output.write(json.dumps(record) + "\n")
            message = reply_for(messages, serial)
            return self.respond(200, {"id": f"chatcmpl-mock-{serial}", "object": "chat.completion", "model": "trail-mock",
                "choices": [{"index": 0, "message": message, "finish_reason": "tool_calls" if message.get("tool_calls") else "stop"}],
                "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}})
        except (ValueError, KeyError, TypeError, AttributeError):
            return self.respond(400, {"error": {"message": "Invalid request"}})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--audit", help="Optional metadata-only request log")
    args = parser.parse_args()
    server = MockServer((args.host, args.port), audit=args.audit)
    print(f"Trail mock ready: http://{args.host}:{server.server_port}/v1 · model trail-mock", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
