import http2 from 'node:http2';
import { createPrivateKey, sign } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { pathToFileURL } from 'node:url';
import express from 'express';

export function providerToken(key, keyID, teamID, now = Date.now()) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = encode({ alg: 'ES256', kid: keyID }) + '.' +
    encode({ iss: teamID, iat: Math.floor(now / 1000) });
  return unsigned + '.' + sign('sha256', Buffer.from(unsigned),
    { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
}

export function payload(job) {
  const text = (value, fallback, limit) => typeof value === 'string' && value.trim()
    ? Array.from(value.trim()).slice(0, limit).join('') : fallback;
  return {
    aps: {
      alert: {
        title: text(job.title, 'SounDisco', 120),
        body: text(job.body, 'Tienes una actualización. Abre la app para ver los detalles.', 500),
      },
      sound: 'default', 'thread-id': 'soundisco-notifications',
    },
    notification_id: job.notification_id,
    recipient_id: job.recipient,
  };
}

export async function rpc(config, name, params = {}) {
  const headers = {
    apikey: config.serviceKey,
    'Content-Type': 'application/json',
  };
  // Legacy service_role keys are JWTs and must also identify the Postgres role.
  // New sb_secret keys authenticate through apikey and must not be parsed as JWTs.
  if (!config.serviceKey.startsWith('sb_secret_')) {
    headers.Authorization = 'Bearer ' + config.serviceKey;
  }
  const response = await fetch(config.url + '/rest/v1/rpc/' + name, {
    method: 'POST', redirect: 'error',
    headers,
    body: JSON.stringify(params),
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error('Supabase RPC ' + name + ' failed: ' + response.status);
  const body = await response.text();
  return body ? JSON.parse(body) : null;
}

export function sendPush(job, config, jwt, connect = http2.connect) {
  return new Promise((resolve, reject) => {
    if (!['sandbox', 'production'].includes(job.environment)) {
      reject(new Error('Invalid APNs environment'));
      return;
    }
    const host = job.environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    const client = connect('https://' + host);
    let settled = false;
    const finish = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      client.destroy();
      if (error) reject(error); else resolve(result);
    };
    const timer = setTimeout(() => finish(new Error('APNs timeout')), 15000);
    client.on('error', () => finish(new Error('APNs connection error')));
    let request;
    try {
      request = client.request({
        ':method': 'POST', ':path': '/3/device/' + job.token,
        authorization: 'bearer ' + jwt, 'apns-topic': config.bundleID,
        'apns-push-type': 'alert', 'apns-priority': '10',
        'apns-collapse-id': job.notification_id,
        'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600),
      });
    } catch {
      finish(new Error('APNs request error'));
      return;
    }
    let status = 0;
    let body = '';
    request.on('response', headers => { status = Number(headers[':status']); });
    request.setEncoding('utf8');
    request.on('data', chunk => { body += chunk; });
    request.on('error', () => finish(new Error('APNs stream error')));
    request.on('end', () => {
      let reason;
      try { reason = JSON.parse(body).reason; } catch { reason = 'HTTP ' + status; }
      // Only Unregistered invalidates a device. Topic/environment mistakes do not.
      finish(null, { success: status === 200,
        error: status === 200 ? null : String(reason ?? 'HTTP ' + status).slice(0, 100),
        invalid: status === 410 && reason === 'Unregistered' });
    });
    request.end(JSON.stringify(payload(job)));
  });
}

export async function runBatch(config, key, dependencies = {}) {
  const call = dependencies.rpc ?? rpc;
  const send = dependencies.sendPush ?? sendPush;
  await call(config, 'generate_notification_reminders');
  const jobs = await call(config, 'claim_notification_pushes_v2');
  const jwt = providerToken(key, config.keyID, config.teamID);
  let acknowledgmentFailures = 0;
  for (let offset = 0; offset < jobs.length; offset += 5) {
    const results = await Promise.allSettled(jobs.slice(offset, offset + 5).map(async job => {
      let result;
      try { result = await send(job, config, jwt); }
      catch { result = { success: false, error: 'Transport error', invalid: false }; }
      await call(config, 'finish_notification_push', {
        p_job: job.job_id, p_lease: job.lease, p_success: result.success,
        p_error: result.error, p_invalid: result.invalid,
      });
    }));
    acknowledgmentFailures += results.filter(result => result.status === 'rejected').length;
  }
  if (acknowledgmentFailures) throw new Error('Push acknowledgments failed: ' + acknowledgmentFailures);
  return jobs.length;
}

export function configuration(env = process.env) {
  for (const name of ['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','APNS_KEY_ID','APNS_TEAM_ID','APPLE_P8_KEY','APNS_BUNDLE_ID']) {
    if (!env[name]?.trim()) throw new Error('Missing configuration: ' + name);
  }
  const url = new URL(env.SUPABASE_URL);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw new Error('SUPABASE_URL must be an HTTPS origin');
  }
  const port = Number(env.PORT ?? 10000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT must be a valid TCP port');
  }
  return {
    url: url.origin, serviceKey: env.SUPABASE_SERVICE_ROLE_KEY,
    keyID: env.APNS_KEY_ID, teamID: env.APNS_TEAM_ID,
    bundleID: env.APNS_BUNDLE_ID,
    privateKey: env.APPLE_P8_KEY.replace(/\\n/g, '\n').trim(),
    port,
  };
}

export function startHealthServer(port) {
  const app = express();
  app.disable('x-powered-by');
  app.get('/', (_request, response) => response.status(200).json({ service: 'soundisco-push-worker', status: 'ok' }));
  app.get('/health', (_request, response) => response.status(200).json({ status: 'ok' }));
  return app.listen(port, '0.0.0.0', () => {
    console.info(JSON.stringify({ service: 'health', status: 'listening', port }));
  });
}

async function main() {
  const config = configuration();
  const key = createPrivateKey(config.privateKey);
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('APNs requires a P-256 signing key');
  }
  const once = process.argv.includes('--once');
  const server = once ? null : startHealthServer(config.port);
  const shutdown = new AbortController();
  for (const signal of ['SIGTERM','SIGINT']) process.on(signal, () => shutdown.abort());
  try {
    while (!shutdown.signal.aborted) {
      try {
        const count = await runBatch(config, key);
        console.info(JSON.stringify({ processed: count, at: new Date().toISOString() }));
      } catch {
        // No tokens, user IDs, request headers or remote response contents in logs.
        console.error('Push cycle failed. Check server configuration and private outbox status.');
        if (once) { process.exitCode = 1; return; }
      }
      if (once) return;
      try { await delay(10000, undefined, { signal: shutdown.signal }); } catch { break; }
    }
  } finally {
    server?.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => { console.error('Worker startup failed. Check required configuration and APNs key.'); process.exitCode = 1; });
}
