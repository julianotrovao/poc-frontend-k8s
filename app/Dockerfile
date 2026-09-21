# syntax=docker/dockerfile:1
ARG NODE_VERSION=22-alpine

# ---- 1) deps: todas as dependências (dev incluso) para testes
FROM node:${NODE_VERSION} AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---- 2) test: `docker build --target test .` executa os testes automatizados
FROM deps AS test
COPY . .
RUN npm test -- --ci

# ---- 3) prod-deps: somente dependências de produção
FROM node:${NODE_VERSION} AS prod-deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---- 4) runtime: imagem final mínima, não-root
FROM node:${NODE_VERSION} AS runtime
ARG APP_VERSION=dev
ENV NODE_ENV=production \
    APP_VERSION=${APP_VERSION} \
    PORT=3000
WORKDIR /app
RUN apk upgrade --no-cache
COPY --from=prod-deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src
COPY --chown=node:node public ./public
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD node -e "fetch('http://127.0.0.1:3000/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "src/server.js"]
