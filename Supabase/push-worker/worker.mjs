import http2 from 'node:http2';
import { createPrivateKey, sign } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { pathToFileURL } from 'node:url';
import express from 'express';
import { applicationDefault, initializeApp, deleteApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

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
      sound: job.is_alarm === true ? 'milestone_alarm.wav' : 'default',
      'thread-id': 'soundisco-notifications',
      ...(job.is_alarm === true ? { 'interruption-level': 'time-sensitive', category: 'MILESTONE_ALARM' } : {}),
      ...(Number.isInteger(job.badge) && job.badge >= 0 ? { badge: job.badge } : {}),
    },
    notification_id: job.notification_id,
    recipient_id: job.recipient,
    ...(job.is_alarm === true ? { is_alarm: true } : {}),
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
        'content-type': 'application/json',
        'apns-collapse-id': job.notification_id,
        'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600),
      });
    } catch {
      finish(new Error('APNs request error'));
      return;
    }
    let status = 0;
    let apnsID = null;
    let body = '';
    request.on('response', headers => {
      status = Number(headers[':status']);
      apnsID = headers['apns-id'] ?? null;
    });
    request.setEncoding('utf8');
    request.on('data', chunk => { body += chunk; });
    request.on('error', () => finish(new Error('APNs stream error')));
    request.on('end', () => {
      let reason;
      try { reason = JSON.parse(body).reason; } catch { reason = 'HTTP ' + status; }
      // Only Unregistered invalidates a device. Topic/environment mistakes do not.
      finish(null, { success: status === 200, statusCode: status, apnsID,
        error: status === 200 ? null : String(reason ?? 'HTTP ' + status).slice(0, 100),
        invalid: status === 410 && reason === 'Unregistered' });
    });
    request.end(Buffer.from(JSON.stringify(payload(job)), 'utf8'));
  });
}

export async function runBatch(config, credentials, dependencies = {}) {
  const call = dependencies.rpc ?? rpc;
  const send = dependencies.sendPush ?? sendPush;
  await call(config, 'generate_notification_reminders');
  const jobs = await call(config, 'claim_notification_pushes_v4');
  const tokens = new Map();
  const tokenFor = environment => {
    const credential = credentials[environment];
    if (!credential) throw new Error('Missing APNs credentials for ' + environment);
    if (!tokens.has(environment)) {
      tokens.set(environment, providerToken(credential.key, credential.keyID, config.teamID));
    }
    return tokens.get(environment);
  };
  let acknowledgmentFailures = 0;
  for (let offset = 0; offset < jobs.length; offset += 5) {
    const results = await Promise.allSettled(jobs.slice(offset, offset + 5).map(async job => {
      let result;
      try { result = await send(job, config, tokenFor(job.environment)); }
      catch (error) {
        const safeReasons = ['APNs timeout', 'APNs connection error', 'APNs request error',
          'APNs stream error', 'Invalid APNs environment',
          'Missing APNs credentials for sandbox', 'Missing APNs credentials for production'];
        result = { success: false,
          error: safeReasons.includes(error?.message) ? error.message : 'Transport error', invalid: false };
      }
      if (!result.success) {
        console.error(JSON.stringify({ service: 'apns', environment: job.environment,
          status: 'failed', reason: result.error, statusCode: result.statusCode ?? null,
          apnsID: result.apnsID ?? null, bundleID: config.bundleID }));
      } else {
        console.info(JSON.stringify({ service: 'apns', status: 'accepted',
          environment: job.environment, badge: job.badge ?? null }));
      }
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

export function androidPayload(job) {
  return {
    token: job.token,
    notification: payload(job).aps.alert,
    data: { notification_id: job.notification_id, recipient_id: job.recipient },
    android: {
      priority: 'high', ttl: 3600000,
      notification: { sound: 'default', channelId: 'soundisco_notifications', tag: job.notification_id },
    },
  };
}

export async function sendAndroidPush(job, messaging, timeoutMs = 20000) {
  let timer;
  try {
    await Promise.race([
      messaging.send(androidPayload(job)),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject({ code: 'messaging/timeout' }), timeoutMs);
      }),
    ]);
    return { success: true, error: null, invalid: false };
  } catch (error) {
    const code = typeof error?.code === 'string' && /^messaging\/[a-z-]{1,80}$/.test(error.code)
      ? error.code : 'messaging/transport-error';
    return { success: false, error: code,
      invalid: ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code) };
  } finally { clearTimeout(timer); }
}

export async function runAndroidBatch(config, messaging, dependencies = {}) {
  const call = dependencies.rpc ?? rpc;
  const send = dependencies.sendPush ?? sendAndroidPush;
  const jobs = await call(config, 'claim_android_pushes');
  let failures = 0;
  for (let offset = 0; offset < jobs.length; offset += 5) {
    const results = await Promise.allSettled(jobs.slice(offset, offset + 5).map(async job => {
      const result = await send(job, messaging);
      if (!result.success) console.error(JSON.stringify({ service: 'fcm', status: 'failed', reason: result.error }));
      await call(config, 'finish_android_push', {
        p_job: job.job_id, p_lease: job.lease, p_success: result.success,
        p_error: result.error, p_invalid: result.invalid,
      });
    }));
    failures += results.filter(result => result.status === 'rejected').length;
  }
  if (failures) throw new Error('Android push acknowledgments failed: ' + failures);
  return jobs.length;
}

export function createWorkerState() {
  return { active: false, healthy: false, lastProgress: null, lastSuccess: null };
}

export function healthStatus(states, now = Date.now()) {
  const processes = Object.fromEntries(['apns', 'fcm'].map(name => {
    const state = states[name];
    const active = Boolean(state?.active && state.lastProgress !== null && now - state.lastProgress < 300000);
    return [name, { active, healthy: active && state.healthy, lastSuccess: state?.lastSuccess ?? null }];
  }));
  return { status: Object.values(processes).every(value => value.healthy) ? 'ok' : 'degraded',
    capabilities: { apnsBadge: true, iosMilestoneAlarm: true, apnsQueueRPC: 'claim_notification_pushes_v4' }, processes };
}

export async function runLoop(name, batch, state, signal, once = false, intervalMs = 10000) {
  state.active = true;
  try {
    while (!signal.aborted) {
      state.lastProgress = Date.now();
      try {
        const count = await batch();
        state.healthy = true;
        state.lastSuccess = Date.now();
        console.info(JSON.stringify({ service: name, processed: count, at: new Date().toISOString() }));
      } catch {
        state.healthy = false;
        console.error(JSON.stringify({ service: name, status: 'cycle_failed' }));
        if (once) process.exitCode = 1;
      }
      state.lastProgress = Date.now();
      if (once) break;
      try { await delay(intervalMs, undefined, { signal }); } catch { break; }
    }
  } finally { state.active = false; }
}

export function configuration(env = process.env) {
  for (const name of ['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','APNS_TEAM_ID','APNS_BUNDLE_ID']) {
    if (!env[name]?.trim()) throw new Error('Missing configuration: ' + name);
  }
  const sandboxKeyID = env.APNS_SANDBOX_KEY_ID ?? env.APNS_KEY_ID;
  const sandboxPrivateKey = env.APPLE_SANDBOX_P8_KEY ?? env.APPLE_P8_KEY;
  for (const [name, value] of [
    ['APNS_SANDBOX_KEY_ID (or APNS_KEY_ID)', sandboxKeyID],
    ['APPLE_SANDBOX_P8_KEY (or APPLE_P8_KEY)', sandboxPrivateKey],
    ['APNS_PRODUCTION_KEY_ID', env.APNS_PRODUCTION_KEY_ID],
    ['APPLE_PRODUCTION_P8_KEY', env.APPLE_PRODUCTION_P8_KEY],
  ]) {
    if (!value?.trim()) throw new Error('Missing configuration: ' + name);
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
    teamID: env.APNS_TEAM_ID, bundleID: env.APNS_BUNDLE_ID,
    credentials: {
      sandbox: {
        keyID: sandboxKeyID.trim(),
        privateKey: sandboxPrivateKey.replace(/\\n/g, '\n').trim(),
      },
      production: {
        keyID: env.APNS_PRODUCTION_KEY_ID.trim(),
        privateKey: env.APPLE_PRODUCTION_P8_KEY.replace(/\\n/g, '\n').trim(),
      },
    },
    port,
  };
}

export function startHealthServer(port, states) {
  const app = express();
  app.disable('x-powered-by');
  app.get('/', (_request, response) => response.status(200).json({ service: 'soundisco-push-worker', status: 'ok' }));
  app.get('/health', (_request, response) => {
    const health = healthStatus(states);
    response.status(health.status === 'ok' ? 200 : 503).json(health);
  });
  return app.listen(port, '0.0.0.0', () => {
    console.info(JSON.stringify({ service: 'health', status: 'listening', port }));
  });
}

async function main() {
  const config = configuration();
  const credentials = {};
  for (const [environment, credential] of Object.entries(config.credentials)) {
    const key = createPrivateKey(credential.privateKey);
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
      throw new Error('APNs requires a P-256 signing key for ' + environment);
    }
    credentials[environment] = { key, keyID: credential.keyID };
  }
  const once = process.argv.includes('--once');
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim()) {
    throw new Error('GOOGLE_APPLICATION_CREDENTIALS must point to a Firebase service account JSON file');
  }
  const firebase = initializeApp({ credential: applicationDefault() });
  const messaging = getMessaging(firebase);
  const states = { apns: createWorkerState(), fcm: createWorkerState() };
  const server = once ? null : startHealthServer(config.port, states);
  const shutdown = new AbortController();
  for (const signal of ['SIGTERM','SIGINT']) process.on(signal, () => shutdown.abort());
  const supabase = { rpc: (name, params) => rpc(config, name, params) };
  const dependencies = name => ({ rpc: async (_config, method, params) => {
    const result = await supabase.rpc(method, params);
    states[name].lastProgress = Date.now();
    return result;
  } });
  try {
    await Promise.all([
      runLoop('apns', () => runBatch(config, credentials, dependencies('apns')), states.apns, shutdown.signal, once),
      runLoop('fcm', () => runAndroidBatch(config, messaging, dependencies('fcm')), states.fcm, shutdown.signal, once),
    ]);
  } finally {
    server?.close();
    await deleteApp(firebase);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => { console.error('Worker startup failed. Check APNs keys, Firebase credentials file and required configuration.'); process.exitCode = 1; });
}
