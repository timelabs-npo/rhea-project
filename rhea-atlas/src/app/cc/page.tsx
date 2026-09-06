'use client'

import { useEffect, useState, useCallback, useRef } from 'react'
// CC talks directly to tribunal_api.py on port 8400, not Themis on 8000
const CC_API = process.env.NEXT_PUBLIC_CC_API ?? 'http://localhost:8400'
const CC_API_KEY = process.env.NEXT_PUBLIC_CC_API_KEY ?? 'dev-bypass'

// ─── Tauri Native Bindings (no-op in browser) ───────────────────────
const isTauri = typeof window !== 'undefined' && '__TAURI__' in window

async function sendNotification(title: string, body: string) {
  if (!isTauri) return
  try {
    const pluginPkg = ['@tauri-apps/', 'plugin-notification'].join('')
    const { isPermissionGranted, requestPermission, sendNotification: notify } =
      await import(/* @vite-ignore */ pluginPkg)
    let granted = await isPermissionGranted()
    if (!granted) granted = (await requestPermission()) === 'granted'
    if (granted) notify({ title, body })
  } catch { /* browser fallback — silent */ }
}

async function listenGlobalShortcut(handler: (key: string) => void) {
  if (!isTauri) return
  try {
    const evPkg = ['@tauri-apps/api/', 'event'].join('')
    const mod = await import(/* @vite-ignore */ evPkg)
    const listen = mod.listen as (evt: string, cb: (e: { payload: string }) => void) => Promise<() => void>
    await listen('global-shortcut', (e) => handler(e.payload))
  } catch { /* browser fallback — silent */ }
}

// ─── Types ────────────────────────────────────────────────────────────

type AgentStatus = {
  name: string
  alive: boolean
  pace: string
  mode: string
  T_day: number
  dollar_day: number
  floor_gap: number
  office_status: string
  pending_msgs: number
  tasks_open: number
  tasks_claimed: number
  last_activity: string
  last_feed: string
}

type RadioEvent = {
  id: number
  type: string
  sender: string
  receiver: string
  text: string
  ts: string
}

type HistoryEntry = {
  id: number
  session_id: string
  step: number
  type: string
  prompt: string
  response: string
  agreement_score: number
  confidence: number
  created_at: string
}

type OfficeMsg = {
  id: string
  sender: string
  receiver: string
  text: string
  ts: string
  response: string
}

type NDIStatus = {
  available: boolean
  version?: string
  cpu_supported?: boolean
  library_path?: string
  sources_on_network?: number
  sources?: { name: string; url: string }[]
  error?: string
}

// ─── API Helpers ──────────────────────────────────────────────────────

const headers = { 'X-API-Key': CC_API_KEY, 'Content-Type': 'application/json' }
const api = (path: string) => fetch(`${CC_API}${path}`, { headers }).then(r => r.json())

// ─── Pace Colors ──────────────────────────────────────────────────────

const PACE_COLORS: Record<string, string> = {
  green: 'bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.6)]',
  yellow: 'bg-amber-400 shadow-[0_0_8px_rgba(251,191,36,0.6)]',
  red: 'bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.6)]',
  normal: 'bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.6)]',
  compact: 'bg-amber-400 shadow-[0_0_8px_rgba(251,191,36,0.6)]',
  recovery: 'bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.6)]',
}

// ─── Sub-panels ───────────────────────────────────────────────────────

function AgentsSidebar({ agents }: { agents: AgentStatus[] }) {
  return (
    <div className="space-y-2">
      <h2 className="text-xs font-bold uppercase tracking-widest text-cyan-400/80 mb-3">Agents</h2>
      {agents.map(a => (
        <div key={a.name} className="flex items-center gap-2 p-2 rounded-lg bg-white/[0.03] hover:bg-white/[0.06] transition-colors">
          <div className={`w-2 h-2 rounded-full shrink-0 ${a.alive ? (PACE_COLORS[a.pace] || PACE_COLORS.green) : 'bg-slate-600'}`} />
          <span className="font-mono text-sm text-white/90 flex-1">{a.name}</span>
          {a.pending_msgs > 0 && (
            <span className="text-[10px] bg-amber-500/20 text-amber-300 px-1.5 rounded-full">{a.pending_msgs}</span>
          )}
          <span className="text-[10px] text-white/30">{a.office_status}</span>
        </div>
      ))}
    </div>
  )
}

function GovernorStats({ agents }: { agents: AgentStatus[] }) {
  const totalTokens = agents.reduce((s, a) => s + (a.T_day || 0), 0)
  const totalCost = agents.reduce((s, a) => s + (a.dollar_day || 0), 0)
  const alive = agents.filter(a => a.alive).length
  return (
    <div className="space-y-2 mt-4">
      <h2 className="text-xs font-bold uppercase tracking-widest text-cyan-400/80 mb-3">Governor</h2>
      <div className="grid grid-cols-2 gap-2 text-xs">
        <div className="bg-white/[0.03] rounded-lg p-2">
          <div className="text-white/40">T_day</div>
          <div className="font-mono text-white/90">{totalTokens.toLocaleString()}</div>
        </div>
        <div className="bg-white/[0.03] rounded-lg p-2">
          <div className="text-white/40">$_day</div>
          <div className="font-mono text-white/90">${totalCost.toFixed(4)}</div>
        </div>
        <div className="bg-white/[0.03] rounded-lg p-2">
          <div className="text-white/40">Alive</div>
          <div className="font-mono text-white/90">{alive}/{agents.length}</div>
        </div>
        <div className="bg-white/[0.03] rounded-lg p-2">
          <div className="text-white/40">Tasks</div>
          <div className="font-mono text-white/90">{agents.reduce((s, a) => s + (a.tasks_open || 0), 0)}</div>
        </div>
      </div>
    </div>
  )
}

function RadioFeed({ events }: { events: RadioEvent[] }) {
  const feedRef = useRef<HTMLDivElement>(null)
  useEffect(() => { feedRef.current?.scrollTo(0, 0) }, [events.length])

  return (
    <div className="flex flex-col h-full">
      <h2 className="text-xs font-bold uppercase tracking-widest text-cyan-400/80 mb-3 shrink-0">
        Radio Feed <span className="text-red-400 animate-pulse ml-1">ON AIR</span>
      </h2>
      <div ref={feedRef} className="flex-1 overflow-y-auto space-y-1 font-mono text-xs pr-1">
        {events.map((e, i) => (
          <div key={e.id ?? i} className="flex gap-2 py-1 border-b border-white/[0.04] hover:bg-white/[0.03]">
            <span className="text-white/25 shrink-0 w-12">{e.ts?.slice(11, 16) || '??:??'}</span>
            <span className="text-cyan-300/70 shrink-0 w-16 truncate">[{e.sender}]</span>
            <span className="text-white/70 flex-1 break-words">{e.text}</span>
          </div>
        ))}
        {events.length === 0 && <div className="text-white/20 italic">No radio events yet</div>}
      </div>
    </div>
  )
}

function TribunalPane() {
  const [prompt, setPrompt] = useState('')
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<{ consensus: string; agreement: number; confidence: number; models: number } | null>(null)

  const submit = async () => {
    if (!prompt.trim() || loading) return
    setLoading(true)
    try {
      const res = await fetch(`${CC_API}/tribunal`, {
        method: 'POST', headers,
        body: JSON.stringify({ prompt, k: 3, mode: 'chairman' }),
      })
      const data = await res.json()
      setResult({
        consensus: data.consensus || '',
        agreement: data.agreement_score || 0,
        confidence: data.confidence || 0,
        models: data.models_responded || 0,
      })
    } catch { setResult({ consensus: 'Error — API unreachable', agreement: 0, confidence: 0, models: 0 }) }
    finally { setLoading(false) }
  }

  return (
    <div className="space-y-3">
      <h2 className="text-xs font-bold uppercase tracking-widest text-cyan-400/80">Tribunal</h2>
      <div className="flex gap-2">
        <input
          value={prompt} onChange={e => setPrompt(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && submit()}
          placeholder="Enter claim to evaluate..."
          className="flex-1 bg-white/[0.05] border border-white/10 rounded-lg px-3 py-2 text-sm text-white/90 placeholder-white/20 focus:outline-none focus:border-cyan-500/50"
        />
        <button onClick={submit} disabled={loading}
          className="px-4 py-2 bg-cyan-600/30 hover:bg-cyan-600/50 text-cyan-300 rounded-lg text-sm font-medium transition-colors disabled:opacity-30">
          {loading ? '...' : 'Send'}
        </button>
      </div>
      {result && (
        <div className="bg-white/[0.03] rounded-lg p-3 space-y-2">
          <div className="flex gap-4 text-xs">
            <span className="text-white/40">Agreement: <span className="text-white/80 font-mono">{(result.agreement * 100).toFixed(0)}%</span></span>
            <span className="text-white/40">Confidence: <span className="text-white/80 font-mono">{(result.confidence * 100).toFixed(0)}%</span></span>
            <span className="text-white/40">Models: <span className="text-white/80 font-mono">{result.models}</span></span>
          </div>
          <p className="text-sm text-white/70 leading-relaxed">{result.consensus}</p>
        </div>
      )}
    </div>
  )
}

function HistoryPanel({ history }: { history: HistoryEntry[] }) {
  // Inline expand: click to toggle full response. Chosen over modal/slide-out
  // because it keeps context visible and doesn't interrupt the monitoring flow.
  const [expanded, setExpanded] = useState<number | null>(null)

  return (
    <div className="space-y-2">
      <h2 className="text-xs font-bold uppercase tracking-widest text-cyan-400/80 mb-3">History</h2>
      <div className="space-y-1 max-h-64 overflow-y-auto">
        {history.map(h => (
          <div key={h.id}
            onClick={() => setExpanded(expanded === h.id ? null : h.id)}
            className="cursor-pointer bg-white/[0.03] hover:bg-white/[0.06] rounded-lg p-2 transition-colors">
            <div className="flex items-center gap-2 text-xs">
              <span className="text-white/25 font-mono w-14">{h.created_at?.slice(11, 16)}</span>
              <span className={`px-1.5 rounded text-[10px] ${h.type === 'tribunal' ? 'bg-cyan-500/20 text-cyan-300' : h.type === 'tribunal_sceptic' ? 'bg-red-500/20 text-red-300' : 'bg-purple-500/20 text-purple-300'}`}>
                {h.type}
              </span>
              <span className="text-white/60 truncate flex-1">{h.prompt}</span>
              <span className="text-white/30 font-mono">{(h.confidence * 100).toFixed(0)}%</span>
            </div>
            {expanded === h.id && (
              <div className="mt-2 pl-16 text-xs text-white/50 border-t border-white/5 pt-2">
                <p>Agreement: {(h.agreement_score * 100).toFixed(1)}% | Confidence: {(h.confidence * 100).toFixed(1)}%</p>
                <p className="mt-1 text-white/40">{typeof h.response === 'string' ? h.response.slice(0, 300) : JSON.stringify(h.response).slice(0, 300)}</p>
              </div>
            )}
          </div>
        ))}
        {history.length === 0 && <div className="text-white/20 italic text-xs">No history yet — submit a claim via Tribunal</div>}
      </div>
    </div>
  )
}

function OfficePanel({ messages }: { messages: OfficeMsg[] }) {
  return (
    <div className="space-y-2">
      <h2 className="text-xs font-bold uppercase tracking-widest text-cyan-400/80 mb-3">Office</h2>
      <div className="space-y-1 max-h-48 overflow-y-auto font-mono text-xs">
        {messages.map((m, i) => (
          <div key={m.id ?? i} className="flex gap-2 py-1 border-b border-white/[0.04]">
            <span className="text-white/25 w-12 shrink-0">{m.ts?.slice(11, 16)}</span>
            <span className="text-emerald-300/70 w-12 shrink-0">{m.sender}</span>
            <span className="text-white/30">→</span>
            <span className="text-amber-300/70 w-12 shrink-0">{m.receiver}</span>
            <span className="text-white/50 truncate flex-1">{m.text}</span>
          </div>
        ))}
        {messages.length === 0 && <div className="text-white/20 italic">No office messages</div>}
      </div>
    </div>
  )
}

function NDIPanel({ ndi }: { ndi: NDIStatus | null }) {
  const [broadcasting, setBroadcasting] = useState(false)

  const sendTest = async () => {
    setBroadcasting(true)
    try {
      await fetch(`${CC_API}/cc/ndi/send-test`, {
        method: 'POST', headers,
        body: JSON.stringify({ name: 'Rhea Command Centre', duration: 10 }),
      })
    } catch { /* silent */ }
    setTimeout(() => setBroadcasting(false), 10000)
  }

  if (!ndi) return null

  return (
    <div className="space-y-2">
      <h2 className="text-xs font-bold uppercase tracking-widest text-cyan-400/80 mb-3">
        NDI
        <span className={`ml-2 text-[10px] ${ndi.available ? 'text-emerald-400' : 'text-red-400'}`}>
          {ndi.available ? `v${ndi.version?.split(' ').pop() || '?'}` : 'OFFLINE'}
        </span>
      </h2>
      {ndi.available ? (
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-xs">
            <span className="text-white/40">Sources:</span>
            <span className="font-mono text-white/80">{ndi.sources_on_network ?? 0}</span>
            <button onClick={sendTest} disabled={broadcasting}
              className="ml-auto px-2 py-1 bg-purple-600/30 hover:bg-purple-600/50 text-purple-300 rounded text-[10px] transition-colors disabled:opacity-30">
              {broadcasting ? 'Broadcasting...' : 'Test Pattern'}
            </button>
          </div>
          {(ndi.sources || []).length > 0 && (
            <div className="space-y-1">
              {ndi.sources!.map((s, i) => (
                <div key={i} className="flex items-center gap-2 p-1.5 rounded bg-white/[0.03] text-xs">
                  <div className="w-1.5 h-1.5 rounded-full bg-purple-400 shadow-[0_0_6px_rgba(168,85,247,0.5)]" />
                  <span className="font-mono text-white/80">{s.name}</span>
                  <span className="text-white/20 text-[10px] ml-auto truncate max-w-32">{s.url}</span>
                </div>
              ))}
            </div>
          )}
          {(ndi.sources || []).length === 0 && (
            <div className="text-white/20 italic text-[11px]">No NDI sources on network — hit Test Pattern to broadcast</div>
          )}
        </div>
      ) : (
        <div className="text-white/30 text-xs">{ndi.error || 'NDI runtime not installed'}</div>
      )}
    </div>
  )
}

// ─── Main Layout ──────────────────────────────────────────────────────

export default function CommandCentre() {
  const [agents, setAgents] = useState<AgentStatus[]>([])
  const [radio, setRadio] = useState<RadioEvent[]>([])
  const [history, setHistory] = useState<HistoryEntry[]>([])
  const [office, setOffice] = useState<OfficeMsg[]>([])
  const [ndi, setNdi] = useState<NDIStatus | null>(null)
  const [connected, setConnected] = useState(false)
  const prevAlive = useRef<Record<string, boolean>>({})

  const refresh = useCallback(async () => {
    try {
      const [agentRes, radioRes, historyRes, officeRes, ndiRes] = await Promise.allSettled([
        api('/agents/status'),
        api('/cc/radio?limit=50'),
        api('/cc/history?limit=30'),
        api('/cc/office?limit=20'),
        api('/cc/ndi'),
      ])

      if (agentRes.status === 'fulfilled' && agentRes.value?.agents) {
        const newAgents = Object.values(agentRes.value.agents) as AgentStatus[]
        // Notify on agent status changes (skip first load)
        if (Object.keys(prevAlive.current).length > 0) {
          for (const a of newAgents) {
            const was = prevAlive.current[a.name]
            if (was !== undefined && was !== a.alive) {
              sendNotification(
                `Agent ${a.name}`,
                a.alive ? `${a.name} is back online` : `${a.name} went offline`
              )
            }
          }
        }
        prevAlive.current = Object.fromEntries(newAgents.map(a => [a.name, a.alive]))
        setAgents(newAgents)
      }
      if (radioRes.status === 'fulfilled') setRadio(radioRes.value?.radio || [])
      if (historyRes.status === 'fulfilled') setHistory(historyRes.value?.history || [])
      if (officeRes.status === 'fulfilled') setOffice(officeRes.value?.messages || [])
      if (ndiRes.status === 'fulfilled') setNdi(ndiRes.value as NDIStatus)
      setConnected(true)
    } catch {
      setConnected(false)
    }
  }, [])

  useEffect(() => {
    refresh()
    const id = setInterval(refresh, 5000)
    // Listen for global shortcuts from Tauri (Rust emits 'global-shortcut' event)
    listenGlobalShortcut((key) => {
      if (key.includes('KeyT')) {
        // Focus tribunal input
        document.querySelector<HTMLInputElement>('[placeholder*="claim"]')?.focus()
      }
    })
    return () => clearInterval(id)
  }, [refresh])

  return (
    <div className="fixed inset-0 z-[200] bg-[#0a0a0f] text-white overflow-hidden flex flex-col">
      {/* Header */}
      <div className="border-b border-white/[0.06] px-4 py-2 flex items-center gap-3">
        <div className={`w-2 h-2 rounded-full ${connected ? 'bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.5)]' : 'bg-red-500'}`} />
        <h1 className="text-sm font-bold tracking-wider text-white/80">RHEA COMMAND CENTRE</h1>
        <span className="text-[10px] text-white/20 ml-auto font-mono">
          {agents.filter(a => a.alive).length}/{agents.length} agents
          {ndi?.available && <> | NDI {ndi.sources_on_network ?? 0} src</>}
          {' '}| 5s poll
        </span>
      </div>

      {/* 3-column layout */}
      <div className="flex flex-1 overflow-hidden">
        {/* Left sidebar: Agents + Governor + NDI */}
        <div className="w-56 shrink-0 border-r border-white/[0.06] p-3 overflow-y-auto space-y-4 h-full">
          <AgentsSidebar agents={agents} />
          <GovernorStats agents={agents} />
          <NDIPanel ndi={ndi} />
        </div>

        {/* Center: Radio Feed */}
        <div className="flex-1 border-r border-white/[0.06] p-3 min-w-0 h-full">
          <RadioFeed events={radio} />
        </div>

        {/* Right: Tribunal + History + Office */}
        <div className="w-96 shrink-0 p-3 overflow-y-auto space-y-4 h-full">
          <TribunalPane />
          <HistoryPanel history={history} />
          <OfficePanel messages={office} />
        </div>
      </div>
    </div>
  )
}
