import http from 'node:http';
import { complete } from './fig_completion_engine.mjs';

const defaultHost = '127.0.0.1';
const defaultPort = 17382;
const maxBodyBytes = 1024 * 1024;

export function createServer() {
  return http.createServer(async (request, response) => {
    response.setHeader('Access-Control-Allow-Origin', 'http://127.0.0.1');
    response.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    response.setHeader('Access-Control-Allow-Headers', 'content-type');
    if (request.method === 'OPTIONS') {
      response.writeHead(204);
      response.end();
      return;
    }
    if (request.method === 'GET' && request.url === '/health') {
      writeJson(response, 200, {
        ok: true,
        service: 'ianvs-fig-completion-service',
      });
      return;
    }
    if (request.method !== 'POST' || !request.url?.startsWith('/complete')) {
      writeJson(response, 404, { error: 'not_found' });
      return;
    }
    try {
      const body = await readJsonBody(request);
      writeJson(response, 200, complete(body));
    } catch (error) {
      writeJson(response, 400, {
        error: 'bad_request',
        message: error instanceof Error ? error.message : 'Invalid request',
      });
    }
  });
}

export function startServer({
  host = defaultHost,
  port = defaultPort,
} = {}) {
  const server = createServer();
  server.listen(port, host, () => {
    const address = server.address();
    const resolvedPort =
      typeof address === 'object' && address !== null ? address.port : port;
    console.log(
      `ianvs fig completion service listening on http://${host}:${resolvedPort}`,
    );
  });
  return server;
}

function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > maxBodyBytes) {
        reject(new Error('Request body is too large'));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on('error', reject);
    request.on('end', () => {
      try {
        const text = Buffer.concat(chunks).toString('utf8');
        resolve(text.trim().isEmpty ? {} : JSON.parse(text));
      } catch (error) {
        reject(error);
      }
    });
  });
}

function writeJson(response, statusCode, payload) {
  response.writeHead(statusCode, { 'content-type': 'application/json' });
  response.end(JSON.stringify(payload));
}

function cliOptions(argv) {
  const options = { host: defaultHost, port: defaultPort };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--host' && argv[index + 1]) {
      options.host = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg === '--port' && argv[index + 1]) {
      options.port = Number.parseInt(argv[index + 1], 10);
      index += 1;
    }
  }
  return options;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startServer(cliOptions(process.argv.slice(2)));
}
