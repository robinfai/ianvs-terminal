import { Badge, Card, Notice } from '../components/ui'
import { ServerSnapshot } from '../components/ServerSnapshot'
import { useSession } from '../state/SessionContext'

export function OverviewPage() {
  const session = useSession()
  return <div className="stack page-stack">
    <div className="page-heading"><p className="eyebrow">我的工作空间</p><h1>配置有序，连接安心</h1><p className="secondary">查看服务器保存的配置，在可信客户端继续你的工作。</p></div>
    <div className="metric-grid">
      <Card title="账户访问"><Badge tone="success">已登录</Badge><p>@{session.user?.username}</p><p className="secondary">{session.mode === 'local' ? '本地服务连接' : '远程账户会话'}</p></Card>
      <Card title="敏感凭据"><Badge tone={session.key ? 'info' : 'warning'}>{session.key ? '密钥已暂存 · 待实际解密验证' : '按需解锁'}</Badge><p className="secondary">SSH 密码与私钥由客户端加密。普通字段仍可查看。</p></Card>
    </div>
    <Notice>登录密码不能恢复主密钥。密钥仅保留在当前页面内存，刷新或退出后清除。</Notice>
    <div className="row wrap"><a className="button button--primary" href="#/profiles">管理 SSH 配置</a><a className="button" href="#/sync">换机与密钥恢复指引</a></div>
    <ServerSnapshot />
    <Card title="当前服务"><p className="break-word">{session.baseUrl}</p><p className="secondary">此控制台固定连接当前站点。录制、布局和粘贴历史不在本轮同步范围内。</p></Card>
  </div>
}
