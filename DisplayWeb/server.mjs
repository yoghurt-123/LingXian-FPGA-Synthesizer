import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, normalize, resolve } from 'node:path';

const root = resolve(process.argv[2] ?? 'dist');
const port = Number(process.env.PORT ?? 5173);
const mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.md': 'text/markdown; charset=utf-8',
  '.ico': 'image/x-icon',
};

const server = createServer((request, response) => {
  try {
    const url = new URL(request.url ?? '/', `http://${request.headers.host ?? '127.0.0.1'}`);
    let pathname = decodeURIComponent(url.pathname).replace(/^\/+/, '');
    if (pathname === '') pathname = 'index.html';
    const candidate = resolve(join(root, normalize(pathname).replace(/^(\.\.[/\\])+/, '')));
    if (!candidate.startsWith(root)) {
      response.writeHead(403);
      response.end('Forbidden');
      return;
    }
    let finalPath = candidate;
    if (!existsSync(finalPath) && !extname(finalPath)) {
      finalPath = join(root, 'index.html');
    }
    if (!existsSync(finalPath) || !statSync(finalPath).isFile()) {
      response.writeHead(404);
      response.end('Not found');
      return;
    }
    const body = readFileSync(finalPath);
    response.writeHead(200, {
      'Content-Type': mime[extname(finalPath)] ?? 'application/octet-stream',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    response.end(body);
  } catch (error) {
    response.writeHead(500);
    response.end(`Server error: ${error instanceof Error ? error.message : String(error)}`);
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`AURAL instrument display: http://127.0.0.1:${port}/`);
  console.log('Open Chrome/Edge and click Connect to choose the FTDI COM port.');
});
