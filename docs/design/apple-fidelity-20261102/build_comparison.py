from pathlib import Path
import json
root=Path('docs/design/apple-fidelity-20261102')
scenes=[
('history','历史会话',None,'history-light',[(14,6,80,7,'1'),(4,24,92,13,'2'),(4,39,92,28,'3'),(27,87,46,7,'4')],['1 导航差异：保留现有全屏返回与管理入口；原稿为关闭式面板。','2 当前会话独立分组；标题 17 / 摘要 15，保留选中标识。','3 最近会话恢复同一白色分组；连续分隔线，移除独立卡片间距。','4 新建会话为 48 pt 蓝色胶囊按钮。会话文案、条数使用测试数据。']),
('approval','AI 审批卡',(22,80,456,982),'approval-light',[(3,7,94,16,'1'),(4,24,92,37,'2'),(7,38,86,7,'3'),(44,52,50,7,'4')],['1 浅蓝用户气泡 / 白色回复，分组底色；角色保留语义标签。','2 白色圆角卡：待确认 → 目的 → 目标和目录 → 命令 → 审核说明。','3 完整命令可选取、滚动阅读，不以省略号替代。','4 拒绝和审阅分离，审阅不执行。顶部保留现有任务状态栏；底部独立输入组件未深入改动。']),
('ssh','SSH 连接',(496,80,448,982),'ssh-light',[(4,18,92,18,'1'),(4,41,92,27,'2'),(4,72,92,7,'3'),(4,80,92,15,'4')],['1 主机、用户、端口恢复在连接分组内，常规行高至少 48 pt。','2 验证字段共用无外框行样式。私钥保留独立一行和删除操作，较原稿多占一行。','3 更多连接设置恢复白色分组，保留高级设置内容。','4 保存为独立开关；连接为 48 pt 主按钮。测试状态为空密码，未伪造已保存凭据。']),
('sync','同步表单',(964,80,455,982),'sync-password-light',[(4,15,92,26,'1'),(4,44,92,36,'2'),(12,89,84,7,'3')],['1 当前生效模式与编辑中的模式分开，未保存状态继续显示。','2 模式 / 账户分组；长 API 地址独占一行；密码状态与原稿同类。','3 密码模式保留“保存更改”；默认 Apple 模式显示 Apple 登录按钮。两种实际状态均附截图，未恢复旧的密码默认入口。']),
]
css='''*{box-sizing:border-box}body{margin:0;background:#f5f5f7;color:#1d1d1f;font:15px -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}header,main{width:1294px;margin:auto}header{padding:28px 0 18px}h1{font-size:28px;margin:8px 0}p{color:#666;line-height:1.6}nav{display:flex;gap:10px;margin:16px 0}a{color:#007aff;text-decoration:none}nav a{padding:8px 16px;border-radius:20px;background:white}article{background:white;padding:20px;border-radius:20px;margin-bottom:24px}.grid{display:grid;grid-template-columns:402px 402px 402px;gap:24px}h2{font-size:17px;margin:0 0 12px}.phone{width:402px;height:874px;overflow:hidden;position:relative;border:1px solid #ddd;border-radius:16px;background:#f2f2f7}.phone>img{width:100%;display:block}.crop>img{max-width:none;position:absolute}.mark{position:absolute;border:2px solid #fa8200;border-radius:10px;background:#ff990007}.mark b{position:absolute;top:-11px;left:-8px;background:#d66a00;border:2px solid white;color:white;width:25px;height:25px;border-radius:50%;font-size:13px;display:grid;place-items:center}.notes{padding:12px 0;display:grid;grid-template-columns:1fr 1fr;gap:8px 30px}.notes p{margin:0;font-size:14px}.small{font-size:13px}.extra{display:flex;gap:20px}.extra img{width:240px;border:1px solid #ddd;border-radius:12px}footer{padding:20px 0 40px;color:#777}'''
nav='<nav>'+''.join(f'<a href="{key}.html">{title}</a>' for key,title,*_ in scenes)+'<a href="index.html">全部</a></nav>'
intro='<p>以原始审批稿为参考，实际列使用 iOS 27.0 模拟器原生截图（402 × 874 pt）。两端按等宽展示；概念稿与系统安全区、数据状态不同，不做伪像素差异计算。</p>'
blocks=[]
for key,title,crop,actual,marks,notes in scenes:
 if crop:
  x,y,w,h=crop; scale=402/w
  ref=f'<div class="phone crop"><img src="reference/core.png" style="width:{1440*scale}px;left:{-x*scale}px;top:{-y*scale}px"></div>'
 else:ref='<div class="phone"><img src="reference/history.png"></div>'
 real=f'<div class="phone"><img src="simulator/{actual}.png"></div>'
 ann=f'<div class="phone"><img src="simulator/{actual}.png">'+''.join(f'<div class="mark" style="left:{x}%;top:{y}%;width:{w}%;height:{h}%"><b>{n}</b></div>' for x,y,w,h,n in marks)+'</div>'
 block=f'<article id="{key}"><h1>{title}</h1><div class="grid"><section><h2>原设计稿</h2>{ref}</section><section><h2>实际实现 · 模拟器</h2>{real}</section><section><h2>差异标注 · 实际截图</h2>{ann}</section></div><div class="notes">'+''.join(f'<p>{n}</p>' for n in notes)+'</div></article>'
 blocks.append(block)
 html=f'<!doctype html><meta charset="utf-8"><title>{title} · 设计还原对比</title><style>{css}</style><header><h1>Trail · 原稿还原对比</h1>{nav}{intro}</header><main>{block}<footer>橙色编号定位对应说明；截图没有重绘。基础规范：页面边距 20、组内 16、组间 24、分组圆角 16、主按钮 48。</footer></main>'
 (root/f'{key}.html').write_text(html)
extras='<article><h1>原生补充状态</h1><p>深色、完整命令审阅、键盘，以及默认 Apple 登录。点击查看原始尺寸。</p><div class="extra">'+''.join(f'<a href="simulator/{n}.png"><img src="simulator/{n}.png"><p>{label}</p></a>' for n,label in [('history-dark','历史 · 深色'),('approval-review-light','完整命令审阅'),('ssh-keyboard-light','SSH · 键盘'),('sync-light','同步 · Apple 默认')])+'</div></article>'
(root/'index.html').write_text(f'<!doctype html><meta charset="utf-8"><title>Trail 设计还原 · 三栏对比</title><style>{css}</style><header><h1>Trail · 原稿 / 实现 / 差异标注</h1>{nav}{intro}</header><main>'+''.join(blocks)+extras+'</main>')
(root/'manifest.json').write_text(json.dumps({'reference':'../apple-rethink-20261101/full','actual':'iOS simulator 27.0, native Flutter production widgets, isolated in-memory fixtures','logicalSize':[402,874],'terminalRendererChanged':False,'scenes':[s[0] for s in scenes],'regressionTests':205},ensure_ascii=False,indent=2))
