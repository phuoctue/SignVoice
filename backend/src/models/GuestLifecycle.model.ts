import {Schema, model} from 'mongoose';
import {z} from 'zod';

const id = z.string().regex(/^[a-f0-9]{24}$/), hash = z.string().regex(/^[a-f0-9]{64}$/);
const base = {eventId: z.string().uuid(), streamEpoch: z.string().uuid(), sequence: z.number().int().positive().safe(), committedAt: z.string().datetime()};
export const lifecycleEventSchema = z.discriminatedUnion('kind', [
  z.object({...base, kind: z.literal('DISCARDED'), payload: z.object({guestUserId: id, guestGrantedAt: z.string().datetime().nullable(),
    dataVersion: z.number().int().nonnegative().safe(), committedAt: z.string().datetime()}).strict()}).strict(),
  z.object({...base, kind: z.literal('CONVERTED'), payload: z.object({sameUserId: id, guestGrantedAt: z.string().datetime().nullable(),
    newEpoch: z.number().int().nonnegative().safe(), convertedAt: z.string().datetime()}).strict()}).strict(),
  z.object({...base, kind: z.literal('GRANTED'), payload: z.object({deviceHash: hash, lastGrantedAt: z.string().datetime(),
    guestUserId: id, requestHash: hash}).strict()}).strict(),
  z.object({...base, kind: z.literal('BARRIER'), payload: z.object({coveredAt: z.string().datetime()}).strict()}).strict(),
]);

export type LifecyclePayload =
  | {guestUserId: string; guestGrantedAt: string | null; dataVersion: number; committedAt: string}
  | {sameUserId: string; guestGrantedAt: string | null; newEpoch: number; convertedAt: string}
  | {deviceHash: string; lastGrantedAt: string; guestUserId: string; requestHash: string}
  | {coveredAt: string};
export interface LifecycleEvent {
  eventId: string;
  streamEpoch: string;
  sequence: number;
  kind: 'DISCARDED' | 'CONVERTED' | 'GRANTED' | 'BARRIER';
  committedAt: string;
  payload: LifecyclePayload;
}
const outbox = new Schema<LifecycleEvent>({
  eventId: {type: String, required: true, immutable: true, unique: true},
  streamEpoch: {type: String, required: true, immutable: true},
  sequence: {type: Number, required: true, immutable: true},
  kind: {type: String, enum: ['DISCARDED', 'CONVERTED', 'GRANTED', 'BARRIER'], required: true, immutable: true},
  committedAt: {type: String, required: true, immutable: true},
  payload: {type: Schema.Types.Mixed, required: true, immutable: true},
}, {collection: 'guest_lifecycle_outbox', versionKey: false, strict: 'throw'});
outbox.index({streamEpoch: 1, sequence: 1}, {unique: true});
export const GuestLifecycleOutbox = model<LifecycleEvent>('GuestLifecycleOutbox', outbox);

const counter = new Schema({
  _id: {type: String, required: true}, streamEpoch: {type: String, required: true},
  sequence: {type: Number, required: true}, activatedAt: {type: Date, required: true},
  exportedSequence: {type: Number, default: 0}, exportedHash: String, coveredAt: String,
  lastBarrierSequence: Number, lastBarrierAt: Date,
}, {collection: 'guest_lifecycle_counter', versionKey: false});
export const GuestLifecycleCounter = model('GuestLifecycleCounter', counter);
