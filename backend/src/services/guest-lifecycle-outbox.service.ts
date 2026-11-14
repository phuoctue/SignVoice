import {randomUUID} from 'node:crypto';
import mongoose, {ClientSession} from 'mongoose';
import {GuestLifecycleCounter, GuestLifecycleOutbox, LifecycleEvent, LifecyclePayload, lifecycleEventSchema} from '../models/GuestLifecycle.model';
import {authClock} from './auth-clock';
import {chainWriteConcern} from './session-chain.service';
import {GuestMediaCleanup} from '../models/GuestMediaCleanup.model';

const initializations = new WeakMap<object, Promise<void>>();
export function ensureGuestOutbox(): Promise<void> {
  const database = mongoose.connection.db;
  if (!database) return Promise.reject(new Error('Guest lifecycle database unavailable'));
  const initialized = initializations.get(database);
  if (initialized) return initialized;
  const pending = initializeGuestOutbox().catch(error => {initializations.delete(database); throw error;});
  initializations.set(database, pending);
  return pending;
}
async function initializeGuestOutbox() {
  await Promise.all([GuestLifecycleCounter.init(), GuestLifecycleOutbox.init(), GuestMediaCleanup.init()]);
  // Existing streams need no majority upsert on every lifecycle request.
  if (await GuestLifecycleCounter.exists({_id: 'lifecycle'})) return;
  try {
    await GuestLifecycleCounter.updateOne({_id: 'lifecycle'}, {$setOnInsert: {
      streamEpoch: randomUUID(), sequence: 0, activatedAt: authClock.now(), exportedSequence: 0,
    }}, {upsert: true, writeConcern: chainWriteConcern});
  } catch (error) {
    if ((error as {code?: number}).code !== 11000) throw error;
  }
}
export async function appendGuestEvent(kind: LifecycleEvent['kind'], payload: LifecyclePayload, session: ClientSession) {
  const counter = await GuestLifecycleCounter.findOneAndUpdate({_id: 'lifecycle', sequence: {$lt: Number.MAX_SAFE_INTEGER}},
    {$inc: {sequence: 1}}, {new: true, session});
  if (!counter) throw new Error('Guest lifecycle counter unavailable or exhausted');
  const event: LifecycleEvent = {eventId: randomUUID(), streamEpoch: counter.streamEpoch, sequence: counter.sequence,
    kind, committedAt: authClock.now().toISOString(), payload};
  await GuestLifecycleOutbox.create([lifecycleEventSchema.parse(event)], {session});
  return event;
}
export async function appendCoverageBarrier(onlyWhenNeeded = false) {
  await ensureGuestOutbox();
  return mongoose.connection.transaction(async session => {
    const counter = await GuestLifecycleCounter.findById('lifecycle').session(session), now = authClock.now();
    if (!counter) throw new Error('Guest lifecycle counter unavailable');
    if (onlyWhenNeeded && counter.sequence === counter.lastBarrierSequence && counter.lastBarrierAt && +now - +counter.lastBarrierAt < 300000) return null;
    const event = await appendGuestEvent('BARRIER', {coveredAt: now.toISOString()}, session);
    await GuestLifecycleCounter.updateOne({_id: 'lifecycle', streamEpoch: event.streamEpoch},
      {$set: {lastBarrierSequence: event.sequence, lastBarrierAt: now}}, {session});
    return event;
  }, {writeConcern: chainWriteConcern});
}
