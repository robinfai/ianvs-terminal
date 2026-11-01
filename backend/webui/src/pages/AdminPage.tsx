import { useState } from 'react'
import { Badge, Button, Card, Dialog, EmptyState, Notice, SelectField, TextField } from '../components/ui'

// Deliberately separate, static examples. Never fetched from another user's resources.
const EXAMPLE_USERS = [
  { id: 'example-01', name: 'lin', role: '普通用户', status: '正常', sessions: 2 },
  { id: 'example-02', name: 'alex', role: '管理员', status: '正常', sessions: 1 },
  { id: 'example-03', name: 'sam', role: '普通用户', status: '已禁用', sessions: 0 },
]
type Tab = 'overview' | 'users' | 'settings' | 'audit'
const tabs: { id: Tab; title: string }[] = [{ id: 'overview', title: '服务总览' }, { id: 'users', title: '用户' }, { id: 'settings', title: '注册与系统设置' }, { id: 'audit', title: '审计' }]

export function AdminPage() {
  const [tab, setTab] = useState<Tab>('overview')
  const [demo, setDemo] = useState(false)
  const [query, setQuery] = useState('')
  const [status, setStatus] = useState('全部')
  const [selected, setSelected] = useState<(typeof EXAMPLE_USERS)[number] | null>(null)
  const [confirm, setConfirm] = useState(false)
  const visible = EXAMPLE_USERS.filter(u => u.name.includes(query.trim().toLowerCase()) && (status === '全部' || u.status === status))
  function clearDemo() { setDemo(false); setSelected(null); setConfirm(false) }

  return <div className="stack page-stack">
    <div className="page-heading"><p className="eyebrow">独立界面预览</p><h1>服务管理预览</h1><p className="secondary">了解管理流程。当前服务尚未提供管理员身份与管理接口。</p></div>
    <Notice tone="warning">未接入管理服务。此页面不授予管理员权限，不读取其他用户的数据，也不能执行账户或系统变更。</Notice>
    <div className="preview-banner row wrap"><Badge tone={demo ? 'warning' : 'neutral'}>{demo ? '演示数据 · 不是真实账户' : '未载入任何账户数据'}</Badge><Button onClick={() => demo ? clearDemo() : setDemo(true)}>{demo ? '清除演示数据' : '载入独立演示数据'}</Button></div>
    <nav className="preview-tabs row wrap" aria-label="管理预览页面">{tabs.map(item => <Button key={item.id} variant={tab === item.id ? 'primary' : 'secondary'} aria-pressed={tab === item.id} onClick={() => setTab(item.id)}>{item.title}</Button>)}</nav>
    <section aria-label={tabs.find(t => t.id === tab)?.title}>
      {tab === 'overview' ? <div className="stack"><div className="metric-grid"><Card title="账户概况"><p className="stat-value">{demo ? '3 个示例账户' : '尚未接入'}</p><p className="secondary">没有查询真实全站用户统计。</p></Card><Card title="服务健康"><Badge>未知 · 未接入管理接口</Badge><p className="secondary">当前账户可用不代表全站健康，也不代表备份已完成。</p></Card></div><Card title="管理能力边界"><ul><li>角色和禁用状态必须由服务端校验，不能依靠隐藏按钮。</li><li>管理员只管理账号元信息，不查看他人的 SSH 资料、密文或主密钥。</li><li>最后一名有效管理员的降权、禁用和删除需要后端事务保护。</li></ul><Button onClick={() => setTab('users')}>查看用户管理结构</Button></Card></div> : null}
      {tab === 'users' ? <div className="stack"><div className="row wrap"><TextField label="筛选示例用户名" value={query} onChange={e => setQuery(e.target.value)} disabled={!demo} /><SelectField label="筛选示例状态" value={status} onChange={e => setStatus(e.target.value)} disabled={!demo}><option>全部</option><option>正常</option><option>已禁用</option></SelectField></div>
        {!demo ? <EmptyState title="管理用户数据尚未接入" description="可载入独立演示数据查看结构；不会访问真实用户。" /> : <div className="console-grid"><div className="stack"><div className="table-wrap"><table><caption className="sr-only">虚构账户列表</caption><thead><tr><th>用户</th><th>角色</th><th>状态</th><th>操作</th></tr></thead><tbody>{visible.map(u => <tr key={u.id}><td>{u.name}</td><td>{u.role}</td><td><Badge tone={u.status === '正常' ? 'success' : 'warning'}>{u.status}</Badge></td><td><Button onClick={() => setSelected(u)} aria-label={`查看示例用户 ${u.name}`}>查看</Button></td></tr>)}</tbody></table></div>{visible.length === 0 ? <EmptyState title="没有匹配的示例用户" action={<Button onClick={() => { setQuery(''); setStatus('全部') }}>清空筛选</Button>} /> : null}</div>
          <Card title={selected ? `${selected.name} · 示例详情` : '选择一个示例用户'}>{selected ? <div className="stack"><p>角色：{selected.role} · 状态：{selected.status}</p><p>示例会话数：{selected.sessions}</p><p className="secondary">不展示连接主机、密码、私钥或其他业务数据。</p><Button onClick={() => setConfirm(true)}>查看禁用确认示例</Button><Button disabled>角色变更未接入</Button><Button disabled>邀请与重置凭据未接入</Button><Button disabled>删除账户未接入</Button></div> : <p className="secondary">详情仅包含账号管理元信息。</p>}</Card></div>}</div> : null}
      {tab === 'settings' ? <div className="stack"><Card title="有效配置"><p>注册策略：未知（当前接口未公开）</p><p>来源：服务部署配置文件</p><p className="secondary">尚无动态配置接口。请由部署者通过受控配置流程查看与调整；此页不能保存变更。</p><Button disabled>系统配置未接入</Button></Card><Notice>邀请、密码恢复及管理员初始化均需新增服务端契约；不会通过演示界面修改实际注册策略。</Notice></div> : null}
      {tab === 'audit' ? <Card title="脱敏审计预览">{demo ? <div className="stack"><Badge tone="warning">以下仅为静态示例</Badge><div className="table-wrap"><table><thead><tr><th>事件</th><th>对象</th><th>结果</th></tr></thead><tbody><tr><td>禁用账户</td><td>example-03</td><td>演示记录</td></tr><tr><td>拒绝最后管理员降权</td><td>example-02</td><td>演示记录</td></tr></tbody></table></div><p className="secondary">真实审计接口未接入。不记录密码、令牌、重置凭据、主密钥或 SSH 内容。</p></div> : <EmptyState title="审计查询尚未接入" description="没有把请求日志或示例事件当作真实安全审计。" />}</Card> : null}
    </section>
    <Dialog open={confirm && !!selected} title="禁用确认示例 · 不执行操作" onClose={() => setConfirm(false)} footer={<><Button data-dialog-initial-focus onClick={() => setConfirm(false)}>关闭示例</Button><Button variant="danger" disabled>未接入管理服务，无法禁用</Button></>}>
      <div className="stack"><p>示例对象：{selected?.name}</p><p>真实禁用应阻止新登录与同步、撤销全部会话并保留服务器数据。恢复后需重新登录，旧令牌不能恢复。</p><Notice tone="warning">最后一名有效管理员不可禁用。此约束尚无服务端实现，本预览不执行操作。</Notice><TextField label="禁用原因（示例，不提交）" placeholder="真实流程需记录操作原因" /><p>管理员不能恢复用户主密钥；已下载到设备的本地数据不会被远程抹除。</p></div>
    </Dialog>
  </div>
}
