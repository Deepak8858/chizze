import type { NextConfig } from "next";

const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-XSS-Protection", value: "1; mode=block" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(self)",
  },
  {
    key: "Content-Security-Policy",
    value:
      "default-src 'self'; " +
      "base-uri 'self'; " +
      "frame-ancestors 'none'; " +
      "form-action 'self'; " +
      "img-src 'self' data: blob: https:; " +
      "font-src 'self' data: https:; " +
      "connect-src 'self' https: wss:; " +
      "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " +
      "style-src 'self' 'unsafe-inline' https:;",
  },
];

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      // Allow all HTTPS images (restaurant logos, banners, avatars from any CDN)
      { protocol: "https", hostname: "**" },
    ],
  },
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: securityHeaders,
      },
    ];
  },
};

export default nextConfig;
