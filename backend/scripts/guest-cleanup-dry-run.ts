import mongoose from 'mongoose';
import {parseArgs} from 'node:util';
import {assertOperatorTarget, readOperatorUri, serverTime} from './guest-cleanup-operator';

if (require.main === module) {
  (async () => {
    const {values} = parseArgs({options: {'allow-copy': {type: 'string'}}});
    const uri = await readOperatorUri(), target = assertOperatorTarget(uri, values['allow-copy']);
    // No application config import or dotenv, and no model auto-creation/index writes.
    mongoose.set('autoCreate', false); mongoose.set('autoIndex', false);
    await mongoose.connect(uri, {autoCreate: false, autoIndex: false, serverSelectionTimeoutMS: 5000, connectTimeoutMS: 5000, timeoutMS: 120000});
    try {
      if (!target.local) {
        const status = await mongoose.connection.db!.command({connectionStatus: 1});
        if (!status.authInfo?.authenticatedUsers?.length) throw new Error();
      }
      const {guestCleanupDryRun} = await import('../src/services/guest-cleanup-report.service');
      const report = await guestCleanupDryRun(await serverTime(mongoose.connection.db!));
      if (!report) throw new Error();
      console.log(JSON.stringify(report, null, 2));
      console.error(`Dry-run: ${report.counts.ordinary_expired} ordinary + ${report.counts.legacy_unknown} legacy due; ${report.counts.synthetic_exempt} synthetic exempt; ${report.counts.converted_permanent_skipped} converted/permanent skipped. Zero writes.`);
    } finally {await mongoose.disconnect();}
  })().catch(() => {console.error('Dry-run refused or failed; no approval report produced. URI and credentials are suppressed.'); process.exitCode = 1;});
}
