'use client'
import { motion, AnimatePresence } from 'framer-motion'
import type { DemoWarning } from '@/store/useAtlasStore'

export default function WarningBanner({ warning }: { warning: DemoWarning | null }) {
  return (
    <AnimatePresence>
      {warning && (
        <motion.div
          key="demo-warning"
          initial={{ y: -120, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          exit={{ y: -120, opacity: 0 }}
          transition={{ duration: 0.35, ease: 'easeOut' }}
          className="fixed top-[72px] left-1/2 -translate-x-1/2 z-[140] pointer-events-none"
        >
          <motion.div
            animate={warning.tone === 'danger' ? {
              boxShadow: [
                '0 0 0 0 rgba(255,23,68,0.0)',
                '0 0 40px 6px rgba(255,23,68,0.45)',
                '0 0 0 0 rgba(255,23,68,0.0)',
              ],
            } : {}}
            transition={warning.tone === 'danger' ? { duration: 0.6, repeat: Infinity, repeatType: 'reverse' } : {}}
            className="rounded-2xl border-2 backdrop-blur-xl px-6 py-3"
            style={{
              borderColor: warning.tone === 'danger' ? '#ff1744' : '#00e676',
              background: warning.tone === 'danger'
                ? 'linear-gradient(90deg, rgba(255,23,68,0.22), rgba(213,0,0,0.18), rgba(255,23,68,0.22))'
                : 'linear-gradient(90deg, rgba(0,230,118,0.18), rgba(0,200,83,0.12), rgba(0,230,118,0.18))',
            }}
          >
            <div className="flex items-center gap-3">
              <span
                className="text-xl"
                style={{ filter: warning.tone === 'danger' ? 'drop-shadow(0 0 8px #ff1744)' : 'drop-shadow(0 0 8px #00e676)' }}
              >
                {warning.tone === 'danger' ? '⚠' : '✓'}
              </span>
              <div className="font-mono text-[11px] uppercase tracking-[0.22em] font-bold"
                style={{ color: warning.tone === 'danger' ? '#ff5252' : '#69f0ae' }}>
                {warning.text}
              </div>
            </div>
            <div
              aria-hidden
              className="mt-1 h-[1px] rounded-full overflow-hidden"
              style={{ background: 'rgba(255,255,255,0.06)' }}
            >
              <motion.div
                initial={{ x: '-100%' }}
                animate={{ x: '100%' }}
                transition={{ duration: 1.2, repeat: Infinity, ease: 'linear' }}
                className="h-full w-1/3"
                style={{
                  background: warning.tone === 'danger'
                    ? 'linear-gradient(90deg, transparent, #ff1744, transparent)'
                    : 'linear-gradient(90deg, transparent, #00e676, transparent)',
                }}
              />
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
