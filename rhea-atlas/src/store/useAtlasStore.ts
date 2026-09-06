import create from 'zustand';
import type { DemoCaseId, PublishReceipt } from '@/demo/DemoRunner';

export type ViewId = 'atlas-prime' | 'atlas-mesh' | 'theia-drift' | 'system-pw';

export interface Island {
  id: string;
  name: string;
  position: [number, number, number];
  complexity: number; // D-Metric
  color: string;
}

export interface SessionEntry {
  id: string;
  query: string;
  result: string;
  mode: 'tribunal' | 'sceptic' | 'ice';
  ontology: string;
  timestamp: number; // ms epoch
}

export interface DensityVector {
  origin: [number, number, number];
  direction: [number, number, number];
  magnitude: number;
}

export interface ContextDensity {
  id: string;
  label: string;
  ontology: string;
  density: number; // 0..1
  consistency: number; // 0..1
  vectorField: DensityVector[];
  color: string;
  position: [number, number, number];
  sampleCount: number;
}

export interface AletheiaStats {
  proofCount: number;
  hypothesisCount: number;
  totalArtifacts: number;
  avgAgreement: number;
  lastCapture: string | null;
  ontologyCount: number;
  uniqueQueries: number;
}

export interface DemoWarning {
  text: string;
  tone: 'danger' | 'ok';
}

export interface SphereOverrides {
  glitchMultiplier: number;
  colorOverride?: string;
  severBeam: boolean;
}

export interface AtlasState {
  islands: Island[];
  consensusScore: number;
  dMetric: number;
  activeIslandId: string | null;
  providerCount: number;
  redisStatus: 'up' | 'down' | 'unknown';
  apiHealthy: boolean;
  sessionHistory: SessionEntry[];
  activeSessionId: string | null;
  contextDensities: ContextDensity[];
  showOceanusFlow: boolean;
  activeView: ViewId;
  aletheiaStats: AletheiaStats;
  demoCase: DemoCaseId | null;
  demoWarning: DemoWarning | null;
  demoReceipts: PublishReceipt[];
  sphereOverrides: SphereOverrides;
  setIslands: (islands: Island[]) => void;
  updateIsland: (id: string, delta: Partial<Island>) => void;
  setDMetric: (d: number) => void;
  setActiveIsland: (id: string | null) => void;
  setProviderCount: (n: number) => void;
  setRedisStatus: (s: 'up' | 'down' | 'unknown') => void;
  setApiHealthy: (v: boolean) => void;
  addSessionEntry: (entry: SessionEntry) => void;
  setActiveSession: (id: string | null) => void;
  setContextDensities: (densities: ContextDensity[]) => void;
  toggleOceanusFlow: () => void;
  setActiveView: (v: ViewId) => void;
  setAletheiaStats: (stats: AletheiaStats) => void;
  setDemoCase: (c: DemoCaseId | null) => void;
  setDemoWarning: (w: DemoWarning | null) => void;
  addDemoReceipt: (r: PublishReceipt) => void;
  setSphereOverrides: (o: Partial<SphereOverrides>) => void;
}

export const useAtlasStore = create<AtlasState>((set) => ({
  islands: [
    { id: '1', name: 'Biology', position: [-3, 0, 0], complexity: 1.2, color: '#00ff00' },
    { id: '2', name: 'Mathematics', position: [3, 0, 0], complexity: 0.8, color: '#00ffff' },
  ],
  consensusScore: 94,
  dMetric: 0.22,
  activeIslandId: null,
  providerCount: 0,
  redisStatus: 'unknown',
  apiHealthy: false,
  sessionHistory: [],
  activeSessionId: null,
  contextDensities: [],
  showOceanusFlow: true,
  activeView: 'atlas-prime',
  aletheiaStats: { proofCount: 0, hypothesisCount: 0, totalArtifacts: 0, avgAgreement: 0, lastCapture: null, ontologyCount: 0, uniqueQueries: 0 },
  demoCase: null,
  demoWarning: null,
  demoReceipts: [],
  sphereOverrides: { glitchMultiplier: 1, severBeam: false },
  setIslands: (islands) => set({ islands }),
  updateIsland: (id, delta) => set((state) => ({
    islands: state.islands.map((is) => is.id === id ? { ...is, ...delta } : is)
  })),
  setDMetric: (d) => set({ dMetric: d }),
  setActiveIsland: (id) => set({ activeIslandId: id }),
  setProviderCount: (n) => set({ providerCount: n }),
  setRedisStatus: (s) => set({ redisStatus: s }),
  setApiHealthy: (v) => set({ apiHealthy: v }),
  addSessionEntry: (entry) => set((state) => ({
    sessionHistory: [entry, ...state.sessionHistory].slice(0, 50),
    activeSessionId: entry.id,
  })),
  setActiveSession: (id) => set({ activeSessionId: id }),
  setContextDensities: (densities) => set({ contextDensities: densities }),
  toggleOceanusFlow: () => set((state) => ({ showOceanusFlow: !state.showOceanusFlow })),
  setActiveView: (v) => set({ activeView: v }),
  setAletheiaStats: (stats) => set({ aletheiaStats: stats }),
  setDemoCase: (c) => set({ demoCase: c }),
  setDemoWarning: (w) => set({ demoWarning: w }),
  addDemoReceipt: (r) => set((state) => ({ demoReceipts: [r, ...state.demoReceipts].slice(0, 10) })),
  setSphereOverrides: (o) => set((state) => ({ sphereOverrides: { ...state.sphereOverrides, ...o } })),
}));
