// Teste de carga: 300 usuários virtuais (VUs) — rampa 1m, platô 3m, descida 30s.
// Thresholds espelham os SLOs: erro < 0,5%, p95 < 300ms.
import http from 'k6/http';
import { check, group, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://frontend.local';

export const options = {
  scenarios: {
    usuarios_300: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 300 },
        { duration: '3m', target: 300 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.005'],
    http_req_duration: ['p(95)<300', 'p(99)<800'],
    'http_req_duration{endpoint:healthz}': ['p(95)<100'],
    checks: ['rate>0.99'],
  },
  tags: { testid: 'frontend-300vu' },
};

export default function () {
  group('navegacao', () => {
    const home = http.get(`${BASE}/`, { tags: { endpoint: 'home' } });
    check(home, { 'home 200': (r) => r.status === 200 });

    const work = http.get(`${BASE}/api/work`, { tags: { endpoint: 'work' } });
    check(work, { 'work 200': (r) => r.status === 200 });

    const health = http.get(`${BASE}/healthz`, { tags: { endpoint: 'healthz' } });
    check(health, { 'healthz 200': (r) => r.status === 200 });
  });
  sleep(1);
}
