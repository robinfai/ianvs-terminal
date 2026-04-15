# T-XXX Task Title

在开始实现前，复制这份模板新建一个任务文档，并把 `XXX` 替换成稳定编号。

建议文件名格式：

- `T-001-terminal-scrollback.md`
- `T-002-profile-editor.md`

## Goal

用一句话写清楚本次任务唯一要解决的问题。

## Scope

- 写本次允许修改的能力和模块
- 保持范围小，尽量单一目标

## Non-goals

- 写清楚这次不做什么
- 把容易顺手扩展的点全部排除掉

## Files In Scope

- `app/lib/...`
- `app/test/...`
- `native/core/...`

## Functional Acceptance

- 写用户可观察到的行为结果
- 每一条都要能被测试命令或人工步骤验证

## Verification Commands

参考 [../TESTING.md](/Users/robinfai/personal/flutterm/docs/TESTING.md)，只选这次真正需要的命令。

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test
```

## Manual QA

写这次要执行的人工步骤。GUI 和 terminal 改动通常不能省略这一节。

## Done When

- 目标完成
- 验证通过
- 没有超出范围
- 文档同步更新

## Risks / Follow-ups

- 记录本次没有解决但值得继续追踪的问题
- 如果需要下一任务，直接写出来
