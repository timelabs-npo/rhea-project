'use client';

import React, { Suspense } from 'react';
import { Canvas } from '@react-three/fiber';
import { OrbitControls, Environment, Stars, Float } from '@react-three/drei';
import MagneticNebula from '@/components/atlas/MagneticNebula';
import RuliadicIsland from '@/components/RuliadicIsland';
import IsomorphismBeam from '@/components/IsomorphismBeam';

export type SceneNode = {
  name: string;
  position: [number, number, number];
  color: string;
  semanticText: string;
  semanticValue: number;
  radius: number;
};

export type SphereOverrides = {
  glitchMultiplier: number;
  colorOverride?: string;
  severBeam: boolean;
};

export interface Prime3DSceneProps {
  primeNodes: SceneNode[];
  sphereOverrides: SphereOverrides;
  onNodeClick: (name: string) => void;
}

export default function Prime3DScene({ primeNodes, sphereOverrides, onNodeClick }: Prime3DSceneProps) {
  return (
    <div className="absolute inset-0 z-0 cursor-crosshair">
      <Canvas camera={{ position: [0, 0, 10], fov: 40 }}>
        <Suspense fallback={null}>
          <MagneticNebula />
          <Stars radius={100} depth={50} count={7000} factor={4} saturation={0} fade speed={0.5} />
          <ambientLight intensity={0.2} />
          <pointLight position={[10, 10, 10]} intensity={1} color="#00ffff" />
          <Float speed={1.5} rotationIntensity={0.2} floatIntensity={0.5}>
            {primeNodes.map((node) => (
              <RuliadicIsland
                key={node.name}
                position={node.position}
                color={node.color}
                semanticText={node.semanticText}
                semanticValue={node.semanticValue}
                radius={node.radius}
                onClick={() => onNodeClick(node.name)}
                distortMultiplier={sphereOverrides.glitchMultiplier}
                forceColor={sphereOverrides.colorOverride}
              />
            ))}
          </Float>
          {!sphereOverrides.severBeam && (
            <IsomorphismBeam start={{ x: -3, y: 1, z: 0 }} end={{ x: 3, y: -1, z: 0 }} color="#00ffff" speed={0.5} />
          )}
          <OrbitControls enablePan={false} rotateSpeed={0.3} zoomSpeed={0.5} />
          <Environment preset="night" />
        </Suspense>
      </Canvas>
    </div>
  );
}
