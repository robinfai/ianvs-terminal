import { useState } from 'react'
import { Badge, Button, Card, Notice } from '../components/ui'
import { ServerSnapshot } from '../components/ServerSnapshot'
import { useSession } from '../state/SessionContext'

export function SyncPage() {
  const session = useSession()
  const [guide, setGuide] = useState(false)
  const [step, setStep] = useState(0)
  const [lost, setLost] = useState(false)
  const steps = ['确认账户与服务', '准备原主密钥', '在客户端检查结果']
  return <div className="stack page-stack">
    <div className="page-heading"><p className="eyebrow">同步与换机</p><h1>{guide ? '在新设备继续使用 Ianvs' : '掌握你的同步状态'}</h1><p className="secondary">账户访问与敏感凭据解锁分开完成。普通连接信息与偏好目前未加密。</p></div>
    <div className="row wrap"><Badge tone="success">账户已登录</Badge><Badge tone={session.key ? 'info' : 'warning'}>{session.key ? '页面已暂存密钥，尚不代表解密成功' : '敏感凭据按需解锁'}</Badge></div>
    <Button variant={guide ? 'secondary' : 'primary'} onClick={() => setGuide(!guide)} aria-expanded={guide}>{guide ? '返回同步面板' : '打开换机与恢复指引'}</Button>
    {guide ? <div className="console-grid">
      <section className="stack" aria-label="换机步骤">
        <ol className="step-list">{steps.map((label, index) => <li key={label} aria-current={step === index ? 'step' : undefined}><button className="step-button" onClick={() => setStep(index)} aria-current={step === index ? 'step' : undefined}><span className="step-number">{index + 1}</span>{label}</button></li>)}</ol>
        <Card title={steps[step]}>
          {step === 0 ? <div className="stack"><p>当前账户：@{session.user?.username}</p><p className="break-word">当前服务：{session.baseUrl}</p><p>确认与旧设备使用同一账户、同一服务。登录成功不代表原主密钥已经恢复。</p><Button variant="primary" onClick={() => setStep(1)}>账户正确，继续</Button></div> : null}
          {step === 1 ? <div className="stack"><p>优先在可信旧设备中确认原主密钥。Apple 平台可使用已有钥匙串同步；其他设备使用客户端支持的 portable key 导入方式。</p><p>Web 仅在查看或重写敏感凭据时按需索取密钥，不把它发送到服务器。此指引不会替你生成或恢复密钥。</p><div className="row wrap"><Button variant="primary" onClick={() => setStep(2)}>查看验证步骤</Button><Button onClick={() => setLost(!lost)} aria-expanded={lost}>没有旧设备或备份</Button></div>{lost ? <Notice tone="warning">无法恢复原主密钥时，既有敏感凭据无法解密。保留旧密文，不要生成新密钥覆盖；账户密码重置、管理员或服务端都不能找回主密钥。普通字段仍可查看。</Notice> : null}</div> : null}
          {step === 2 ? <div className="stack"><p>在可信客户端导入原主密钥后，实际解密一条已有敏感凭据进行验证。仅输入密钥或完成本指引，不代表解密或同步成功。</p><p>Web 可在 SSH 配置中按需解密；若失败，请重新确认原密钥，不覆盖既有密文。</p><a className="button button--primary" href="#/profiles">打开 SSH 配置进行验证</a><Button onClick={() => setGuide(false)}>返回服务器状态</Button></div> : null}
        </Card>
      </section>
      <aside className="stack"><h2>恢复前，请记住</h2><p>服务器不保存你的主密钥。敏感凭据与普通连接信息的保护方式不同。</p><Notice tone="warning">找回账户 ≠ 恢复密钥</Notice><p className="secondary">本地数据始终可独立使用。未配置远程同步不影响本地终端。</p></aside>
    </div> : <ServerSnapshot />}
    <Card title="发现冲突？到发生冲突的客户端处理">
      <div className="stack"><p>此 Web 控制台不持有另一设备的本地候选版本，不能代替客户端判断冲突或自动合并。</p><p>在发生冲突的客户端比较普通字段与版本，再选择保留本地或远程。敏感差异需要原主密钥；提交前确认影响，版本变化时重新比较。</p><Notice>未解决时保留双方候选，不自动覆盖。受保护快照恢复不属于当前 Web 能力。</Notice></div>
    </Card>
  </div>
}
