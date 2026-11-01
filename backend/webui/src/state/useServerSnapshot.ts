import { useCallback, useEffect, useRef, useState } from 'react'
import { ApiError } from '../api/client'
import type { Resource } from '../types'
import { useSession } from './SessionContext'

export const SYNC_DOCUMENTS = [
  { kind: 'profile', id: 'default', label: '连接配置', description: 'SSH 连接与敏感凭据' },
  { kind: 'config', id: 'preferences', label: '应用偏好', description: '客户端的应用设置' },
  { kind: 'config', id: 'local-terminal', label: '终端配置', description: '本地终端的配置' },
] as const

export type SnapshotRow = { label: string; description: string; resource?: Resource; error?: string; empty?: boolean }

export function useServerSnapshot() {
  const { client } = useSession()
  const [rows, setRows] = useState<SnapshotRow[]>([])
  const [loading, setLoading] = useState(true)
  const [sampledAt, setSampledAt] = useState<string | null>(null)
  const generation = useRef(0)
  const refresh = useCallback(async () => {
    if (!client) return
    const current = ++generation.current
    setLoading(true)
    const result = await Promise.all(SYNC_DOCUMENTS.map(async (doc): Promise<SnapshotRow> => {
      try {
        // Fetch own ordinary document but display metadata only. Never request sensitive envelopes.
        const resource = await client.getResource(doc.kind, doc.id)
        return { ...doc, resource }
      } catch (error) {
        if (error instanceof ApiError && error.status === 404) return { ...doc, empty: true }
        return { ...doc, error: error instanceof ApiError && error.status === 401
          ? '会话已失效，请重新登录。'
          : error instanceof ApiError && error.status === 403 ? '当前账户无权读取此文档。' : '无法获取服务器状态，请重试。' }
      }
    }))
    if (current !== generation.current) return
    setRows(result)
    setSampledAt(new Date().toLocaleString('zh-CN'))
    setLoading(false)
  }, [client])
  useEffect(() => { void refresh(); return () => { generation.current++ } }, [refresh])
  return { rows, loading, sampledAt, refresh }
}
