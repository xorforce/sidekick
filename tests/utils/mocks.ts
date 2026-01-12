/**
 * Test utilities and mocks
 */

import type { ExecWrapper, XcodeBuildResult } from '../../src/exec/xcodebuild.js';

/**
 * Creates a mock ExecWrapper for testing
 */
export function createMockExecWrapper(
  result: XcodeBuildResult | ((options: any) => XcodeBuildResult)
): ExecWrapper {
  return {
    build: async (options) => {
      if (typeof result === 'function') {
        return result(options);
      }
      return result;
    },
  };
}

/**
 * Creates a successful build result
 */
export function createSuccessfulBuildResult(
  overrides?: Partial<XcodeBuildResult>
): XcodeBuildResult {
  return {
    success: true,
    exitCode: 0,
    stdout: '',
    stderr: '',
    rawLogPath: '/logs/build-1234567890-raw.log',
    prettyLogPath: '/logs/build-1234567890-pretty.log',
    errors: [],
    ...overrides,
  };
}

/**
 * Creates a failed build result
 */
export function createFailedBuildResult(
  errors: string[],
  overrides?: Partial<XcodeBuildResult>
): XcodeBuildResult {
  return {
    success: false,
    exitCode: 65,
    stdout: '',
    stderr: '',
    rawLogPath: '/logs/build-1234567890-raw.log',
    prettyLogPath: '/logs/build-1234567890-pretty.log',
    errors,
    ...overrides,
  };
}
