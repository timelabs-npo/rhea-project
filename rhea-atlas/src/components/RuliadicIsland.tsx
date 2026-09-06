'use client'
import { useMemo, useRef, useState } from 'react'
import { useFrame } from '@react-three/fiber'
import { Sphere, MeshDistortMaterial } from '@react-three/drei'
import * as THREE from 'three'

interface RuliadicIslandProps {
  position: [number, number, number]
  color: string
  radius?: number
  semanticText?: string
  semanticValue?: number
  onClick?: () => void
  distortMultiplier?: number
  forceColor?: string
}

function hashText(input: string): number {
  let h = 2166136261
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

export default function RuliadicIsland({
  position,
  color,
  radius = 1,
  semanticText = '',
  semanticValue = 1,
  onClick,
  distortMultiplier = 1,
  forceColor,
}: RuliadicIslandProps) {
  const meshRef = useRef<THREE.Mesh>(null!)
  const [hovered, setHovered] = useState(false)
  const semanticHash = useMemo(() => hashText(semanticText || color), [semanticText, color])
  const effectiveColor = forceColor ?? color
  const semanticMod = useMemo(() => ({
    distort: 0.15 + (semanticHash % 20) / 100,
    speed: 1 + ((semanticHash >> 4) % 20) / 10,
    ringOpacity: 0.12 + ((semanticHash >> 10) % 20) / 100,
  }), [semanticHash])
  const effectiveDistort = useMemo(() => semanticMod.distort * distortMultiplier, [semanticMod.distort, distortMultiplier])
  const effectiveSpeed = useMemo(() => semanticMod.speed * (1 + (distortMultiplier - 1) * 0.35), [semanticMod.speed, distortMultiplier])

  useFrame((state) => {
    if (meshRef.current) {
      meshRef.current.rotation.y += 0.003
      meshRef.current.rotation.x = Math.sin(state.clock.elapsedTime * 0.3 + (semanticHash % 13)) * 0.1
    }
  })

  return (
    <group position={position}>
      <Sphere
        ref={meshRef}
        args={[radius, 64, 64]}
        onClick={onClick}
        onPointerOver={() => setHovered(true)}
        onPointerOut={() => setHovered(false)}
        scale={hovered ? 1.08 + Math.min(0.2, semanticValue * 0.06) : 1}
      >
        <MeshDistortMaterial
          color={effectiveColor}
          roughness={0.18}
          metalness={0.82}
          distort={hovered ? effectiveDistort + 0.12 : effectiveDistort}
          speed={effectiveSpeed}
          transparent
          opacity={Math.max(0.55, Math.min(0.95, 0.7 + semanticValue * 0.12))}
        />
      </Sphere>
      {/* Glow ring */}
      <mesh rotation={[Math.PI / 2, 0, 0]}>
        <ringGeometry args={[radius * 1.25, radius * 1.3, 64]} />
        <meshBasicMaterial
          color={effectiveColor}
          transparent
          opacity={hovered ? semanticMod.ringOpacity + 0.22 : semanticMod.ringOpacity}
          side={THREE.DoubleSide}
        />
      </mesh>
    </group>
  )
}
