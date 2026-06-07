#!/usr/bin/env node

/**
 * workstation — Zero-dependency cross-platform documentation server.
 * Runs on any system with Node.js installed.
 * Serves the `docs` folder on http://localhost:8081.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 8081;
const DOCS_DIR = __dirname; // Serves the folder where serve.js resides (docs/)

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon'
};

const server = http.createServer((req, res) => {
  // Decode URL to handle spaces and special characters
  let safeUrl = decodeURIComponent(req.url);
  
  // Strip query string or hash params
  const hashIdx = safeUrl.indexOf('#');
  if (hashIdx !== -1) safeUrl = safeUrl.substring(0, hashIdx);
  const queryIdx = safeUrl.indexOf('?');
  if (queryIdx !== -1) safeUrl = safeUrl.substring(0, queryIdx);

  // If request is root, redirect to index.html
  if (safeUrl === '/' || safeUrl === '') {
    safeUrl = '/index.html';
  }

  // Resolve file path relative to docs directory
  // Note: we strip leading slashes to resolve correctly inside DOCS_DIR
  const relativePath = safeUrl.replace(/^\/+/, '');
  const filePath = path.join(DOCS_DIR, relativePath);

  // Security check: Ensure requested file is inside DOCS_DIR
  if (!filePath.startsWith(DOCS_DIR)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('403 Forbidden: Access denied.');
    return;
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      // Return 404
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end(`404 Not Found: ${safeUrl}`);
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    res.writeHead(200, {
      'Content-Type': contentType,
      'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate',
      'Pragma': 'no-cache',
      'Expires': '0',
      'Surrogate-Control': 'no-store'
    });

    const stream = fs.createReadStream(filePath);
    stream.on('error', (streamErr) => {
      console.error(`[Error] Streaming file failed: ${streamErr.message}`);
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('500 Internal Server Error');
      }
    });
    stream.pipe(res);
  });
});

server.listen(PORT, () => {
  console.log('\x1b[36m%s\x1b[0m', '------------------------------------------------------------');
  console.log('\x1b[32m%s\x1b[0m', '  Workstation Documentation Server is Running!');
  console.log('\x1b[36m%s\x1b[0m', '------------------------------------------------------------');
  console.log(`  Serving folder: ${DOCS_DIR}`);
  console.log(`  Local URL:      \x1b[34mhttp://localhost:${PORT}/index.html\x1b[0m`);
  console.log(`  Local IP:       \x1b[34mhttp://127.0.0.1:${PORT}/index.html\x1b[0m`);
  console.log('\x1b[36m%s\x1b[0m', '------------------------------------------------------------');
  console.log('  Press Ctrl+C to stop the server.');
});
