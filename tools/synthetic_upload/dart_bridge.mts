// Dedicated-process loopback test bridge; no phone mode or credential IPC.
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
const source = path.resolve(process.cwd());
const { startSyntheticUpload } = await import(pathToFileURL(path.join(source, 'tools/synthetic_upload/launcher.ts')).href);
const { verifyBackupBundle } = await import(pathToFileURL(path.join(source, 'server/outreach/backup-service.ts')).href);
const { canonicalSha256 } = await import(pathToFileURL(path.join(source, 'server/outreach/canonical-json.ts')).href);
const initialApproval = process.argv[4] ? JSON.parse(fs.readFileSync(process.argv[4], 'utf8')) : null;
if (initialApproval && initialApproval.sourceIp !== '127.0.0.1') throw new Error('Bridge is loopback-only');
const { startSyntheticPhone } = initialApproval
  ? await import(pathToFileURL(path.join(source, 'tools/synthetic_phone_upload/launcher.ts')).href)
  : {startSyntheticPhone: null};
const options = {publicHost: '127.0.0.1', browserPort: 0, devicePort: 0,
  certificatePath: process.argv[2], privateKeyPath: process.argv[3]};
const harness = initialApproval ? await startSyntheticPhone({...options, approval: initialApproval}) : await startSyntheticUpload(options);
const write = (value: object) => process.stdout.write(`OUTREACH_BRIDGE ${JSON.stringify(value)}\n`);
write({browserUrl: harness.browserUrl, deviceUrl: harness.deviceUrl, fingerprint: harness.certificateFingerprint});
let stopped = false;
async function stop() {
  if (stopped) return;
  stopped = true;
  await harness.stop();
  fs.rmSync(harness.root, {recursive: true, force: true});
}
try {
  for await (const line of readline.createInterface({input: process.stdin})) {
    const command = JSON.parse(line);
    if (command.action === 'stop') { await stop(); write({stopped: true}); break; }
    if (command.action === 'approve' && initialApproval) {
      const batch = JSON.parse(command.body);
      harness.admission.install({...initialApproval, batch: {
        batchId: batch.batch_id,
        rawUtf8BodySha256: createHash('sha256').update(Buffer.from(command.body, 'utf8')).digest('hex'),
        canonicalBatchSha256: canonicalSha256(batch), syntheticDataConfirmed: true, parentClosureReviewed: true,
        operations: batch.operations.map((op: any) => ({operationId: op.operation_id, entityType: op.entity_type,
          entityId: op.entity_id, revision: op.revision, sequence: op.sequence})),
      }});
      write({approved: true}); continue;
    }
    if (command.action !== 'inspect') throw new Error('Unsupported test command');
    const operations = harness.storage.connection.prepare('SELECT operation_id, entity_type, entity_id, revision, sequence, payload_hash, canonical_payload FROM outreach_operations ORDER BY sequence').all();
    const matching = command.expected.every((op: any) => operations.some((row: any) =>
      ['operation_id', 'entity_type', 'entity_id', 'revision', 'sequence'].every(key => row[key] === op[key]) &&
      row.payload_hash === canonicalSha256(Object.fromEntries(
        ['sequence','operation_id','actor_id','entity_type','entity_id','revision','action','occurred_at','payload']
          .map(key => [key, op[key]]))) &&
      canonicalSha256(JSON.parse(row.canonical_payload)) === canonicalSha256(op.payload)));
    const backups = path.join(harness.root, 'state/backups');
    const manifests = fs.readdirSync(backups).filter((name: string) => name.endsWith('.json'));
    const verified = manifests.length > 0 && manifests.every((name: string) => verifyBackupBundle(path.join(backups, name)).manifest.reason === 'daily_sync');
    write({matching, operationCount: operations.length, verifiedBackup: verified});
  }
} finally { await stop(); }
