'use strict';

// Logger JSON (uma linha por evento) -> facilita `| json` no Loki/LogQL.
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const threshold = LEVELS[(process.env.LOG_LEVEL || 'info').toLowerCase()] || LEVELS.info;

function log(level, msg, fields = {}) {
  if (LEVELS[level] < threshold) return;
  process.stdout.write(
    JSON.stringify({ time: new Date().toISOString(), level, msg, ...fields }) + '\n'
  );
}

module.exports = {
  debug: (msg, fields) => log('debug', msg, fields),
  info: (msg, fields) => log('info', msg, fields),
  warn: (msg, fields) => log('warn', msg, fields),
  error: (msg, fields) => log('error', msg, fields),
};
