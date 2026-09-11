import { useEffect, useRef, useState } from 'react';
import content from './content.json';

const { items, matrix } = content;
const groups = [...new Set(items.map(item => item.group))];
const initial = () => items.find(item => item.id === location.hash.slice(1)) || items[0];

function ImageViewer({ asset, onClose }) {
  const dialog = useRef(null);
  const [zoom, setZoom] = useState(100);
  useEffect(() => { const el = dialog.current; el.showModal(); return () => el.close(); }, []);
  return <dialog className="viewer" ref={dialog} onCancel={onClose} onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
    <div className="viewer-bar"><strong>{asset.title}</strong><label>缩放 <input aria-label="图片缩放" type="range" min="50" max="200" step="25" value={zoom} onChange={e => setZoom(+e.target.value)} /><output>{zoom}%</output></label><a href={asset.src} target="_blank" rel="noreferrer">打开原图</a><button onClick={onClose} autoFocus>关闭</button></div>
    <div className="viewer-scroll"><img src={asset.src} alt={asset.title} style={{ width: `${zoom}%` }} /></div>
  </dialog>;
}

export function App() {
  const [selected, setSelected] = useState(initial);
  const [tab, setTab] = useState('screens');
  const [mode, setMode] = useState('compare');
  const [asset, setAsset] = useState(null);
  const [navigation, setNavigation] = useState(false);
  const index = items.indexOf(selected);
  const shownMode = selected.before ? mode : 'after';
  const choose = item => { setSelected(item); setTab('screens'); setNavigation(false); history.replaceState(null, '', `#${item.id}`); window.scrollTo({ top: 0 }); };
  useEffect(() => { const hash = () => { const item = items.find(value => value.id === location.hash.slice(1)); if (item) setSelected(item); }; addEventListener('hashchange', hash); return () => removeEventListener('hashchange', hash); }, []);
  useEffect(() => {
    const key = e => {
      if (asset || tab !== 'screens' || /INPUT|SELECT|TEXTAREA/.test(e.target.tagName)) return;
      if (e.key === 'ArrowRight' && index < items.length - 1) { e.preventDefault(); choose(items[index + 1]); }
      if (e.key === 'ArrowLeft' && index > 0) { e.preventDefault(); choose(items[index - 1]); }
    };
    addEventListener('keydown', key); return () => removeEventListener('keydown', key);
  }, [asset, index, tab]);

  const imageCard = (version, src) => <figure className="screen-card" key={version}>
    <figcaption><span className={`version ${version}`}>{version === 'before' ? '调整前' : '调整后'}</span><span>{version === 'after' ? selected.afterLabel : selected.beforeLabel}</span></figcaption>
    <button className="screenshot-button" aria-label={`放大${version === 'before' ? '调整前' : '调整后'}：${selected.title}`} onClick={() => setAsset({ src, title: `${selected.title} · ${version === 'before' ? '调整前' : '调整后'}` })}><img key={src} src={src} alt={`${selected.title}，${version === 'before' ? '调整前' : '调整后'}实际截图`} /></button>
    <div className="image-foot">{selected.id === 'native' ? 'Simulator 原生截图' : 'iPhone 17 · 402 × 874 pt'}<span>点击放大</span></div>
  </figure>;

  return <div className="app">
    <a className="skip-link" href="#main">跳到对比内容</a>
    <header className="topbar"><div className="brand">Trail <span>iOS 设计对比</span></div><div className="top-meta">0.1.0 <span>·</span> 2026.09.11 <span className="local-label">本机临时预览</span></div></header>
    <div className="workspace">
      <aside className={navigation ? 'sidebar expanded' : 'sidebar'}>
        <button className="mobile-nav" aria-expanded={navigation} onClick={() => setNavigation(!navigation)}>{selected.title} · 选择场景</button>
        <nav aria-label="对比场景"><div className="nav-label">界面与流程 <span>{items.length}</span></div>{groups.map(group => <section className="nav-group" key={group}><h2>{group}</h2>{items.filter(item => item.group === group).map(item => <button key={item.id} className={item.id === selected.id && tab === 'screens' ? 'nav-item active' : 'nav-item'} aria-current={item.id === selected.id && tab === 'screens' ? 'page' : undefined} onClick={() => choose(item)}>{item.title}{!item.before && <span className="small-tag">补充</span>}</button>)}</section>)}</nav>
        <div className="sidebar-foot">实际运行截图<br />iPhone 17 模拟器 · iOS 26.3</div>
      </aside>
      <main id="main" tabIndex="-1">
        <div className="page-tabs" aria-label="内容类型"><button className={tab === 'screens' ? 'selected' : ''} aria-pressed={tab === 'screens'} onClick={() => setTab('screens')}>前后截图</button><button className={tab === 'matrix' ? 'selected' : ''} aria-pressed={tab === 'matrix'} onClick={() => setTab('matrix')}>功能取舍 <span>{matrix.length}</span></button><button className={tab === 'evidence' ? 'selected' : ''} aria-pressed={tab === 'evidence'} onClick={() => setTab('evidence')}>验证与边界</button></div>
        {tab === 'screens' && <>
          <div className="heading-row"><div><div className="eyebrow">{selected.group}</div><h1>{selected.title}</h1><p className="intro">{selected.summary}</p></div><div className="pagination"><button aria-label="上一个场景" disabled={index === 0} onClick={() => choose(items[index - 1])}>上一项</button><span>{index + 1} / {items.length}</span><button aria-label="下一个场景" disabled={index === items.length - 1} onClick={() => choose(items[index + 1])}>下一项</button></div></div>
          <div className="compare-toolbar"><div className="segmented"><button disabled={!selected.before} className={shownMode === 'compare' ? 'selected' : ''} aria-pressed={shownMode === 'compare'} onClick={() => setMode('compare')}>并排对比</button><button className={shownMode === 'after' ? 'selected' : ''} aria-pressed={shownMode === 'after'} onClick={() => setMode('after')}>只看调整后</button></div><span>{!selected.before ? '补充截图 · 没有对应的调整前截图' : '原比例显示 · 点击截图查看细节'}</span></div>
          {selected.reference && <button className="reference-link" onClick={() => setAsset({ src: selected.reference, title: "第 3 张 · 常用项优先设计稿" })}>查看选定设计稿</button>}{selected.note && <p className="state-note"><strong>截图说明</strong>{selected.note}</p>}
          <div className={`comparison ${!selected.before || mode === 'after' ? 'single' : ''}`}>{selected.before && mode === 'compare' && imageCard('before', selected.before)}{imageCard('after', selected.after)}</div>
          <section className="change-notes"><h2>这一页调整了什么</h2><ol>{selected.changes.map((text, i) => <li key={text}><span>{String(i + 1).padStart(2, '0')}</span>{text}</li>)}</ol></section>
          <p className="source-note">除“原生触控复核”外，截图来自 Flutter 渲染层，不含系统状态栏和软键盘。查看原生截图可核对键盘是否收起。</p>
        </>}
        {tab === 'matrix' && <section className="document"><div className="eyebrow">移动端功能范围</div><h1>功能保留、收敛与层级</h1><p className="intro">连接 → 终端会话 → 文件 / 搜索 / 录制 / 回看</p><div className="table-scroll"><table><thead><tr><th>功能</th><th>手机入口与处理</th><th>保留能力与边界</th></tr></thead><tbody>{matrix.map(([name, treatment, boundary]) => <tr key={name}><th scope="row">{name}</th><td>{treatment}</td><td>{boundary}</td></tr>)}</tbody></table></div></section>}
        {tab === 'evidence' && <section className="document evidence"><div className="eyebrow">验证记录</div><h1>证据与适用范围</h1><div className="evidence-stat"><strong>{content.verificationCount}</strong><span>项本轮相关回归通过</span></div><h2>本轮紧凑尺度</h2><p>第 3 张“常用项优先”已接入 Flutter。左侧“本轮”以收紧前结果为基线；“上一轮”保留功能层级调整记录。</p><h2>已经核对</h2><ul><li>iPhone 17 模拟器，iOS 26.3，402 × 874 pt，全流程实际渲染截图。</li><li>组件覆盖 375 × 667、402 × 874、874 × 402，1 / 2 / 3 倍文字；主要点击目标至少 44 pt。</li><li>会话返回、切换与关闭；播放暂停、拖动恢复、后台暂停、搜索、倍速和专注模式。</li><li>原生集成截图覆盖连接、设置、终端、文件和回放；Luna确认播放器无键盘遮挡，播放交互由组件测试验证。</li></ul><h2>本轮验证的边界</h2><ul><li>连接、文件和录制使用内存夹具。这些证据不证明真实 SSH 传输或生产同步服务可用。</li><li>没有完成全量 VoiceOver 人工遍历，也没有新增文件与回放页面的交互式边缘返回手势。</li><li>通用连接配置组件截图，不等于 iOS 开放了本地 shell 或桌面能力。</li><li>本网页显示模拟器验证结果，不能以此证明新版本已安装到真机。</li></ul><h2>截图阅读提示</h2><p>相同功能不一定是相同交互状态，页面顶部会标注差别。没有对应基线的截图标为“补充”。旧的系统主屏幕与已修复键盘回归截图未混入最终效果。</p><a className="text-link" href="/density-review-notes.md" target="_blank" rel="noreferrer">打开本轮验证说明</a></section>}
      </main>
    </div>
    {asset && <ImageViewer asset={asset} onClose={() => setAsset(null)} />}
  </div>;
}
