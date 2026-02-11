/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Enable faster refresh in development
  experimental: {
    optimizePackageImports: ['lucide-react', 'recharts'],
  },
  // Environment variables exposed to the browser
  env: {
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || 'https://sai-backend-production.up.railway.app',
  },
}

module.exports = nextConfig
