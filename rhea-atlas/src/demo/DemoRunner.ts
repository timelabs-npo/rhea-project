'use client'

export type DemoCaseId = 'idle' | 'attack'

export interface PublishReceipt {
  status: 'LocalCommitted' | 'RemoteApplied' | 'Conflict'
  operation_id: string
  receipt_digest: string
  expected_head: string
  result_head: string
  replica_id: string
  ts_ms: number
  item_bytes_len: number
}

export interface DemoTelemetry {
  frame: {
    magic: number
    kind: number
    metadata_len: number
    payload_len: number
    hex: string
  }
  drift: number
  curvature: number
  engine_state: 'Breathe' | 'DpiShaping' | 'Committing' | 'Recovering'
  receipt?: PublishReceipt
}

type SetDMetric = (d: number) => void
type SetWarning = (w: { text: string; tone: 'danger' | 'ok' } | null) => void
type AddReceipt = (r: PublishReceipt) => void
type SetSphereOverrides = (o: { glitchMultiplier: number; colorOverride?: string; severBeam: boolean }) => void
type AddSession = (e: { id: string; query: string; result: string; mode: 'tribunal' | 'sceptic' | 'ice'; ontology: string; timestamp: number }) => void
type SetCase = (c: DemoCaseId | null) => void

function litWireFrame(kind: number, metadata_len: number, payload_len: number): DemoTelemetry['frame'] {
  const buf = new Uint8Array(13)
  buf[0] = 0x4c
  buf[1] = 0x49
  buf[2] = 0x54
  buf[3] = 0x31
  buf[4] = kind & 0xff
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength)
  dv.setUint32(5, metadata_len, false)
  dv.setUint32(9, payload_len, false)
  const hex = Array.from(buf).map((b) => b.toString(16).padStart(2, '0')).join(' ')
  return { magic: 0x4c495431, kind, metadata_len, payload_len, hex }
}

function randomHex(n: number): string {
  const bytes = new Uint8Array(n)
  crypto.getRandomValues(bytes)
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('')
}

function mkLocalCommittedReceipt(): PublishReceipt {
  return {
    status: 'LocalCommitted',
    operation_id: randomHex(16),
    receipt_digest: randomHex(32),
    expected_head: randomHex(32),
    result_head: randomHex(32),
    replica_id: 'rheknel-v1-lit-' + randomHex(6),
    ts_ms: Date.now(),
    item_bytes_len: 13 + 4 + 128,
  }
}

export class DemoRunner {
  private setDMetric: SetDMetric
  private setWarning: SetWarning
  private addReceipt: AddReceipt
  private setSphereOverrides: SetSphereOverrides
  private addSession: AddSession
  private setCase: SetCase
  private intervalId: number | null = null
  private timeouts: number[] = []
  private active: DemoCaseId | null = null

  constructor(opts: {
    setDMetric: SetDMetric
    setWarning: SetWarning
    addReceipt: AddReceipt
    setSphereOverrides: SetSphereOverrides
    addSession: AddSession
    setCase: SetCase
  }) {
    this.setDMetric = opts.setDMetric
    this.setWarning = opts.setWarning
    this.addReceipt = opts.addReceipt
    this.setSphereOverrides = opts.setSphereOverrides
    this.addSession = opts.addSession
    this.setCase = opts.setCase
  }

  private clearAll() {
    if (this.intervalId !== null) {
      window.clearInterval(this.intervalId)
      this.intervalId = null
    }
    for (const t of this.timeouts) window.clearTimeout(t)
    this.timeouts = []
  }

  stop() {
    this.clearAll()
    this.active = null
    this.setCase(null)
  }

  startCase(id: DemoCaseId) {
    this.clearAll()
    this.active = id
    this.setCase(id)
    if (id === 'idle') this.runIdle()
    else this.runAttack()
  }

  private runIdle() {
    this.setWarning(null)
    this.setSphereOverrides({ glitchMultiplier: 1, severBeam: false })
    const tick = () => {
      const drift = 0.12 + Math.random() * 0.22
      this.setDMetric(Number(drift.toFixed(2)))
    }
    tick()
    this.intervalId = window.setInterval(tick, 800)
  }

  private runAttack() {
    // t+0s: DRIFT spike + NEGATIVE CURVATURE warning + sphere glitch red
    this.setDMetric(243.8)
    this.setWarning({
      text: 'NEGATIVE CURVATURE DETECTED — Ricci Flow negative-eigenvalue DPI shaping event active',
      tone: 'danger',
    })
    this.setSphereOverrides({
      glitchMultiplier: 8.5,
      colorOverride: '#ff1744',
      severBeam: true,
    })
    this.addSession({
      id: `dpi-${Date.now()}`,
      query: 'LIT_WIRE_V1 DPI_SHAPING_DETECT',
      result: JSON.stringify(litWireFrame(3, 16, 64)),
      mode: 'tribunal',
      ontology: 'ricci-flow',
      timestamp: Date.now(),
    })

    // t+2.5s: LOCAL_COMMITTED receipt + color amber
    this.schedule(2500, () => {
      const receipt = mkLocalCommittedReceipt()
      this.addReceipt(receipt)
      this.setSphereOverrides({
        glitchMultiplier: 4,
        colorOverride: '#ffa726',
        severBeam: true,
      })
      this.addSession({
        id: `rcpt-${receipt.operation_id}`,
        query: 'rheknel::publish',
        result: JSON.stringify(receipt),
        mode: 'ice',
        ontology: 'state/receipt',
        timestamp: Date.now(),
      })
    })

    // t+4.5s: clear warning, drift decay begins
    this.schedule(4500, () => {
      this.setWarning(null)
      this.setSphereOverrides({
        glitchMultiplier: 1.8,
        colorOverride: '#26c6da',
        severBeam: false,
      })
    })

    // t+4.5s → t+9.5s: drift decays from 243.8 → ~0.22
    const start = performance.now() + 4500
    const dur = 5000
    const startDrift = 243.8
    const endDrift = 0.22
    const decayIv = window.setInterval(() => {
      const t = Math.min(1, (performance.now() - start) / dur)
      const eased = 1 - Math.pow(1 - t, 3)
      const d = startDrift + (endDrift - startDrift) * eased
      this.setDMetric(Number(d.toFixed(2)))
      if (t >= 1) {
        window.clearInterval(decayIv)
        this.setSphereOverrides({ glitchMultiplier: 1, severBeam: false })
      }
    }, 60)
    // hack: register decay interval so stop() clears it; we stash in intervalId-ish via timeouts[]
    ;(this.timeouts as unknown as number[]).push(decayIv)

    // t+10.5s: back to idle-style telemetry
    this.schedule(10500, () => {
      this.startCase('idle')
    })
  }

  private schedule(ms: number, fn: () => void) {
    const id = window.setTimeout(fn, ms)
    this.timeouts.push(id)
  }

  isActive(): DemoCaseId | null {
    return this.active
  }
}
