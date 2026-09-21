'use strict';

const path = require('node:path');
const crypto = require('node:crypto');
const express = require('express');
const { register, metricsMiddleware } = require('./metrics');
const logger = require('./logger');

const PUBLIC_DIR = path.join(__dirname, '..', 'public');
const QUIET_ROUTES = new Set(['/healthz', '/readyz', '/metrics']);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function createApp(options = {}) {
  const cfg = {
    version: options.version ?? process.env.APP_VERSION ?? 'dev',
    env: options.env ?? process.env.APP_ENV ?? 'local',
    workMinMs: Number(options.workMinMs ?? process.env.WORK_MIN_MS ?? 20),
    workMaxMs: Number(options.workMaxMs ?? process.env.WORK_MAX_MS ?? 120),
    // 0..1 — fração de respostas 500 simuladas em /api/work (útil para testar SLO/alertas)
    errorRate: Number(options.errorRate ?? process.env.ERROR_RATE ?? 0),
  };
  const startedAt = Date.now();
  const app = express();
  app.locals.ready = true;
  app.disable('x-powered-by');

  app.use((req, res, next) => {
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('X-Frame-Options', 'DENY');
    res.set('Referrer-Policy', 'no-referrer');
    next();
  });
  app.use(metricsMiddleware);
  app.use((req, res, next) => {
    const started = process.hrtime.bigint();
    res.on('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - started) / 1e6;
      const level = QUIET_ROUTES.has(req.path) ? 'debug' : 'info';
      logger[level]('request', {
        method: req.method,
        path: req.path,
        status: res.statusCode,
        duration_ms: Math.round(durationMs * 100) / 100,
      });
    });
    next();
  });

  app.get('/healthz', (req, res) => {
    res.status(200).json({
      status: 'ok',
      version: cfg.version,
      uptime_s: Math.round((Date.now() - startedAt) / 1000),
    });
  });

  app.get('/readyz', (req, res) => {
    if (!app.locals.ready) return res.status(503).json({ status: 'shutting-down' });
    return res.status(200).json({ status: 'ready' });
  });

  app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  app.get('/api/info', (req, res) => {
    res.json({ app: 'poc-frontend-nodejs', version: cfg.version, env: cfg.env, hostname: process.env.HOSTNAME || 'local' });
  });

  // Simula trabalho de backend com latência variável (alvo do teste de carga).
  app.get('/api/work', async (req, res) => {
    const { workMinMs: min, workMaxMs: max } = cfg;
    const delay = max > min ? crypto.randomInt(min, max + 1) : min;
    await sleep(delay);
    if (cfg.errorRate > 0 && crypto.randomInt(0, 10000) < cfg.errorRate * 10000) {
      return res.status(500).json({ error: 'simulated failure' });
    }
    return res.json({ ok: true, delay_ms: delay, version: cfg.version });
  });

  // Endpoint de demonstração: gera 5xx para exercitar alertas de burn rate do SLO.
  app.get('/api/error', (req, res) => res.status(500).json({ error: 'forced error' }));

  app.get('/', (req, res) => res.sendFile(path.join(PUBLIC_DIR, 'index.html')));
  app.use(express.static(PUBLIC_DIR));
  app.use((req, res) => res.status(404).json({ error: 'not found' }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    logger.error('unhandled', { message: err.message });
    res.status(500).json({ error: 'internal error' });
  });

  return app;
}

module.exports = { createApp };
