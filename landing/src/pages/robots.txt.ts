import type { APIRoute } from 'astro';
import { indexable } from '../site';

// Solo producción se indexa; qa y dev bloquean a los buscadores.
export const GET: APIRoute = ({ site }) =>
  new Response(
    indexable
      ? `User-agent: *\nAllow: /\n\nSitemap: ${new URL('/sitemap.xml', site)}\n`
      : 'User-agent: *\nDisallow: /\n',
    { headers: { 'Content-Type': 'text/plain; charset=utf-8' } },
  );
