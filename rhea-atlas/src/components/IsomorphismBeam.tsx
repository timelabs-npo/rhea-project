'use client';

import React, { useRef, useMemo } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';

type Vec3Like = { x: number; y: number; z: number } | THREE.Vector3;

function toVec3(v: Vec3Like): THREE.Vector3 {
  return v instanceof THREE.Vector3 ? v : new THREE.Vector3(v.x, v.y, v.z);
}

interface IsomorphismBeamProps {
  start: Vec3Like;
  end: Vec3Like;
  color?: string;
  speed?: number;
}

export default function IsomorphismBeam({
  start,
  end,
  color = '#00ffff',
  speed = 1.0,
}: IsomorphismBeamProps) {
  const startV = useMemo(() => toVec3(start), [start]);
  const endV = useMemo(() => toVec3(end), [end]);
  const materialRef = useRef<THREE.ShaderMaterial>(null);

  // Create curve between points
  const curve = useMemo(() => {
    const midPoint = new THREE.Vector3().addVectors(startV, endV).multiplyScalar(0.5);
    const height = startV.distanceTo(endV) * 0.2;
    midPoint.y += height;
    return new THREE.QuadraticBezierCurve3(startV, midPoint, endV);
  }, [startV, endV]);

  const shaderMaterial = useMemo(() => {
    return new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 },
        uColor: { value: new THREE.Color(color) },
        uSpeed: { value: speed },
      },
      vertexShader: `
        varying vec2 vUv;
        void main() {
          vUv = uv;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: `
        uniform float uTime;
        uniform vec3 uColor;
        uniform float uSpeed;
        varying vec2 vUv;
        void main() {
          float pulse = mod(vUv.x - uTime * uSpeed * 0.5, 1.0);
          float strength = smoothstep(0.0, 0.1, 1.0 - abs(pulse - 0.5));
          vec3 finalColor = mix(uColor * 0.2, uColor, strength);
          gl_FragColor = vec4(finalColor, strength * 0.8);
        }
      `,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
  }, [color, speed]);

  useFrame((state) => {
    if (materialRef.current) {
      materialRef.current.uniforms.uTime.value = state.clock.elapsedTime;
    }
  });

  return (
    <mesh>
      <tubeGeometry args={[curve, 64, 0.02, 8, false]} />
      <primitive object={shaderMaterial} ref={materialRef} attach="material" />
    </mesh>
  );
}
