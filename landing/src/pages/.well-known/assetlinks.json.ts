import type { APIRoute } from 'astro';

// Android App Links: este dominio abre la app de este entorno.
// ANDROID_PACKAGE y ANDROID_SHA256 (huellas separadas por comas) los fija el CI.
const pkg = process.env.ANDROID_PACKAGE ?? 'com.tuempresa.escaque';
const fingerprints = (process.env.ANDROID_SHA256 ?? '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

export const GET: APIRoute = () =>
  new Response(
    JSON.stringify(
      [
        {
          relation: ['delegate_permission/common.handle_all_urls'],
          target: { namespace: 'android_app', package_name: pkg, sha256_cert_fingerprints: fingerprints },
        },
      ],
      null,
      2,
    ),
    { headers: { 'Content-Type': 'application/json' } },
  );
