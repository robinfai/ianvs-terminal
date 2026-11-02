import { useCallback, useEffect, useState } from 'react'
import { LinkedSignInMethods } from '../components/AppleSignIn'
import { ApiError } from '../api/client'
import { useSession } from '../state/SessionContext'
import { Badge, Button, Card, Dialog, EmptyState, Notice, Spinner } from '../components/ui'

type SessionRow = { id: string; device_name: string; created_at: string; expires_at: string; current: boolean }
export function SettingsPage() {
  const session = useSession()
  const [sessions, setSessions] = useState<SessionRow[]>([])
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [loaded, setLoaded] = useState(false)
  const [busy, setBusy] = useState(false)
  const [expired, setExpired] = useState(false)
  const [confirm, setConfirm] = useState<SessionRow[] | 'logout' | null>(null)
  const reportError = useCallback((err: unknown) => {
    if (err instanceof ApiError && err.status === 401) { setExpired(true); session.clearKey(); setSessions([]); setError('当前会话已过期或被撤销，请重新登录。'); return }
    if (err instanceof ApiError && err.status === 403) { setError('当前身份无权执行此操作。请确认连接模式和访问权限。'); return }
    setError('请求结果未能确认。请刷新会话列表核对；不要把连接失败当作操作成功。')
  }, [session.clearKey])
  const refresh = useCallback(async () => {
    if (!session.client || session.mode !== 'remote') return
    setLoading(true); setError(null)
    try { setSessions((await session.client.listSessions()).sessions); setLoaded(true); setExpired(false) }
    catch (err) { reportError(err) }
    finally { setLoading(false) }
  }, [session.client, session.mode, reportError])
  useEffect(() => { void refresh() }, [refresh])
  const perform = async () => {
    if (!confirm || busy) return
    const action = confirm
    setBusy(true); setError(null); setMessage(null)
    try {
      if (action === 'logout') {
        if (session.client && session.mode === 'remote') await session.client.logout()
        session.signOut()
      } else if (session.client) {
        let successful = 0
        let lastError: unknown
        for (const item of action) {
          try { await session.client.revokeSession(item.id); successful++ } catch (err) { lastError = err }
        }
        setMessage(`已确认撤销 ${successful} / ${action.length} 个会话。${successful < action.length ? '其余会话未确认，请核对最新列表后重试。' : '这些客户端需要重新登录。'}`)
        await refresh()
        if (lastError) reportError(lastError)
      }
      setConfirm(null)
    } catch (err) { reportError(err); setConfirm(null) }
    finally { setBusy(false) }
  }
  return <div className="page">
    <header className="page__header"><div><p className="eyebrow">账户 / 安全</p><h1 className="page__title">安全与会话</h1><p className="page__subtitle">查看有效登录，收回访问权限，并管理此页面中的数据密钥。</p></div></header>
    {error && <Notice tone="error" role="alert">{error}{expired && <Button onClick={session.signOut}>清除此会话并重新登录</Button>}</Notice>}
    {message && <Notice tone="info" role="status">{message}</Notice>}
    <Card title="当前账户"><dl className="kv-list"><div className="kv"><dt>用户名</dt><dd>@{session.user?.username}</dd></div><div className="kv"><dt>服务地址</dt><dd className="break-word">{session.baseUrl}</dd></div><div className="kv"><dt>连接方式</dt><dd><Badge>{session.mode === 'remote' ? '远程账户' : '本地服务'}</Badge></dd></div></dl></Card>
    {session.mode === 'remote' && <Card title="有效登录会话" actions={<Button disabled={busy || loading || expired} onClick={() => void refresh()}>刷新列表</Button>}><div className="stack">
      <p className="secondary">设备名只是登录备注。同一设备可以有多个会话；关闭标签页不会退出服务器会话。</p>
      {loading && <div className="row"><Spinner label="正在获取会话" /><span>正在获取会话…</span></div>}
      {loaded && !expired && <p>{sessions.length} 个已签发的有效会话 · 最多 8 个登录名额。待完成登录也占用名额，最多五分钟，未列在下方。</p>}
      {loaded && !loading && !expired && sessions.length === 0 && <EmptyState title="未返回有效会话" description="请刷新核对当前登录状态；这不代表其他设备的数据已被删除。" />}
      {sessions.map(item => <div className="session-row" key={item.id}><div className="stack"><strong className="break-word">{item.device_name || '旧会话 · 设备未知'} {item.current && <Badge tone="info">当前会话</Badge>}</strong><span className="secondary">会话 {item.id.slice(0, 8)}</span><span>创建：{new Date(item.created_at).toLocaleString('zh-CN')}</span><span>到期：{new Date(item.expires_at).toLocaleString('zh-CN')}</span></div>{!item.current && <Button variant="danger" disabled={busy || loading || expired} onClick={() => setConfirm([item])}>撤销此会话</Button>}</div>)}
      <div><Button variant="danger" disabled={busy || loading || expired || !sessions.some(item => !item.current)} onClick={() => setConfirm(sessions.filter(item => !item.current))}>退出其他会话</Button></div>
    </div></Card>}
    <Card title="数据密钥"><div className="stack"><p>登录不校验数据密钥。查看或改写敏感内容时，浏览器会按需请求密钥，并仅将其保留在页面内存中。</p><div className="row"><Badge tone="neutral">{session.key ? '已提供密钥 · 有效性由实际操作校验' : '本页未保存密钥'}</Badge><Badge>密钥不上传服务器</Badge></div><p className="secondary">刷新页面、退出或忘记密钥会清除此页密钥。忘记密钥不会删除服务器数据，也不会更换原密钥。</p>{session.key && <div><Button onClick={session.clearKey}>忘记此页密钥</Button></div>}</div></Card>
    {session.mode === 'remote' && <Card title="登录方式"><LinkedSignInMethods /></Card>}
    <Card title={session.mode === 'remote' ? '退出当前账户' : '断开本地控制台'}><div className="stack"><p className="secondary">{session.mode === 'remote' ? '退出将撤销当前服务器会话，并清除此控制台身份与页面内存中的密钥。不会删除本地数据。' : '仅清除此控制台身份与密钥，不停止正在运行的本地服务。'}</p><div><Button variant="danger" disabled={busy} onClick={() => setConfirm('logout')}>{session.mode === 'remote' ? '退出当前账户' : '断开连接'}</Button></div></div></Card>
    {confirm && <Dialog open title={confirm === 'logout' ? '确认退出当前会话？' : `确认撤销 ${confirm.length} 个会话？`} onClose={() => { if (!busy) setConfirm(null) }} footer={<><Button data-dialog-initial-focus disabled={busy} onClick={() => setConfirm(null)}>取消</Button><Button variant="danger" busy={busy} onClick={() => void perform()}>{confirm === 'logout' ? '确认退出' : '确认撤销'}</Button></>}><div className="stack">{confirm !== 'logout' && <ul>{confirm.map(item => <li className="break-word" key={item.id}>{item.device_name || '设备未知'} · {item.id.slice(0, 8)}</li>)}</ul>}<p>操作成功后，需要重新登录才能恢复访问。此操作不会远程删除已下载的数据。</p><p className="secondary">若网络中断，将明确提示结果未确认；请刷新核对，不会显示虚假的撤销成功。</p></div></Dialog>}
  </div>
}
