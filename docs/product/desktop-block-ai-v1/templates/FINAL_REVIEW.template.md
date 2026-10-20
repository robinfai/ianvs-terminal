# 最终桌面复核入口

## 身份

最终分支/PR：待填；实现 C4：待填；证据 E：待填；工作树：待填。

## 四阶段状态

D1/D2/D3/D4的真实状态与results相对链接。

## 源码、二进制与证据一致性

C4、锁文件、native库/字体/镜像closure、二进制hash；C4..E仅文档/证据。后续任何受影响修改重新采证。

## 原始图、视频与日志

manifest.json、逐case嵌图、原生平台与物理设备记录。

## Native gates

make verify、Composer/AI/API/ACP/SSH/TUI、中文IME、VoiceOver、性能、DPI、手机回归。每项给范围，不将聚焦测试替代完整gate。

## 发布与支持范围

macOS支持版本逐项实际验证；Linux/Windows当前能力和证据单列。缺环境不能宣称全平台通过。

## 返工与回滚

未过case、开放P0/P1、已接受P2、如何回滚且不复活已死Session或覆盖生产数据。

## 最终判定

verified / implemented_unverified / blocked / failed。填写证据支持的结论，不写笼统“全部完成”。
