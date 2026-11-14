import {randomBytes} from 'node:crypto';

export const guestGrantBody = () => ({
  deviceKey: randomBytes(32).toString('hex'),
  requestKey: randomBytes(32).toString('hex'),
  expectedLastGrantAt: null,
});
