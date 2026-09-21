#!/usr/bin/env bash
# Integra o Grafana EXISTENTE: descobre o datasource Prometheus, cria o datasource Loki (se faltar)
# e importa o dashboard "Frontend Node.js — SLI/SLO" via API.
# Uso:  GRAFANA_PASSWORD='***' ./10-grafana-integration.sh          (usuário admin)
#   ou: GRAFANA_TOKEN='glsa_...' ./10-grafana-integration.sh        (service account token, papel Admin)
set -euo pipefail
source "$(dirname "$0")/env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GRAFANA_URL LOKI_URL ROOT
export GRAFANA_USER="${GRAFANA_USER:-admin}"
[ -n "${GRAFANA_TOKEN:-}" ] || : "${GRAFANA_PASSWORD:?Defina GRAFANA_PASSWORD (ou GRAFANA_TOKEN)}"

python3 - <<'PY'
import base64, json, os, sys, urllib.request, urllib.error

base = os.environ["GRAFANA_URL"].rstrip("/")
hdr = {"Content-Type": "application/json"}
if os.environ.get("GRAFANA_TOKEN"):
    hdr["Authorization"] = "Bearer " + os.environ["GRAFANA_TOKEN"]
else:
    cred = f'{os.environ["GRAFANA_USER"]}:{os.environ["GRAFANA_PASSWORD"]}'.encode()
    hdr["Authorization"] = "Basic " + base64.b64encode(cred).decode()

def call(method, path, body=None):
    req = urllib.request.Request(base + path, method=method, headers=hdr,
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"ERRO {method} {path}: {e.code} {e.read().decode()[:300]}")

print("Grafana:", call("GET", "/api/health").get("version", "?"))
ds = call("GET", "/api/datasources")
prom = next((d for d in ds if d["type"] == "prometheus"), None)
loki = next((d for d in ds if d["type"] == "loki"), None)
if not prom:
    sys.exit("Nenhum datasource Prometheus encontrado no Grafana — crie um apontando para o Prometheus existente.")
if not loki:
    loki = call("POST", "/api/datasources", {"name": "Loki", "type": "loki", "access": "proxy",
                                              "url": os.environ["LOKI_URL"], "uid": "loki"})["datasource"]
    print("Datasource Loki criado ->", os.environ["LOKI_URL"])
else:
    print("Datasource Loki já existe:", loki["name"], loki["uid"])

path = os.path.join(os.environ["ROOT"], "k8s/observability/dashboards/frontend-slo.json")
raw = open(path, encoding="utf-8").read()
# O JSON usa uid fixos "prometheus"/"loki": troca pelos uid reais do seu Grafana.
raw = raw.replace('"uid": "prometheus"', f'"uid": "{prom["uid"]}"').replace('"uid": "loki"', f'"uid": "{loki["uid"]}"')
dash = json.loads(raw)
res = call("POST", "/api/dashboards/db", {"dashboard": dash, "overwrite": True, "message": "poc-frontend-nodejs"})
print("Dashboard:", base + res.get("url", ""))
PY
