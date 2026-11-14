import type { File, VitestRunnerImportSource } from '@vitest/runner';
import { updateTask } from '@vitest/runner';
import { processError } from '@vitest/utils/error';
import { VitestTestRunner } from 'vitest/runners';
import { cleanupFileDatabases } from './database-cleanup';

type OwnedDatabases = Readonly<{ uri: string; control: string; fileId: string }>;

export default class DatabaseCleanupRunner extends VitestTestRunner {
  private pending?: OwnedDatabases;
  private readonly owned = new Map<string, OwnedDatabases>();

  override async importFile(filepath: string, source: VitestRunnerImportSource): Promise<unknown> {
    if (source === 'collect' && this.pending) {
      this.owned.set(filepath, this.pending);
      this.pending = undefined;
    }
    const module = await super.importFile(filepath, source);
    if (source === 'setup' && filepath.replace(/\\/g, '/').endsWith('/tests/setup.ts')) {
      this.pending = (module as { fileDatabases: OwnedDatabases }).fileDatabases;
    }
    return module;
  }

  // Vitest 1.6 calls this after runFiles, even when collection or suite hooks failed.
  override async onAfterRunFiles(files: File[] = []): Promise<void> {
    try {
      for (const file of files) {
        const owned = this.owned.get(file.filepath);
        if (!owned) continue;
        this.owned.delete(file.filepath);
        try {
          await cleanupFileDatabases(owned.uri, owned.control, owned.fileId);
        } catch (cause) {
          const error = new Error(`DB cleanup failed for ${file.filepath}: ${String(cause)}`, { cause });
          file.result ??= { state: 'fail' };
          file.result.state = 'fail';
          (file.result.errors ??= []).push(processError(error));
          updateTask(file, this);
        }
      }
    } finally {
      super.onAfterRunFiles();
    }
  }
}
