'use client'
import { useAtlasStore, AtlasState } from '@/store/useAtlasStore'
import type { DemoCaseId } from '@/demo/DemoRunner'

interface Props {
  onTrigger: (id: DemoCaseId) => void
}

export default function DemoControlPanel({ onTrigger }: Props) {
  const demoCase = useAtlasStore((s: AtlasState) => s.demoCase)
  const demoReceipts = useAtlasStore((s: AtlasState) => s.demoReceipts)
  const lastReceipt = demoReceipts[0]

  const btnBase = 'w-full rounded-lg px-2 py-1.5 text-[10px] font-mono uppercase tracking-widest border transition-all'
  const idleActive = demoCase === 'idle'
  const attackActive = demoCase === 'attack'

  return (
    <div className="mt-3 rounded-2xl border border-amber-500/15 bg-amber-500/[0.04] p-2.5">
      <div className="flex items-center justify-between mb-2">
        <h3 className="text-[9px] font-bold uppercase tracking-[0.25em] text-amber-400/70">Demo Runner · LIT_WIRE_V1</h3>
        <span className="text-[8px] font-mono text-gray-500">hotkeys: 1 / 2</span>
      </div>
      <div className="grid grid-cols-2 gap-1.5 mb-2">
        <button
          onClick={() => onTrigger('idle')}
          className={`${btnBase} ${
            idleActive
              ? 'border-emerald-500/40 bg-emerald-500/12 text-emerald-300 shadow-[0_0_24px_rgba(16,185,129,0.12)]'
              : 'border-white/5 bg-black/20 text-gray-500 hover:text-emerald-300/80 hover:border-emerald-500/20'
          }`}
          title="[1] IDLE STATE — calm breathing telemetry, DRIFT < 0.35"
        >
          [1] Idle
        </button>
        <button
          onClick={() => onTrigger('attack')}
          className={`${btnBase} ${
            attackActive
              ? 'border-red-500/50 bg-red-500/12 text-red-300 shadow-[0_0_24px_rgba(239,68,68,0.18)] animate-pulse'
              : 'border-white/5 bg-black/20 text-gray-500 hover:text-red-300/80 hover:border-red-500/20'
          }`}
          title="[2] DPI ATTACK & SURGERY — DRIFT→243.80, NEGATIVE CURVATURE → rheknel LOCAL_COMMITTED receipt"
        >
          [2] DPI Attack
        </button>
      </div>
      <div className="grid grid-cols-2 gap-1 text-[8px] font-mono text-gray-500 mb-1.5">
        <div>Case: <span className={idleActive ? 'text-emerald-400' : attackActive ? 'text-red-400' : 'text-gray-600'}>{demoCase ?? '—'}</span></div>
        <div>Receipts: <span className="text-cyan-400/80">{demoReceipts.length}</span></div>
      </div>
      {lastReceipt && (
        <div className="rounded-lg border border-emerald-500/15 bg-black/30 p-2 text-[8px] font-mono leading-relaxed">
          <div className="text-emerald-400/80 uppercase tracking-[0.2em] mb-1 font-bold">
            ⬢ {lastReceipt.status} · {lastReceipt.item_bytes_len}B
          </div>
          <div className="text-gray-500">op_id <span className="text-cyan-300/70">{lastReceipt.operation_id.slice(0, 16)}…</span></div>
          <div className="text-gray-500">digest <span className="text-cyan-300/70">{lastReceipt.receipt_digest.slice(0, 16)}…</span></div>
          <div className="text-gray-500">head <span className="text-emerald-300/70">{lastReceipt.result_head.slice(0, 10)}…</span> ← {lastReceipt.expected_head.slice(0, 10)}…</div>
          <div className="text-gray-500">replica <span className="text-amber-300/70">{lastReceipt.replica_id}</span></div>
        </div>
      )}
    </div>
  )
}
