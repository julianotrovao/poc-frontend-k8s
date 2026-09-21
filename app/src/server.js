'use strict';

const { createApp } = require('./app');
const logger = require('./logger');

const port = Number(process.env.PORT || 3000);
const app = createApp();
const server = app.listen(port, '0.0.0.0', () => logger.info('listening', { port }));

// Graceful shutdown: sai do readiness, espera o endpoint sair do Service, fecha conexões.
function shutdown(signal) {
  logger.info('shutdown', { signal });
  app.locals.ready = false;
  setTimeout(() => server.close(() => process.exit(0)), 5000);
  setTimeout(() => process.exit(1), 15000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
