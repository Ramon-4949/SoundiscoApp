import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { androidPayload, sendAndroidPush, runAndroidBatch, createWorkerState,
  healthStatus, runLoop, startHealthServer } from './worker.mjs';

const job = { job_id: 'job', lease: 'lease', token: 'PRIVATE_TOKEN',
  notification_id: 'notification', recipient: 'recipient', title: 'Confirmación', body: 'Ana confirmó el hito' };

test('FCM payload preserves text, sound, channel and routing; sends to one token', async () => {
  let captured;
  const result = await sendAndroidPush(job, { send: async value => { captured = value; return 'message'; } });
  assert.equal(result.success, true);
  assert.deepEqual(captured.notification, { title: job.title, body: job.body });
  assert.equal(captured.android.notification.sound, 'default');
  assert.equal(captured.android.notification.channelId, 'soundisco_notifications');
  assert.deepEqual(captured.data, { notification_id: job.notification_id, recipient_id: job.recipient });
  assert.equal(captured.token, job.token);
  assert.ok(Buffer.byteLength(JSON.stringify(androidPayload({ ...job, title: 'á'.repeat(9000), body: 'á'.repeat(9000) }))) < 4096);
});

test('only definitive token errors invalidate registration; timeouts are bounded', async () => {
  for (const code of ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token',
    'messaging/invalid-argument', 'messaging/mismatched-credential', 'messaging/server-unavailable']) {
    const result = await sendAndroidPush(job, { send: async () => { throw { code, message: 'PRIVATE' }; } });
    assert.equal(result.invalid, ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code));
    assert.equal(result.error, code);
  }
  assert.equal((await sendAndroidPush(job, { send: () => new Promise(() => {}) }, 5)).error, 'messaging/timeout');
  assert.equal((await sendAndroidPush(job, { send: async () => { throw new Error('PRIVATE'); } })).error, 'messaging/transport-error');
});

test('FCM acknowledges each lease, logs safe error codes and surfaces RPC failures', async () => {
  const acknowledgments = [], logs = [];
  const original = console.error;
  console.error = message => logs.push(message);
  try {
    const count = await runAndroidBatch({}, {}, {
      rpc: async (_, name, params) => {
        if (name === 'claim_android_pushes') return [job, { ...job, job_id: 'second' }];
        acknowledgments.push(params);
      },
      sendPush: async current => ({ success: current.job_id === 'job', invalid: false,
        error: current.job_id === 'job' ? null : 'messaging/mismatched-credential' }),
    });
    assert.equal(count, 2);
    assert.deepEqual(acknowledgments.map(value => value.p_success), [true, false]);
    assert.equal(acknowledgments[0].p_lease, job.lease);
    assert.equal(logs.join('').includes(job.token), false);
    await assert.rejects(runAndroidBatch({}, {}, {
      rpc: async (_, name) => { if (name === 'claim_android_pushes') return [job]; throw new Error('RPC failed'); },
      sendPush: async () => ({ success: true, invalid: false, error: null }),
    }), /acknowledgments failed/);
  } finally { console.error = original; }
});

test('health rejects missing, failed, stale or stopped loops; accepts both idle healthy loops', async () => {
  const states = { apns: createWorkerState(), fcm: createWorkerState() };
  assert.equal(healthStatus(states).status, 'degraded');
  for (const state of Object.values(states)) Object.assign(state, { active: true, healthy: true, lastProgress: Date.now() });
  const server = startHealthServer(0, states);
  if (!server.listening) await once(server, 'listening');
  try {
    const url = `http://127.0.0.1:${server.address().port}/health`;
    assert.equal((await fetch(url)).status, 200);
    states.fcm.healthy = false;
    assert.equal((await fetch(url)).status, 503);
    states.fcm.healthy = true;
    states.fcm.lastProgress -= 300001;
    assert.equal(healthStatus(states).processes.fcm.active, false);
    states.fcm.lastProgress = Date.now();
    states.fcm.active = false;
    assert.equal(healthStatus(states).status, 'degraded');
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('a blocked APNs batch does not stop FCM and shutdown stops both loops', async () => {
  const controller = new AbortController();
  const states = { apns: createWorkerState(), fcm: createWorkerState() };
  let release;
  const blocked = new Promise(resolve => { release = resolve; });
  const apns = runLoop('apns', () => blocked, states.apns, controller.signal, false, 1);
  const fcm = runLoop('fcm', async () => { controller.abort(); return 0; }, states.fcm, controller.signal, false, 1);
  await fcm;
  assert.notEqual(states.fcm.lastSuccess, null);
  assert.equal(states.apns.lastSuccess, null);
  release(0);
  await apns;
  assert.equal(states.apns.active, false);
  assert.equal(states.fcm.active, false);
});
