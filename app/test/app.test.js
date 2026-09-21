'use strict';

const request = require('supertest');
const { createApp } = require('../src/app');

const fastApp = (opts = {}) => createApp({ workMinMs: 0, workMaxMs: 0, version: 'test', ...opts });

describe('health endpoints', () => {
  test('GET /healthz retorna 200 e status ok', async () => {
    const res = await request(fastApp()).get('/healthz');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.version).toBe('test');
    expect(typeof res.body.uptime_s).toBe('number');
  });

  test('GET /readyz alterna para 503 durante o shutdown', async () => {
    const app = fastApp();
    expect((await request(app).get('/readyz')).status).toBe(200);
    app.locals.ready = false;
    expect((await request(app).get('/readyz')).status).toBe(503);
  });
});

describe('api', () => {
  test('GET /api/info', async () => {
    const res = await request(fastApp({ env: 'poc' })).get('/api/info');
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ app: 'poc-frontend-nodejs', env: 'poc', version: 'test' });
  });

  test('GET /api/work com latência configurada', async () => {
    const res = await request(fastApp({ workMinMs: 5, workMaxMs: 10 })).get('/api/work');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.delay_ms).toBeGreaterThanOrEqual(5);
    expect(res.body.delay_ms).toBeLessThanOrEqual(10);
  });

  test('GET /api/work com ERROR_RATE=1 retorna 500', async () => {
    const res = await request(fastApp({ errorRate: 1 })).get('/api/work');
    expect(res.status).toBe(500);
  });

  test('GET /api/error retorna 500', async () => {
    expect((await request(fastApp()).get('/api/error')).status).toBe(500);
  });
});

describe('frontend e erros', () => {
  test('GET / serve o HTML', async () => {
    const res = await request(fastApp()).get('/');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/html/);
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['x-powered-by']).toBeUndefined();
  });

  test('rota inexistente retorna 404 JSON', async () => {
    const res = await request(fastApp()).get('/nao-existe');
    expect(res.status).toBe(404);
    expect(res.body.error).toBe('not found');
  });
});

describe('metrics', () => {
  test('GET /metrics expõe contador e histograma por rota', async () => {
    const app = fastApp();
    await request(app).get('/healthz');
    await request(app).get('/api/work');
    const res = await request(app).get('/metrics');
    expect(res.status).toBe(200);
    expect(res.text).toMatch(/http_requests_total\{[^}]*route="\/healthz"[^}]*status="200"\}/);
    expect(res.text).toMatch(/http_request_duration_seconds_bucket\{[^}]*le="0.3"/);
    expect(res.text).toContain('process_cpu_user_seconds_total');
  });
});
