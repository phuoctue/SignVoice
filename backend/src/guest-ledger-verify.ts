import {verifyGuestLedger} from './services/guest-ledger-file.service';

// Stop the exporter first; the key is read from the process environment, never argv.
async function main() {
  const [directory, streamEpoch, extra] = process.argv.slice(2);
  if (!directory || !streamEpoch || extra) throw new Error('Usage: node dist/guest-ledger-verify.js <directory> <streamEpoch>');
  console.log(JSON.stringify(await verifyGuestLedger(directory, process.env.GUEST_LEDGER_HMAC_KEY || '', streamEpoch)));
}
if (require.main === module) void main().catch(() => {console.error('Guest ledger verification failed; exporter must remain stopped pending investigation'); process.exitCode = 1;});
