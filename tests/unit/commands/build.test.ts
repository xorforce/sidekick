import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildCommand } from '../../../src/commands/build.js';
import { createMockExecWrapper, createSuccessfulBuildResult, createFailedBuildResult } from '../../utils/mocks.js';
import type { ExecWrapper } from '../../../src/exec/xcodebuild.js';

describe('buildCommand', () => {
  let consoleSpy: {
    log: ReturnType<typeof vi.spyOn>;
    error: ReturnType<typeof vi.spyOn>;
  };

  beforeEach(() => {
    consoleSpy = {
      log: vi.spyOn(console, 'log').mockImplementation(() => {}),
      error: vi.spyOn(console, 'error').mockImplementation(() => {}),
    };
    vi.spyOn(process, 'exit').mockImplementation((code?: number) => {
      throw new Error(`process.exit(${code})`);
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('should show success message on successful build', async () => {
    const mockWrapper = createMockExecWrapper(createSuccessfulBuildResult());

    await buildCommand({
      execWrapper: mockWrapper,
      noQuirk: false,
    });

    // Verify log output was shown
    expect(consoleSpy.log).toHaveBeenCalled();
    const logOutput = (consoleSpy.log as any).mock.calls.flat().join('\n');
    expect(logOutput).toContain('Logs saved to:');
  });

  it('should show log paths after successful build', async () => {
    const mockWrapper = createMockExecWrapper(
      createSuccessfulBuildResult({
        rawLogPath: '/logs/test-raw.log',
        prettyLogPath: '/logs/test-pretty.log',
      })
    );

    await buildCommand({
      execWrapper: mockWrapper,
      noQuirk: false,
    });

    const output = (consoleSpy.log as any).mock.calls.flat().join('\n');
    expect(output).toContain('Logs saved to:');
    expect(output).toContain('/logs/test-raw.log');
    expect(output).toContain('/logs/test-pretty.log');
  });

  it('should show error message on failed build', async () => {
    const mockWrapper = createMockExecWrapper(
      createFailedBuildResult([
        "error: test.swift:10:5: error: test error",
      ])
    );

    try {
      await buildCommand({
        execWrapper: mockWrapper,
        noQuirk: false,
      });
      expect.fail('Should have exited with error');
    } catch (error) {
      // process.exit throws, which is expected
      expect((error as Error).message).toContain('process.exit');
    }

    // Verify error output was shown
    expect(consoleSpy.log).toHaveBeenCalled();
    const logOutput = (consoleSpy.log as any).mock.calls.flat().join('\n');
    expect(logOutput).toContain('Errors:');
  });

  it('should show errors on failed build', async () => {
    const errors = [
      "error: test.swift:10:5: error: first error",
      "error: test.swift:20:5: error: second error",
    ];
    const mockWrapper = createMockExecWrapper(createFailedBuildResult(errors));

    try {
      await buildCommand({
        execWrapper: mockWrapper,
        noQuirk: false,
      });
    } catch (error) {
      // process.exit throws, which is expected
    }

    const logOutput = (consoleSpy.log as any).mock.calls.flat().join('\n');
    
    expect(logOutput).toContain('Errors:');
    expect(logOutput).toContain('first error');
    expect(logOutput).toContain('second error');
  });

  it('should show log path on failed build', async () => {
    const mockWrapper = createMockExecWrapper(
      createFailedBuildResult(['error'], {
        rawLogPath: '/logs/failed-raw.log',
      })
    );

    try {
      await buildCommand({
        execWrapper: mockWrapper,
        noQuirk: false,
      });
    } catch (error) {
      // process.exit throws, which is expected
    }

    const logOutput = (consoleSpy.log as any).mock.calls.flat().join('\n');
    
    expect(logOutput).toContain('See full log:');
    expect(logOutput).toContain('/logs/failed-raw.log');
  });

  it('should pass build options to exec wrapper', async () => {
    const mockWrapper: ExecWrapper = {
      build: vi.fn().mockResolvedValue(createSuccessfulBuildResult()),
    };

    await buildCommand({
      execWrapper: mockWrapper,
      platform: 'ios-sim',
      clean: true,
      noQuirk: false,
    });

    expect(mockWrapper.build).toHaveBeenCalledWith(
      expect.objectContaining({
        platform: 'ios-sim',
        clean: true,
      })
    );
  });
});
