"""Deterministic Block UI acceptance fixture, not a model benchmark.

The server only proposes commands. Trail executes them after UI approval.
"""

import argparse

import server as mock


original_reply = mock.reply_for


def reply(messages, serial):
    requests = [
        mock.decode_content(message).get("request", "")
        for message in messages
        if message.get("role") == "user"
    ]
    if requests and requests[-1] == "历史阅读验收":
        return {
            "role": "assistant",
            "content": "\n".join(f"历史阅读测试行 {i}" for i in range(1, 81)),
        }
    if not any("流程验收" in request for request in requests):
        return original_reply(messages, serial)

    result = mock.decode_content(messages[-1])
    context = result.get("terminal_context", result)
    last = context.get("last_command") or {}
    calls = [message for message in messages if message.get("tool_calls")]
    if not calls:
        seconds = 30 if any("暂停" in request for request in requests) else 12
        return mock.tool(
            "run_command",
            {
                "command": (
                    f"printf 'FLOW_START\\n'; sleep {seconds}; "
                    "printf 'FLOW_DONE\\n'"
                ),
                "reason": "本地流程验收：打印开始，等待指定秒数，再打印完成；不写入文件。",
            },
            serial,
        )
    if last.get("exit_code") is not None and "FLOW_DONE" in last.get("output", ""):
        return {
            "role": "assistant",
            "content": (
                f"本地固定测试已观察到 FLOW_DONE，退出码 {last['exit_code']}。"
                "命令只提交一次。"
            ),
        }
    return mock.tool(
        "read_screen",
        {"reason": "等候已经提交的命令完成，不再次发送命令。", "wait_ms": 10000},
        serial,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--audit", help="Optional metadata-only JSONL request log")
    args = parser.parse_args()
    mock.reply_for = reply
    server = mock.MockServer(("127.0.0.1", args.port), audit=args.audit)
    print(f"Block flow fixture on http://127.0.0.1:{args.port}/v1", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
