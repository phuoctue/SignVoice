import { mergeConfig } from 'vitest/config';
import config from '../vitest.config';

export default mergeConfig(config, {
  test: { runner: './tests/database-cleanup-runner.ts', sequence: { hooks: 'stack' } },
});
