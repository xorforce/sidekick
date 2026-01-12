import { describe, it, expect, vi, beforeEach } from 'vitest';
import { XcodeBuildImpl } from '../../../src/exec/xcodebuild-impl.js';
import type { XcodeBuildOptions } from '../../../src/exec/xcodebuild.js';
import { spawn } from 'child_process';

// Mock child_process
vi.mock('child_process', () => ({
  spawn: vi.fn(),
}));

// Mock fs/promises
vi.mock('fs/promises', () => ({
  writeFile: vi.fn().mockResolvedValue(undefined),
  mkdir: vi.fn().mockResolvedValue(undefined),
}));

describe('XcodeBuildImpl', () => {
  let mockSpawn: ReturnType<typeof vi.fn>;
  let mockProcess: {
    stdout: { on: ReturnType<typeof vi.fn> };
    stderr: { on: ReturnType<typeof vi.fn> };
    on: ReturnType<typeof vi.fn>;
  };

  beforeEach(() => {
    vi.clearAllMocks();
    
    mockProcess = {
      stdout: { on: vi.fn() },
      stderr: { on: vi.fn() },
      on: vi.fn((event, callback) => {
        if (event === 'close') {
          // Simulate process completion
          setTimeout(() => callback(0), 10);
        }
        return mockProcess;
      }),
    };

    mockSpawn = vi.mocked(spawn);
    mockSpawn.mockReturnValue(mockProcess as any);
  });

  it('should construct workspace command args correctly', async () => {
    const impl = new XcodeBuildImpl();
    const options: XcodeBuildOptions = {
      workspace: 'MyApp.xcworkspace',
      scheme: 'MyApp',
      configuration: 'Debug',
    };

    await impl.build(options);

    expect(mockSpawn).toHaveBeenCalledWith(
      'xcodebuild',
      expect.arrayContaining([
        '-workspace',
        'MyApp.xcworkspace',
        '-scheme',
        'MyApp',
        '-configuration',
        'Debug',
        'build',
      ]),
      expect.any(Object)
    );
  });

  it('should construct project command args correctly', async () => {
    const impl = new XcodeBuildImpl();
    const options: XcodeBuildOptions = {
      project: 'MyApp.xcodeproj',
      scheme: 'MyApp',
    };

    await impl.build(options);

    expect(mockSpawn).toHaveBeenCalledWith(
      'xcodebuild',
      expect.arrayContaining([
        '-project',
        'MyApp.xcodeproj',
        '-scheme',
        'MyApp',
        'build',
      ]),
      expect.any(Object)
    );
  });

  it('should construct iOS simulator command args correctly', async () => {
    const impl = new XcodeBuildImpl();
    const options: XcodeBuildOptions = {
      workspace: 'MyApp.xcworkspace',
      scheme: 'MyApp',
      platform: 'ios-sim',
      simulator: 'iPhone 15 Pro',
    };

    await impl.build(options);

    expect(mockSpawn).toHaveBeenCalledWith(
      'xcodebuild',
      expect.arrayContaining([
        '-sdk',
        'iphonesimulator',
        '-destination',
        'platform=iOS Simulator,name=iPhone 15 Pro',
      ]),
      expect.any(Object)
    );
  });

  it('should construct iOS device command args correctly', async () => {
    const impl = new XcodeBuildImpl();
    const options: XcodeBuildOptions = {
      workspace: 'MyApp.xcworkspace',
      scheme: 'MyApp',
      platform: 'ios-device',
      device: 'device-uuid',
    };

    await impl.build(options);

    expect(mockSpawn).toHaveBeenCalledWith(
      'xcodebuild',
      expect.arrayContaining([
        '-sdk',
        'iphoneos',
        '-destination',
        'generic/platform=iOS,id=device-uuid',
      ]),
      expect.any(Object)
    );
  });

  it('should construct macOS command args correctly', async () => {
    const impl = new XcodeBuildImpl();
    const options: XcodeBuildOptions = {
      workspace: 'MyApp.xcworkspace',
      scheme: 'MyApp',
      platform: 'macos',
    };

    await impl.build(options);

    expect(mockSpawn).toHaveBeenCalledWith(
      'xcodebuild',
      expect.arrayContaining([
        '-sdk',
        'macosx',
        '-destination',
        'platform=macOS',
      ]),
      expect.any(Object)
    );
  });

  it('should include clean flag when clean option is true', async () => {
    const impl = new XcodeBuildImpl();
    const options: XcodeBuildOptions = {
      workspace: 'MyApp.xcworkspace',
      scheme: 'MyApp',
      clean: true,
    };

    await impl.build(options);

    expect(mockSpawn).toHaveBeenCalledWith(
      'xcodebuild',
      expect.arrayContaining(['clean', 'build']),
      expect.any(Object)
    );
  });

  it('should include derived data path when provided', async () => {
    const impl = new XcodeBuildImpl();
    const options: XcodeBuildOptions = {
      workspace: 'MyApp.xcworkspace',
      scheme: 'MyApp',
      derivedDataPath: '/custom/derived/data',
    };

    await impl.build(options);

    expect(mockSpawn).toHaveBeenCalledWith(
      'xcodebuild',
      expect.arrayContaining([
        '-derivedDataPath',
        '/custom/derived/data',
      ]),
      expect.any(Object)
    );
  });

  it('should extract errors from output', async () => {
    const impl = new XcodeBuildImpl();
    const options: XcodeBuildOptions = {
      workspace: 'MyApp.xcworkspace',
      scheme: 'MyApp',
    };

    // Mock stdout data with errors
    const errorOutput = 'error: test.swift:10:5: error: test error message';
    mockProcess.stdout.on.mockImplementation((event, callback) => {
      if (event === 'data') {
        setTimeout(() => callback(Buffer.from(errorOutput)), 10);
      }
    });

    const result = await impl.build(options);

    expect(result.errors).toBeDefined();
    expect(result.errors?.length).toBeGreaterThan(0);
    expect(result.errors?.[0]).toContain('error:');
  });
});
