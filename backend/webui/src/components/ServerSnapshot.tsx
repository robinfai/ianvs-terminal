import { Badge, Button, Notice, Spinner } from './ui'
import { useServerSnapshot } from '../state/useServerSnapshot'

export function ServerSnapshot() {
  const { rows, loading, sampledAt, refresh } = useServerSnapshot()
  return <section className="stack" aria-labelledby="snapshot-title" aria-busy={loading}>
    <div className="section-header"><div><h2 id="snapshot-title">服务器文档状态</h2>
      <p className="secondary">仅展示当前账户的文档元信息，不代表其他设备已完成同步。</p></div>
      <Button busy={loading} onClick={() => void refresh()}>刷新服务器状态</Button></div>
    {loading && rows.length === 0 ? <div role="status"><Spinner label="正在读取服务器文档" /> 正在获取文档状态…</div> : null}
    <div className="summary-table" role="list" aria-label="同步文档">
      {rows.map(row => <div className="summary-row" role="listitem" key={row.label}>
        <div><h3>{row.label}</h3><p className="secondary">{row.description}</p></div>
        <div>{row.error ? <Notice tone="error" role="alert">{row.error}</Notice>
          : row.empty ? <><Badge>尚无文档</Badge><p className="secondary">在客户端启用同步，或创建连接配置。</p></>
          : <><Badge tone="success">服务器已保存</Badge><p className="secondary">版本 {row.resource?.revision} · {row.resource?.updated_at ? new Date(row.resource.updated_at).toLocaleString('zh-CN') : '更新时间未知'}</p></>}</div>
        <div><Badge>其他客户端状态未知</Badge><p className="secondary">服务尚未提供状态上报。</p></div>
      </div>)}
    </div>
    {sampledAt ? <p className="secondary" role="status">本次查询时间：{sampledAt}。文档中的时间是服务器更新时间，不是设备最后同步时间。</p> : null}
  </section>
}
