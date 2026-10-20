# 证据校验工具

需要 Python 3.10+；全部使用标准库，不联网、不安装依赖、不执行 manifest 中的任何命令。

```sh
python3 scripts/validate_evidence.py templates/manifest.template.json
python3 scripts/validate_evidence.py evidence/manifest.json --gate D1
python3 scripts/validate_evidence.py evidence/manifest.json --gate final
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

默认按脚本上级目录读取 plan.json / shotlist.json；`--root` 仅用于独立测试。命令行 manifest 参数可为相对或绝对路径，但证据内部路径必须相对 PRD 根且位于 `evidence/`。

退出码：0 为元数据/文件合同满足；1 为合同未满足；2 为JSON、参数或输入错误。没有 `--gate` 只验证结构，模板中的 not_run 不会变成通过。阶段gate检查该阶段全部case为passed；final严格检查所有case与最终C一致。

## 录入规则

从 templates/manifest.template.json 复制开始。填 environments 后添加 artifacts，case 通过时填完整步骤、实际结果、源文件、assertions、artifact_ids与结果文档；before/after分开。每张after原图映射shotlist中的shot_ids，每条case正文嵌图。一个文件只建立一条artifact，再以ID引用；多个检查点共用图要解释reuse_reason。

`environment.example.json` 是**字段示例**，含无效占位SHA和版本，必须替换；不是原生环境证据。video需continuous=true且modified=false；PNG检查签名/IHDR尺寸与hash，不验证图像内容与真实截图身份。

assertions中的proof_artifact_id必须引用该case的log/metrics/trace/semantic_tree；截图或模型口头结论不能证明没有误执行。

## 能证明与不能证明

工具能够发现缺case/检查点、错误需求映射、缺文件、哈希错误、PNG尺寸不符、错误来源声明、缺日志/连续视频、commit不一致、结果文档未逐case嵌图。它不验证录像编码/连续性真实性，不验证系统截图来源，不验证硬件确实使用，不理解截图文字，也不证明日志断言本身可靠。这些仍由09复核手册及真实原生测试负责。

`test_validate_evidence.py` 使用临时目录中的合成1×1 PNG和非视频字节来测试元数据校验路径。它们仅是校验器单元数据，不是产品截图/视频；不保存到evidence目录，不计入64个产品测试结果。包内qa/validator-tests.txt仅记录这些工具测试。
