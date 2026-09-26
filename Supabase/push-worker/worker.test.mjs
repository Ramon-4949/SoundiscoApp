import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { providerToken, payload, rpc, sendPush, runBatch, configuration } from './worker.mjs';

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const config = { url: 'https://example.invalid', serviceKey: 'SECRET', teamID: 'TEAM', bundleID: 'hola.SoundiscoApp' };
const credentials = {
  sandbox: { key: privateKey, keyID: 'SANDBOX_KEY' },
  production: { key: privateKey, keyID: 'PRODUCTION_KEY' },
};
const job = { job_id: 'job', lease: 'lease', notification_id: 'notification', recipient: 'recipient',
  token: 'a'.repeat(64), environment: 'sandbox', titulo: 'PRIVATE TITLE', ubicacion: 'PRIVATE LOCATION' };

test('JWT uses ES256 P1363 signature and Apple claims', () => {
  const jwt = providerToken(privateKey, 'KEY', 'TEAM', 1700000000000);
  const [header, claims, signature] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'ES256', kid: 'KEY' });
  assert.deepEqual(JSON.parse(Buffer.from(claims, 'base64url')), { iss: 'TEAM', iat: 1700000000 });
  assert.equal(verify('sha256', Buffer.from(header + '.' + claims),
    { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')), true);
});

test('payload uses only server-generated text and routing identifiers', () => {
  assert.deepEqual(Object.keys(payload(job)).sort(), ['aps','notification_id','recipient_id']);
  assert.equal(JSON.stringify(payload(job)).includes('PRIVATE'), false);
  assert.equal(JSON.stringify(payload(job)).includes(job.token), false);
  assert.ok(Buffer.byteLength(JSON.stringify(payload(job))) < 4096);
  const dynamic = payload({ ...job, title: 'Confirmación de Hito', body: 'Alice confirmó Montaje' });
  assert.equal(dynamic.aps.sound, 'default');
  assert.deepEqual(dynamic.aps.alert, { title: 'Confirmación de Hito', body: 'Alice confirmó Montaje' });
  const long = payload({ ...job, title: '😀'.repeat(9000), body: '\\"😀'.repeat(9000) });
  assert.ok(Buffer.byteLength(JSON.stringify(long)) < 4096);
});

function fakeTransport(status, reason, capture) {
  return origin => {
    capture.origin = origin;
    const session = new EventEmitter();
    session.destroy = () => { capture.closed = true; };
    session.request = headers => {
      capture.headers = headers;
      const stream = new EventEmitter();
      stream.setEncoding = () => {};
      stream.end = body => {
        capture.rawBody = body;
        capture.payload = JSON.parse(body);
        queueMicrotask(() => {
          stream.emit('response', { ':status': status });
          stream.emit('data', JSON.stringify({ reason }));
          stream.emit('end');
        });
      };
      return stream;
    };
    return session;
  };
}

test('HTTP2 request carries correct APNs headers, host and generic body', async () => {
  const capture = {};
  assert.equal((await sendPush(job, config, 'JWT', fakeTransport(200, null, capture))).success, true);
  assert.equal(capture.origin, 'https://api.sandbox.push.apple.com');
  assert.equal(capture.headers['apns-topic'], config.bundleID);
  assert.equal(capture.headers['apns-push-type'], 'alert');
  assert.equal(capture.headers['apns-collapse-id'], job.notification_id);
  assert.deepEqual(capture.payload, payload(job));
  assert.equal(capture.closed, true);
});

test('APNs request preserves accented Spanish as UTF-8 bytes', async () => {
  const capture = {};
  const message = { ...job, title: 'Confirmación de Hito', body: 'Ana confirmó la asignación' };
  await sendPush(message, config, 'JWT', fakeTransport(200, null, capture));
  assert.equal(Buffer.isBuffer(capture.rawBody), true);
  assert.equal(capture.rawBody.toString('utf8'), JSON.stringify(payload(message)));
});

test('APNs transient and configuration failures preserve device registration', async () => {
  for (const [status,reason] of [[429,'TooManyRequests'],[500,'InternalServerError'],[400,'BadDeviceToken'],[403,'InvalidProviderToken']]) {
    const result = await sendPush(job, config, 'JWT', fakeTransport(status, reason, {}));
    assert.equal(result.success, false);
    assert.equal(result.statusCode, status);
    assert.equal(result.invalid, false);
  }
  assert.equal((await sendPush(job, config, 'JWT', fakeTransport(410, 'Unregistered', {}))).invalid, true);
});

test('production uses production host', async () => {
  const capture = {};
  await sendPush({ ...job, environment: 'production' }, config, 'JWT', fakeTransport(200, null, capture));
  assert.equal(capture.origin, 'https://api.push.apple.com');
});

test('batch acknowledges successes and failures without skipping other jobs', async () => {
  const acknowledgments = [];
  const originalWarn = console.error;
  console.error = () => {};
  try {
  const count = await runBatch(config, credentials, {
    rpc: async (_, name, params) => {
      if (name === 'claim_notification_pushes_v2') return [job, { ...job, job_id: 'second' }];
      if (name === 'finish_notification_push') acknowledgments.push(params);
    },
    sendPush: async current => {
      if (current.job_id === 'second') throw new Error('SECRET transport details');
      return { success: true, error: null, invalid: false };
    },
  });
  assert.equal(count, 2);
  assert.deepEqual(acknowledgments.map(a => a.p_success), [true,false]);
  assert.equal(acknowledgments[1].p_error, 'Transport error');
  assert.equal(acknowledgments[0].p_lease, job.lease);
  } finally {
    console.error = originalWarn;
  }
});

test('batch logs APNs diagnostics without device tokens or recipient data', async () => {
  const warnings = [];
  const originalWarn = console.error;
  console.error = value => warnings.push(JSON.parse(value));
  try {
    await runBatch(config, credentials, {
      rpc: async (_, name) => name === 'claim_notification_pushes_v2' ? [job] : undefined,
      sendPush: async () => ({ success: false, error: 'BadDeviceToken', invalid: false }),
    });
  } finally {
    console.error = originalWarn;
  }
  assert.deepEqual(warnings, [{ service: 'apns', environment: 'sandbox',
    status: 'failed', reason: 'BadDeviceToken', statusCode: null, apnsID: null, bundleID: config.bundleID }]);
  assert.equal(JSON.stringify(warnings).includes(job.token), false);
  assert.equal(JSON.stringify(warnings).includes(job.recipient), false);
});

test('batch signs sandbox and production jobs with their matching APNs keys', async () => {
  const keyIDs = [];
  const productionJob = { ...job, job_id: 'production-job', environment: 'production' };
  await runBatch(config, credentials, {
    rpc: async (_, name) => name === 'claim_notification_pushes_v2'
      ? [job, productionJob] : undefined,
    sendPush: async (_current, _config, jwt) => {
      keyIDs.push(JSON.parse(Buffer.from(jwt.split('.')[0], 'base64url')).kid);
      return { success: true, error: null, invalid: false };
    },
  });
  assert.deepEqual(keyIDs, ['SANDBOX_KEY', 'PRODUCTION_KEY']);
});

test('RPC errors do not disclose credentials or server responses', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => new Response('SECRET details', { status: 403 });
  try {
    await assert.rejects(rpc(config, 'claim_notification_pushes'),
      { message: 'Supabase RPC claim_notification_pushes failed: 403' });
  } finally { globalThis.fetch = original; }
});

test('RPC sends new Supabase secret keys only through apikey', async () => {
  const original = globalThis.fetch;
  let captured;
  globalThis.fetch = async (_url, options) => {
    captured = options.headers;
    return new Response('[]', { status: 200 });
  };
  try {
    await rpc({ ...config, serviceKey: 'sb_secret_example' }, 'claim_notification_pushes');
    assert.equal(captured.apikey, 'sb_secret_example');
    assert.equal(captured.Authorization, undefined);

    await rpc({ ...config, serviceKey: 'legacy.jwt.key' }, 'claim_notification_pushes');
    assert.equal(captured.Authorization, 'Bearer legacy.jwt.key');
  } finally { globalThis.fetch = original; }
});

test('configuration requires secrets and rejects non-HTTPS origins', () => {
  assert.throws(() => configuration({}), /Missing configuration/);
  assert.throws(() => configuration({
    SUPABASE_URL: 'http://example.invalid', SUPABASE_SERVICE_ROLE_KEY: 'secret',
    APNS_KEY_ID: 'key', APNS_TEAM_ID: 'team', APPLE_P8_KEY: 'private-key', APNS_BUNDLE_ID: 'bundle',
    APNS_PRODUCTION_KEY_ID: 'production-key', APPLE_PRODUCTION_P8_KEY: 'production-private-key',
  }), /HTTPS/);
});

test('configuration reads the APNs key from the environment and normalizes escaped newlines', () => {
  const result = configuration({
    SUPABASE_URL: 'https://example.invalid', SUPABASE_SERVICE_ROLE_KEY: 'secret',
    APNS_KEY_ID: 'key', APNS_TEAM_ID: 'team',
    APPLE_P8_KEY: '-----BEGIN PRIVATE KEY-----\\nvalue\\n-----END PRIVATE KEY-----',
    APNS_PRODUCTION_KEY_ID: 'production-key',
    APPLE_PRODUCTION_P8_KEY: '-----BEGIN PRIVATE KEY-----\\nproduction\\n-----END PRIVATE KEY-----',
    APNS_BUNDLE_ID: 'hola.SoundiscoApp', PORT: '10000',
  });
  assert.equal(result.credentials.sandbox.privateKey, '-----BEGIN PRIVATE KEY-----\nvalue\n-----END PRIVATE KEY-----');
  assert.equal(result.credentials.sandbox.keyID, 'key');
  assert.equal(result.credentials.production.privateKey,
    '-----BEGIN PRIVATE KEY-----\nproduction\n-----END PRIVATE KEY-----');
  assert.equal(result.credentials.production.keyID, 'production-key');
  assert.equal(result.port, 10000);
  assert.throws(() => configuration({
    SUPABASE_URL: 'https://example.invalid', SUPABASE_SERVICE_ROLE_KEY: 'secret',
    APNS_KEY_ID: 'key', APNS_TEAM_ID: 'team', APPLE_P8_KEY: 'private-key',
    APNS_PRODUCTION_KEY_ID: 'production-key', APPLE_PRODUCTION_P8_KEY: 'production-private-key',
    APNS_BUNDLE_ID: 'hola.SoundiscoApp', PORT: 'invalid',
  }), /PORT/);
});

test('configuration requires separate production credentials', () => {
  assert.throws(() => configuration({
    SUPABASE_URL: 'https://example.invalid', SUPABASE_SERVICE_ROLE_KEY: 'secret',
    APNS_KEY_ID: 'sandbox-key', APNS_TEAM_ID: 'team', APPLE_P8_KEY: 'sandbox-private-key',
    APNS_BUNDLE_ID: 'hola.SoundiscoApp',
  }), /APNS_PRODUCTION_KEY_ID/);
});
