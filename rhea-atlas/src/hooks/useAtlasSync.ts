'use client';

import { useEffect } from 'react';
import { useAtlasStore } from '@/store/useAtlasStore';
import { API_BASE, IS_API_CONFIGURED } from '@/lib/config';

export interface HealthState {
  providerCount: number;
  redisStatus: 'up' | 'down' | 'unknown';
  dMetric: number;
  auditRecords: number;
  apiHealthy: boolean;
}

// Exported so other components can read the last known health
let _lastHealth: HealthState = {
  providerCount: 0,
  redisStatus: 'unknown',
  dMetric: 0,
  auditRecords: 0,
  apiHealthy: false,
};

export function getLastHealth(): HealthState {
  return _lastHealth;
}

export function useAtlasSync() {
  const setters = useAtlasStore((s) => ({
    setDMetric: s.setDMetric,
    updateIsland: s.updateIsland,
    setProviderCount: s.setProviderCount,
    setRedisStatus: s.setRedisStatus,
    setApiHealthy: s.setApiHealthy,
    setAletheiaStats: s.setAletheiaStats,
  }));

  useEffect(() => {
    // Demo / offline mode: no backend configured — skip all network
    if (!IS_API_CONFIGURED) return;

    const { setDMetric, updateIsland, setProviderCount, setRedisStatus, setApiHealthy, setAletheiaStats } = setters;

    const fetchHealth = async () => {
      let rootData: Record<string, unknown> = {};
      let apiData: Record<string, unknown> = {};
      let atlasData: Record<string, unknown> = {};

      // Fetch root health endpoint
      try {
        const res = await fetch(`${API_BASE}/health`);
        if (res.ok) rootData = await res.json();
      } catch {
        // server may be offline — silent
      }

      // Fetch API health endpoint
      try {
        const res = await fetch(`${API_BASE}/api/health`);
        if (res.ok) apiData = await res.json();
      } catch {
        // server may be offline — silent
      }

      // Fetch Atlas projection state (shared UI bridge)
      try {
        const res = await fetch(`${API_BASE}/ui/atlas`);
        if (res.ok) atlasData = await res.json();
      } catch {
        // Redis STM may be unavailable — silent
      }

      const atlasMetrics =
        (atlasData.metrics as Record<string, unknown> | undefined)?.metrics as Record<string, unknown> | undefined;
      const atlasDMetric =
        (atlasMetrics?.d_metric as Record<string, unknown> | undefined)?.value;

      // Parse provider count from either endpoint
      const providerCount =
        (typeof rootData.provider_count === 'number' ? rootData.provider_count : 0) ||
        (typeof apiData.providers_available === 'number' ? apiData.providers_available : 0) ||
        (typeof apiData.providers === 'number' ? apiData.providers : 0) ||
        (Array.isArray(apiData.providers) ? (apiData.providers as unknown[]).length : 0);

      // Redis status
      const redisRaw =
        rootData.redis ??
        rootData.redis_stm ??
        apiData.redis ??
        rootData.redis_status ??
        apiData.redis_status;
      let redisStatus: HealthState['redisStatus'] = 'unknown';
      if (typeof redisRaw === 'string') {
        redisStatus = redisRaw.toLowerCase().includes('up') || redisRaw.toLowerCase() === 'ok'
          ? 'up'
          : 'down';
      } else if (typeof redisRaw === 'boolean') {
        redisStatus = redisRaw ? 'up' : 'down';
      }

      // D-metric: prefer explicit field, then audit_records derivation
      const auditRecords =
        typeof rootData.audit_records === 'number' ? rootData.audit_records :
        typeof apiData.audit_records === 'number' ? apiData.audit_records : 0;

      const rawDMetric =
        (typeof atlasDMetric === 'number' ? atlasDMetric : 0) ||
        (typeof rootData.d_metric === 'number' ? rootData.d_metric : 0) ||
        (typeof apiData.d_metric === 'number' ? apiData.d_metric : 0) ||
        (typeof rootData.drift === 'number' ? rootData.drift : 0) ||
        (typeof apiData.drift === 'number' ? apiData.drift : 0) ||
        (auditRecords > 0 ? parseFloat((auditRecords * 0.05 + 243.8).toFixed(2)) : 0);

      const apiHealthy =
        Object.keys(rootData).length > 0 ||
        Object.keys(apiData).length > 0 ||
        Object.keys(atlasData).length > 0;

      _lastHealth = {
        providerCount,
        redisStatus,
        dMetric: rawDMetric,
        auditRecords,
        apiHealthy,
      };

      // Push into store
      setApiHealthy(apiHealthy);
      setRedisStatus(redisStatus);
      if (providerCount > 0) setProviderCount(providerCount);
      if (rawDMetric > 0) setDMetric(rawDMetric);

      // Sync island complexity based on drift from audit records
      const drift = auditRecords * 0.05;
      updateIsland('1', { complexity: 1.2 + drift });
      updateIsland('2', { complexity: 0.8 + drift });
    };

    let es: EventSource | null = null;
    try {
      es = new EventSource(`${API_BASE}/ui/events`);
      es.onmessage = (ev) => {
        setApiHealthy(true);
        try {
          const msg = JSON.parse(ev.data);
          const drift =
            (msg?.metrics?.d_metric?.value as number | undefined) ??
            (msg?.d_metric as number | undefined);
          if (typeof drift === 'number' && Number.isFinite(drift) && drift > 0) setDMetric(drift);
          const redis =
            (msg?.redis_stm as string | undefined) ??
            (msg?.redis as string | undefined);
          if (typeof redis === 'string') {
            const norm = redis.toLowerCase();
            setRedisStatus(norm.includes('on') || norm.includes('up') || norm === 'ok' ? 'up' : 'down');
          }
        } catch {
          // non-JSON event payloads are expected in early relay versions
        }
      };
      es.onerror = () => { es?.close(); es = null; };
    } catch {
      // SSE unsupported/unavailable — polling remains active
    }

    // Aletheia stats polling (30s — less critical than health)
    const fetchAletheia = async () => {
      try {
        const res = await fetch(`${API_BASE}/aletheia/stats`);
        if (res.ok) {
          const s = await res.json();
          setAletheiaStats({
            proofCount: s.proof_count ?? 0,
            hypothesisCount: s.hypothesis_count ?? 0,
            totalArtifacts: s.total_artifacts ?? 0,
            avgAgreement: s.avg_agreement ?? 0,
            lastCapture: s.last_capture ?? null,
            ontologyCount: s.ontology_count ?? 0,
            uniqueQueries: s.unique_queries ?? 0,
          });
        }
      } catch { /* Aletheia unavailable — silent */ }
    };

    // Immediate first call, then every 5 s polling fallback
    fetchHealth();
    fetchAletheia();
    const interval = setInterval(fetchHealth, 5000);
    const aletheiaInterval = setInterval(fetchAletheia, 30000);
    return () => {
      clearInterval(interval);
      clearInterval(aletheiaInterval);
      es?.close();
    };
    // NOTE: Empty deps by design. Zustand setters are stable refs; we also skip
    // all re-binding after first mount to avoid infinite re-run loops from any
    // upstream selector re-stability issues.
  }, []);
}
