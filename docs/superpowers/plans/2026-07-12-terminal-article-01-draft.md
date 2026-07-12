# 第 1 篇 Terminal 文章成稿 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 根据已批准的设计稿，完成《五彩斑斓的黑》第 1 篇 4,000—5,500 字中文成稿，解释开发侧与运维侧两类 Shell 需求如何共同推动 Terminal 产品持续迭代。

**Architecture:** 正文只保留一条因果链：两类 Shell 需求长期存在，因此承载人工交互的 Terminal 仍需演进。历史、专业角色、Kubernetes 与 Warp 都是这条主线的证据；AI 是增强层，不是基础 Shell 路径的替代品。

**Tech Stack:** Markdown、ASCII 图、Bash 示例、Flutter 聚焦测试、POSIX/Unix/SSH/Kubernetes/Warp 等一手资料。

---

## Scope Check

本计划只生成第 1 篇完整正文，不修改应用代码，也不提前讲解 TTY/PTY、ANSI 状态机、Screen Buffer、Renderer 或 Kubernetes 远程执行协议。这些内容属于系列后续文章。

设计依据：`docs/superpowers/specs/2026-07-12-terminal-article-01-design.md`。

## File Structure

- Create: `docs/articles/terminal-series/01-why-terminal-still-exists.md`
  - 保存可独立发布的第 1 篇中文正文。
  - 在同一文件中包含标题、核心问题、历史背景、技术演进时间线、ASCII 图、代码示例、源码参考和延伸阅读。
- Read only: `docs/superpowers/specs/2026-07-12-terminal-article-01-design.md`
  - 提供主论点、章节边界、事实来源和禁用表述。
- Read only: `docs/ARCHITECTURE.md`
  - 仅用于本地 Ianvs Terminal 源码参考，不把产品实现写成文章主角。

## Global Writing Contract

- 面向有经验的工程师，使用完整工程判断，不写入门词典。
- 第一次出现 Terminal、Shell、CLI 时只做最小区分；严格术语定义后移到第 3 篇。
- “开发侧”和“运维侧”是需求原型，不是封闭职业分类。
- 自动化程序通常依赖 CLI/Shell；只有交互会话、现场观察或人工接管需要 Terminal。
- Kubernetes 只证明声明式系统仍保留现场入口，不解释 `-i`、`-t`、TTY、WebSocket/SPDY 或 Runtime 调用链。
- Warp 只证明 AI 增强与基础终端路径共存，不声称完整兼容或无损自动回退。
- 不使用“GUI 失败”“Terminal 比任何时候都更重要”“所有开发者都必须使用 Terminal”等绝对表述。
- 正文中的外部事实就近链接一手资料；文末再给源码参考和延伸阅读。

---

### Task 1: Opening, Core Question, And Article Frame

**Files:**
- Create: `docs/articles/terminal-series/01-why-terminal-still-exists.md`

- [ ] **Step 1: Create the article directory and opening section**

创建文章文件，并使用以下标题和开场锚点：

```markdown
# 为什么今天还有 Terminal？——开发者的工作台，运维者的消防楼梯

对开发者，Terminal 是每天开工的工作台；对运维者，它又是系统出问题时不能锁死的消防楼梯。
```

随后用 300—450 字完成开场，必须包含：

1. GUI、IDE、Web 控制台和声明式 API 已经成功替代大量常见操作。
2. 问题不是“GUI 为什么失败”，而是两类 Shell 需求为什么没有消失。
3. 一句话答案：开发需要开放、可组合的工作台；运维需要低依赖、可直接接管的控制与恢复通道。
4. Terminal 是两类 Shell 需求需要人工交互时共同使用的界面。

- [ ] **Step 2: Write the core-question section**

添加：

```markdown
## 核心问题

## 去 Console 化其实成功了
```

在“核心问题”中用表面问题、深层问题和一句话答案三段推进；在“去 Console 化其实成功了”中用 500—700 字说明 GUI、IDE 和 Web 控制台的真实价值，并以这句话收束：

> 去 Console 化成功地替换了普通用户的许多正常路径，却没有消除开发侧的开放工作流，也没有理由拆掉运维侧的异常路径。

- [ ] **Step 3: Verify the opening does not revive the rejected thesis**

Run:

```bash
rg -n "GUI 失败|比任何时候都更重要|数字系统|Terminal 只在应急时" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: no matches, exit code 1.

Run:

```bash
rg -n "工作台|消防楼梯|两类 Shell 需求" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: all three concepts appear in the opening and core-question section.

- [ ] **Step 4: Commit the opening slice**

```bash
git add docs/articles/terminal-series/01-why-terminal-still-exists.md
git commit -m "docs: draft terminal article opening"
```

---

### Task 2: Historical Background And Evolution Timeline

**Files:**
- Modify: `docs/articles/terminal-series/01-why-terminal-still-exists.md`

- [ ] **Step 1: Write the historical-background section**

添加 `## 历史背景`，用 800—1,000 字完成四段历史：

1. 分时系统中的物理 Terminal 是计算入口。
2. Unix、标准流、Shell 和管道把入口变成可组合的软件开发工作台。
3. GUI 成功取代普通用户的高频路径，Terminal 从大众正门退出。
4. 软件终端在 IDE 与项目工具链中成为开发工作台，在 SSH、云和容器平台中成为运维控制与恢复通道。

历史事实就近使用以下一手资料：

- Dennis Ritchie: `https://www.nokia.com/bell-labs/about/dennis-m-ritchie/hist.html`
- POSIX Shell Command Language: `https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html`
- VT100 User Guide: `https://bitsavers.org/pdf/dec/terminal/vt100/EK-VT100-UG-001_VT100_User_Guide_Aug78.pdf`
- RFC 4254: `https://datatracker.ietf.org/doc/html/rfc4254`

- [ ] **Step 2: Add the exact evolution timeline**

添加 `## 技术演进时间线`，表格必须覆盖以下七个节点和结论：

| 时期 | 变化 | 文章结论 |
| --- | --- | --- |
| 1960s | 分时计算与字符终端 | Terminal 最初是主要人机入口 |
| 1969—1970s | Unix、Shell、标准流与管道 | 开发侧形成可组合的日常工作台 |
| 1978 | VT100 固化屏幕控制契约 | 硬件消失后兼容契约仍被软件继承 |
| 1980s—1990s | 桌面 GUI 成为大众入口 | 去 Console 化成功，但专业 Shell 需求保留 |
| 1990s—2000s | 网络服务与 SSH | 运维形成低依赖的远程控制与恢复通道 |
| 2010s | IDE、云、容器与 DevOps | 两类需求在现代 Terminal 产品中汇合 |
| 2020s | Coding Agent 与 AI Terminal | AI 增强两类工作，基础路径仍须独立工作 |

- [ ] **Step 3: Verify dates, source links, and scope**

Run:

```bash
rg -n "1960s|1969—1970s|1978|1980s—1990s|1990s—2000s|2010s|2020s" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: all seven timeline nodes appear.

Run:

```bash
rg -n "nokia.com/bell-labs|pubs.opengroup.org|bitsavers.org|rfc4254" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: all four primary-source links appear.

Run:

```bash
rg -n "状态机|Screen Buffer|Renderer|WebSocket|SPDY|Kubelet|Runtime 调用链" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: no matches, exit code 1.

- [ ] **Step 4: Commit the history slice**

```bash
git add docs/articles/terminal-series/01-why-terminal-still-exists.md
git commit -m "docs: add terminal article history"
```

---

### Task 3: Dual Shell Needs, Professional Roles, Diagrams, And Examples

**Files:**
- Modify: `docs/articles/terminal-series/01-why-terminal-still-exists.md`

- [ ] **Step 1: Write the developer-side Shell section**

添加 `## 开发侧 Shell：开放、可组合的日常工作台`，用 600—800 字回答：

- 编译器、测试框架、版本控制、包管理器和调试器为何持续以 CLI 暴露能力。
- 开放任务的参数与组合为何难以全部固化为按钮。
- IDE 内置 Terminal 为什么是对图形工作台的补充，不是对 GUI 的否定。
- 结论为什么是“适合开放工作”，而不是“命令行天然更高效”。

插入并解释这个开发侧示例：

```bash
rg "TerminalRuntimeController" packages
flutter test packages/ianvs_terminal/test/terminal_runtime_controller_test.dart
git diff --stat
```

- [ ] **Step 2: Write the operations-side Shell section**

添加 `## 运维侧 Shell：直接控制与应急恢复通道`，用 600—800 字回答：

- 远程主机、容器和受限环境为什么不总有完整 GUI。
- 监控、控制台或自动化为什么无法预先解释所有故障现场。
- SSH、日志、现场命令与恢复工具为什么长期存在。
- Kubernetes 的声明式控制面为什么仍保留 `logs`、`exec` 和 `debug`。

插入并解释这个运维侧示例：

```bash
kubectl apply -f deployment.yaml
kubectl rollout status deployment/app
kubectl exec deployment/app -- cat /etc/resolv.conf
```

解释只对比正常控制面与现场入口，不讨论 TTY 参数或传输协议。

- [ ] **Step 3: Map other roles back to the two demand archetypes**

添加 `## 岗位很多，依赖机制只有两类`，用一张紧凑表格覆盖：

- 数据、ML、科研和 HPC：以开发工作台为主，同时需要远程计算入口。
- DBA、网络、安全响应、IT 支持和现场服务：以直接控制、调查和恢复为主。
- 构建发布、包维护和技术管线：以可组合、可复现的开发流程为主。
- 嵌入式、内核、驱动和机器人开发：交叉编译与测试属于工作台；串口、远程目标和启动恢复属于控制通道。

表格之后必须明确：CI/CD、批处理和 Agent 通常依赖 CLI/Shell，不必经过 Terminal；交互程序、会话状态、现场观察和人工接管才需要 Terminal。

- [ ] **Step 4: Add the main causal diagram**

插入以下主图：

```text
           开发侧 Shell                         运维侧 Shell
   编译 / 测试 / Git / 调试              SSH / 日志 / 检查 / 恢复
          日常工作台                         直接控制与消防楼梯
                 \                           /
                  \                         /
                   └─────── Terminal ──────┘
                              │
             ┌────────────────┴────────────────┐
             │                                 │
       开发生产力迭代                    运维能力迭代
  编辑 / 搜索 / 补全 / Block       兼容 / 远程 / 性能 / 可靠降级
             │                                 │
             └────────────────┬────────────────┘
                              ▼
                   Agent / AI 交互增强
```

图下注明：自动化程序可以直接使用 API 或 CLI；图中只讨论人参与时 Terminal 如何被两类需求塑造。

- [ ] **Step 5: Run the executable developer example**

Run:

```bash
rg "TerminalRuntimeController" packages
```

Expected: matches in the runtime implementation and focused tests.

Run:

```bash
flutter test packages/ianvs_terminal/test/terminal_runtime_controller_test.dart
```

Expected: `All tests passed!` with no failing tests.

Run:

```bash
git diff --stat
```

Expected: the article file appears in the diff before commit.

- [ ] **Step 6: Verify the Terminal-versus-CLI boundary**

Run:

```bash
rg -n "不必经过 Terminal|交互程序|人工接管|需求原型" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: all four boundary concepts appear.

- [ ] **Step 7: Commit the dual-needs slice**

```bash
git add docs/articles/terminal-series/01-why-terminal-still-exists.md
git commit -m "docs: explain terminal dual demand"
```

---

### Task 4: Warp, AI Enhancement, Fallback, And Closing

**Files:**
- Modify: `docs/articles/terminal-series/01-why-terminal-still-exists.md`

- [ ] **Step 1: Write the Warp case study**

添加 `## Warp 为什么仍然保留 Terminal 基础交互`，用 700—900 字建立以下因果关系：

1. Warp 先围绕输入、Block、Shell Hook 和上下文改善开发工作台。
2. Agent 仍需通过 CLI 接入开放且变化的工具生态。
3. REPL、调试器、全屏程序和长时间运行进程要求保留传统交互能力。
4. 人与 Agent 需要共享执行现场，命令、输出、审批和接管必须可见。
5. AI 不可用、理解失败或增强能力不兼容时，基础 Terminal 与 Shell 仍应工作。

就近链接：

- `https://www.warp.dev/blog/how-warp-works`
- `https://www.warp.dev/blog/agent-mode`
- `https://docs.warp.dev/agent-platform/capabilities/full-terminal-use`
- `https://www.warp.dev/blog/block-model-behind-warps-agentic-development-environment`
- `https://docs.warp.dev/terminal/comparisons/terminal-features`

只把 Shell Hook、Block、AltScreen 和权限系统各解释一到两句。

- [ ] **Step 2: Add the AI fallback diagram and engineering judgment**

添加 `## AI 是增强层，不是基础路径的替代品`，并插入：

```text
┌──────────────────────────────────────┐
│ AI Agent：自然语言、规划、自动执行    │
├──────────────────────────────────────┤
│ 结构化体验：Block、上下文、审批、解释 │
├──────────────────────────────────────┤
│ 传统 Terminal：输入、显示、全屏程序   │
├──────────────────────────────────────┤
│ Shell / CLI：命令、标准流、退出状态    │
├──────────────────────────────────────┤
│ 本地系统 / SSH / Container            │
└──────────────────────────────────────┘
```

正文必须说明这是工程分层，不承诺任何兼容问题都能自动、无损回退。准确表述是：基础路径被保留，部分增强能力可以绕过或降级。

- [ ] **Step 3: Write the closing**

用 250—350 字收束，不预测 Terminal 重新成为大众主界面，也不把 AI Terminal 写成唯一未来。最后一段以这组判断为中心：

> Terminal 持续迭代，不是因为所有人都回到了命令行，而是因为软件开发仍需要一张开放、可组合的 Shell 工作台，系统运维仍需要一条低依赖、可直接接管的 Shell 通道。AI Terminal 让工作台更顺手，也让消防楼梯更亮、更容易走，但它不能拆掉下面那条传统路径。

- [ ] **Step 4: Verify Warp claims stay inside the evidence boundary**

Run:

```bash
rg -n "完整兼容|所有 Shell|全部终端|自动无损回退|最终界面一定是 TUI|字符流天然" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: no matches, exit code 1.

Run:

```bash
rg -n "how-warp-works|agent-mode|full-terminal-use|block-model|terminal-features" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: all five official Warp references appear.

- [ ] **Step 5: Commit the Warp and closing slice**

```bash
git add docs/articles/terminal-series/01-why-terminal-still-exists.md
git commit -m "docs: complete terminal AI argument"
```

---

### Task 5: Sources, Further Reading, Editorial Review, And Final Verification

**Files:**
- Modify: `docs/articles/terminal-series/01-why-terminal-still-exists.md`

- [ ] **Step 1: Add source-code references**

添加 `## 源码参考`，按三组整理链接并各写一句阅读目的：

1. 终端基础：xterm.js、VS Code `terminalInstance.ts`、Microsoft ConPTY。
2. 现场入口：Kubernetes `kubectl exec` 文档与 `exec.go`。
3. Warp：`blocks.rs`、`zsh_body.sh`、`dcs_hooks.rs`、`alt_screen.rs`。

链接从设计稿的“源码参考”逐项复制，保留 Warp 固定 commit 路径，避免链接到会漂移的源码行号。

- [ ] **Step 2: Add further reading**

添加 `## 延伸阅读`，正文推荐列表控制在七项：Unix 历史、POSIX Shell、`pty(7)`、RFC 4254、Kubernetes exec、How Warp Works、Warp Block Model。

再添加“不占正文篇幅”的深挖列表：XTerm Control Sequences、Windows Console、Warp Full Terminal Use、Slurm `sbatch`、GDB Remote Debugging、PostgreSQL `psql`、Terminal Lucidity。

- [ ] **Step 3: Check mandatory article components**

Run:

```bash
rg -n "^# 为什么今天还有 Terminal|^## 核心问题|^## 历史背景|^## 技术演进时间线|^## 开发侧 Shell|^## 运维侧 Shell|^## 岗位很多|^## Warp|^## AI 是增强层|^## 源码参考|^## 延伸阅读" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: every required article component appears exactly once.

- [ ] **Step 4: Measure the body length**

Run:

```bash
perl -CSD -0777 -ne '($body) = split(/^## 源码参考/m, $_, 2); $body =~ s/```.*?```//sg; $count = () = $body =~ /\p{Han}/g; print "$count\n"' docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: 3,600—5,000 Han characters before source lists and excluding fenced code, corresponding to roughly 4,000—5,500 Chinese characters once English technical terms are included.

- [ ] **Step 5: Run the complete editorial constraint scan**

Run:

```bash
rg -n "TB[D]|TO[D]O|待补|待定|数字系统|GUI 失败|比任何时候都更重要|Terminal 只在应急时|所有开发者都必须|所有 CLI 都需要 Terminal|Kubernetes 依赖 Terminal|自动无损回退|所有 Shell|全部终端协议" docs/articles/terminal-series/01-why-terminal-still-exists.md
```

Expected: no matches, exit code 1.

Run:

```bash
git diff --check
```

Expected: exit code 0 with no whitespace errors.

- [ ] **Step 6: Re-read against the approved design**

逐项确认：

- 开发工作台与运维控制通道权重均衡。
- 其他专业角色只作为派生或交叉证据。
- Kubernetes 没有 TTY 参数和协议展开。
- Warp 没有被描述为完全兼容或必然无损回退。
- AI 同时增强开发与运维体验，但不成为基础 Shell 前提。
- 两张 ASCII 图和两组代码示例都在正文中得到解释。
- 历史事实、现代产品判断和源码路径都有可追溯链接。

- [ ] **Step 7: Commit the publishable article**

```bash
git add docs/articles/terminal-series/01-why-terminal-still-exists.md
git commit -m "docs: finalize first terminal series article"
```

- [ ] **Step 8: Verify the final repository state**

Run:

```bash
git status --short
```

Expected: no output.

Run:

```bash
git log -5 --oneline
```

Expected: the five article-slice commits appear in reverse chronological order.
