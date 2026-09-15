from pathlib import Path
import re,html,json
D=Path(__file__).resolve().parent
old=(D/'comparison.html').read_text()
css=re.search(r'<style>(.*?)</style>',old,re.S).group(1)
pairs=[('设置入口','screenshots/06-settings-index.png','external-keyboard/settings.png','最初版本','本轮恢复后','恢复“外接键盘”，页头继续使用上一轮修正的居中布局。'),('快捷键列表','screenshots/16-keyboard-settings.png','external-keyboard/list-no-more.png','最初发现问题时','本轮优化后','操作名称与组合键同排；去掉每行重复的分类、作用范围和“未分配”副标题。无可用操作时不再预留空按钮位。')]
body=''
for title,b,a,bl,al,note in pairs:
 for path in [b,a]:assert (D/path).exists()
 body+=f'<section><h2>{title}</h2><p>{note}</p><div class="pair">'
 for path,label in [(b,bl),(a,al)]:body+=f'<figure><figcaption>{label}</figcaption><a class="shot" href="{path}" target="_blank"><img width="484" height="1030" src="{path}" alt="{title} · {label}"></a></figure>'
 body+='</div></section>'
body+='<section><h2>编辑与停用</h2><p>作用范围保留在录制弹窗；停用和恢复统一进入编辑弹窗；大字号允许自动换行，组合键按钮保持至少 44 点触控高度。</p><div class="supp">'
for name,label in [('edit-no-more','点击组合键后停用或修改')]:body+=f'<figure><figcaption>{label}</figcaption><a class="shot" href="external-keyboard/{name}.png" target="_blank"><img width="484" height="1030" src="external-keyboard/{name}.png" alt="{label}"></a></figure>'
body+='</div></section>'
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Trail · 外接键盘恢复与细节对比</title><style>'''+css+'''.supp{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}@media(max-width:640px){.supp{grid-template-columns:1fr}} </style><main><header><div class="eyebrow">TRAIL / iOS / 外接键盘</div><h1>恢复配置入口，精简快捷键列表</h1><p>外接键盘有配置组合键的需要，因此本轮恢复“设置 → 外接键盘”。上一轮标题、表单和其他页面的细节优化继续保留。</p><div class="stats"><span>原问题 08 · 已调整</span><span>34 项回归测试通过</span><span>iPhone 16 Plus · iOS 18.4</span></div><ul><li>常规行只保留操作名称与当前组合键。</li><li>冲突、自定义、停用状态按需显示；“未分配”只显示一次。</li><li>移除每行“…”；点按组合键进入编辑，可停用或恢复默认。</li><li>缩小筛选区与列表之间的间隔；大字号按空间换行。</li></ul><p><a href="comparison.html">上一轮整体优化对比（历史记录）</a> · <a href="index.html">最初问题标注</a></p></header>'''+body+'''<footer><p>验证：34 项测试通过，包含 iOS 按键录制、清除、自定义及桌面冲突行为，375 / 402 宽度与横屏、1～3 倍字号。静态检查没有 error / warning，90 项既有 info 提示保留。模拟器大字号已恢复，未更改用户保存的快捷键。</p><p>截图为实际模拟器画面。组合键以自动化按键事件验证，本轮未连接实体蓝牙键盘。</p></footer></main></html>'''
(D/'keyboard-comparison.html').write_text(page)
notice='<header><strong>本轮更新：外接键盘配置已恢复，并已精简列表。</strong> <a href="keyboard-comparison.html">查看最新对比</a><p>以下保留上一轮历史记录，其中“移除入口”已被本轮决定取代。</p></header>'
if notice not in old:(D/'comparison.html').write_text(old.replace('<main>','<main>'+notice,1))
(D/'external-keyboard/tests.log').write_text(Path('/tmp/keyboard-no-more-tests.log').read_text())
(D/'external-keyboard/analysis.log').write_text(Path('/tmp/external-keyboard-analyze.log').read_text())
(D/'external-keyboard/README.zh-CN.md').write_text('''# 外接键盘恢复与优化

本轮决定：恢复移动端“设置 → 外接键盘”，取代上一轮移除入口的决定。桌面编辑器与快捷键解析逻辑继续保留。

- 列表改为操作与组合键同排，大字号和窄屏允许分行。
- 移除常规行反复出现的分类、作用范围与未分配副标题。
- 冲突、自定义和停用状态按需显示；每行菜单已移除，停用与恢复默认集中在编辑弹窗。
- 外接键盘使用说明只显示一次；作用范围仍可在录制时配置。
- 34 项设置和快捷键回归测试通过；静态检查无 error / warning，既有 90 项 info。
- iOS 模拟器验证入口、列表、录制弹窗；上一版已验证系统 XXXL 字号。未连接实体蓝牙键盘，按键事件由自动化测试验证。未保存任何用户快捷键变更，字号已恢复。

[查看最新前后对比](../keyboard-comparison.html)
''')
print('Built keyboard-comparison.html')
