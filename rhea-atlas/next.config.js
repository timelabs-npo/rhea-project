/** @type {import('next').NextConfig} */
const isStaticExport = process.env.RHEA_STATIC_EXPORT === '1';

const nextConfig = {
  transpilePackages: ['three', '@react-three/fiber', '@react-three/drei'],
  ...(isStaticExport ? { output: 'export' } : {}),
  eslint: {
    ignoreDuringBuilds: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
};

module.exports = nextConfig;
