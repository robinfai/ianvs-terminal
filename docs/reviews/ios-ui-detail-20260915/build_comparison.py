from pathlib import Path
import html,json
D=Path(__file__).resolve().parent
findings=json.loads((D/'findings.json').read_text())
changes={
'01':'页头按屏幕中心对齐；保留两侧操作空间，按实际行高适配大字号。',
'02':'移除首页、外观页和展开项内重复标题。首页管理入口改为带文字的次级按钮。',
'03':'本机保存说明保留一次；选项仅描述同步行为，底部仅说明保存后生效。',
'04':'移动端统一使用“连接”和“回放”；私钥空状态及显隐提示完成本地化；启动跳过选项统一为“仅此设备”。',
'05':'iOS 外观与恢复说明使用设备、会话语境；提醒权限去掉 Dock 说法，保留不会激活应用的边界。',
'06':'Agent、X11 关闭时收起技术说明；启用后显示次级帮助与相关字段。',
'07':'从“管理连接”新建时，未填写名称则以主机地址命名；显式名称继续保留。',
'08':'按你的决定，移动端移除快捷键配置入口；桌面编辑器保留。终端输入按键栏继续可用。',
'09':'没有可用连接时仅显示创建连接的指引，隐藏不可用的筛选框与预设卡片。',
'10':'错误横幅改为简短中文提示；具体失败原因、地址与退出码保留在可选择复制的详情中，关闭入口保留。',
'11':'“待确认”的通用原因只解释一次；每项保留状态、用途及具体异常原因。',
'12':'终端输入连接传递当前明暗主题，并在依赖变化时更新；模拟器重新打开键盘后确认深色一致。',
'13':'四个终端工具栏图标从主题默认 20 调整为 24，保留文字标签和原有触控区域。',
'14':'搜索选项简化为“智能大小写 / 区分大小写 / 忽略大小写 / 正则 · …”，匹配逻辑不变。',
}
# Original screenshots are preserved. Boxes below are HTML overlays, not pixel edits.
pairs=[
('08','06-settings-index','06-settings-index','移动端设置','五个入口 → 四个入口；快捷键配置已移除。',[38,204,406,230]),
('01','01-connections','01-connections','连接首页','标题居中；管理连接移至新建按钮下方，移除重复小标题。',[28,143,428,265]),
('02','08-default-profile','08-default-profile','默认连接','展开后不再重复标签；移除移动端无法对应的 Profile 编辑说明。',[40,238,404,178]),
('05','09-settings-appearance','09-settings-appearance','外观设置','去掉重复外观标题，缩短主题说明与启动说明。',[40,195,405,378]),
('09','10-terminal-presets','10-terminal-presets','没有连接时的配色','筛选框和不可选卡片由一条创建指引替代。',[40,406,405,119]),
('03','13-sync','13-sync','同步设置','总说明、选择和保存生效各表达一次。',[40,210,405,236]),
('03','14-sync-form','14-sync-form','同步服务表单','登录和加密说明保留；重复的本地数据说明已精简。',[40,207,405,606]),
('04','20-manage-connections','20-manage-connections','管理连接空状态','搜索提示与空状态统一为“连接”。',[60,717,370,232]),
('04','21-manage-new-ssh','21-manage-new-ssh','私钥与显隐提示','私钥未选提示本地化，密码按钮提供中文辅助说明。',[40,551,404,225]),
('06','05-ssh-bottom','05-ssh-bottom','SSH 高级选项','同一表单组件；前图为新建连接，后图为管理连接中的保存表单。关注 Agent / X11 两行，底部操作不同。',[46,751,387,91]),
('07','25-managed-connection','25-managed-connection','保存后的默认名称','同为本机测试连接；后图使用端口 1 验证拒绝连接，不含密码。',[42,207,400,67]),
('10','29-connection-failure','29-connection-failure','连接失败提示','将多行技术错误收进详情，列表不再被长英文错误明显挤压。',[28,191,429,65]),
('11','36-session-capabilities','36-session-capabilities','会话能力','相同终端夹具、13 项待确认。每项不再重复同一句原因。',[60,347,365,521]),
('12','48-terminal-keyboard-accessory','48-terminal-keyboard-accessory','深色终端键盘','相同终端夹具；后图为修正后重新打开的系统键盘。',[28,711,429,289]),
('13','30-terminal-dark','30-terminal-dark','终端工具栏','四个图标适度放大，保留文字标签。',[28,914,429,68]),
('14','33-search-options','33-search-options','搜索模式','去掉“子字符串”等冗长说法，保留大小写和正则差异。',[110,257,235,251]),
('08','38-settings-dark','38-settings-dark','深色设置','深色主题同步验证。',[38,204,406,230]),
('01','41-large-text','41-large-text','系统大字号','相同 XXXL 系统字号，页头与主要选项无溢出；测试另外覆盖 3 倍字号与横屏。',[28,144,429,628]),
]
sections=[]
for n,(fid,b,a,title,note,box) in enumerate(pairs):
 assert (D/'screenshots'/f'{b}.png').exists(),b
 assert (D/'after'/f'{a}.png').exists(),a
 f=next(x for x in findings if x['id']==fid)
 def fig(folder,shot,label,rect):
  x,y,w,h=rect
  overlay=f'<span class="box" style="left:{x/484*100:.3f}%;top:{y/1030*100:.3f}%;width:{w/484*100:.3f}%;height:{h/1030*100:.3f}%"></span>'
  return f'<figure><figcaption>{label}</figcaption><a class="shot" href="{folder}/{shot}.png" target="_blank"><img width="484" height="1030" src="{folder}/{shot}.png" loading="lazy" alt="{title}：{label}">{overlay}</a></figure>'
 original=f['box'] if f['shot']==b else box
 sections.append(f'<section id="pair-{n}"><div class="heading"><span class="tag">问题 {fid}</span><h2>{title}</h2></div><p>{note}</p><div class="pair">'+fig('screenshots',b,'优化前',original)+fig('after',a,'优化后',box)+'</div></section>')
rows=''.join(f'<tr><td>{f["id"]}</td><td>{html.escape(f["title"])}</td><td>{html.escape(changes[f["id"]])}</td></tr>' for f in findings)
nav=''.join(f'<a href="#pair-{n}">{title}</a>' for n,(_,_,_,title,_,_) in enumerate(pairs))
out='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Trail · iOS 细节优化对比</title><style>
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f4f5f7;color:#182533;font:15px/1.65 system-ui,-apple-system,sans-serif}main{max-width:1140px;margin:auto;padding:40px 26px 80px}header{background:#fff;padding:28px;border-radius:16px;margin-bottom:20px}h1{font-size:29px;line-height:1.35;margin:8px 0 14px}h2{font-size:21px;margin:0}p{margin:10px 0;color:#4d5b68}.eyebrow{font-size:12px;letter-spacing:1px;color:#316a8f}.stats{display:flex;flex-wrap:wrap;gap:8px;margin:16px 0}.stats span,.tag{font-size:12px;background:#e9f2f8;color:#235577;border-radius:6px;padding:4px 9px}a{color:#1765a0;text-decoration:none}nav{display:flex;flex-wrap:wrap;gap:6px 15px;margin:18px 0}details{background:white;border-radius:12px;padding:18px;margin:20px 0}summary{cursor:pointer;font-weight:600}table{border-collapse:collapse;width:100%;margin-top:18px}td,th{border-bottom:1px solid #e4e8ec;padding:10px;text-align:left;vertical-align:top}td:nth-child(2){width:27%}section{scroll-margin-top:18px;background:white;border-radius:16px;margin:24px 0;padding:24px}.heading{display:flex;gap:12px;align-items:center}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;max-width:920px;margin:auto}figure{margin:0;min-width:0}figcaption{font-size:14px;font-weight:650;text-align:center;padding:10px}.shot{position:relative;display:block;line-height:0}.shot img{display:block;width:100%;height:auto;border-radius:10px}.box{position:absolute;border:2px solid #ee8b32;border-radius:5px;pointer-events:none}figure:nth-child(2) .box{border-color:#159b7e}.hide-boxes .box{display:none}.controls{display:flex;gap:20px;align-items:center}.note{font-size:13px}footer{font-size:13px;color:#596570}button{font:inherit;border:1px solid #d2dae2;background:white;border-radius:7px;padding:7px 12px;cursor:pointer}@media(max-width:640px){main{padding:18px 10px}section{padding:16px 10px}.pair{gap:6px}h1{font-size:23px}table{font-size:13px}.heading{align-items:flex-start}td{padding:7px}nav{font-size:13px}}
</style><main><header><div class="eyebrow">TRAIL / iOS / 2026-09-15</div><h1>细节优化 · 前后对比</h1><p>按原检查清单完成一轮局部优化。移动端已移除快捷键配置，桌面编辑功能保留。</p><div class="stats"><span>14 项问题逐项处理</span><span>18 组前后截图</span><span>103 项回归测试通过</span><span>iPhone 16 Plus · iOS 18.4</span></div><p class="note">截图来自真实模拟器，原图保留。橙框标示原问题区域，绿框标示本轮关注区域；点图可查看原尺寸。浅色配置页使用实际应用数据；终端、能力与深色页面使用与上轮相同的会话夹具，不能据此认定真实 SSH / SFTP 业务通过。</p><div class="controls"><button onclick="document.body.classList.toggle('hide-boxes')">显示／隐藏标注框</button><a href="index.html">查看原问题标注</a><a href="after/29b-error-details.png" target="_blank">查看错误详情截图</a></div><nav>'''+nav+'''</nav></header><details><summary>展开 14 项处理记录</summary><table><thead><tr><th>编号</th><th>原问题</th><th>本轮调整</th></tr></thead><tbody>'''+rows+'''</tbody></table></details>'''+''.join(sections)+'''<footer><p>验证：86 项应用组件与行为测试 + 17 项终端键盘和手势测试通过；包含 375 / 402 宽度、横屏及 1～3 倍文字。模拟器运行时错误查询为空。静态检查无 error / warning，仓库已有 info 提示仍保留。</p><p>启动“仅此设备”已修改并检查代码，本轮未重置已有引导状态。未执行真实服务器登录、SFTP 传输、录制回放文件和同步账户登录。临时测试连接已清理，系统字号已恢复，最终运行入口恢复为 main.dart。</p></footer></main></html>'''
(D/'comparison.html').write_text(out)
(D/'changes.json').write_text(json.dumps(changes,ensure_ascii=False,indent=2)+'\n')
print('Wrote comparison.html with',len(pairs),'verified image pairs')
