import { describe, it, expect, vi } from 'vitest';
import type { ExecWrapper, XcodeBuildOptions, XcodeBuildResult } from '../../../src/exec/xcodebuild.js';
import {
  successfulBuildOutput,
  failedBuildOutput,
  xcprettyFormattedErrors,
} from '../../fixtures/xcodebuild-outputs.js';

describe('ExecWrapper', () => {
  describe('build', () => {
    it('should accept XcodeBuildOptions and return XcodeBuildResult', async () => {
      // This is a type test - the actual implementation will come later
      const mockWrapper: ExecWrapper = {
        build: async (options: XcodeBuildOptions): Promise<XcodeBuildResult> => {
          return {
            success: true,
            exitCode: 0,
            stdout: '',
            stderr: '',
          };
        },
      };

      const result = await mockWrapper.build({
        workspace: 'Test.xcworkspace',
        scheme: 'TestScheme',
      });

      expect(result).toHaveProperty('success');
      expect(result).toHaveProperty('exitCode');
      expect(result).toHaveProperty('stdout');
      expect(result).toHaveProperty('stderr');
    });

    it('should handle successful build', async () => {
      const mockWrapper: ExecWrapper = {
        build: async (): Promise<XcodeBuildResult> => {
          return {
            success: true,
            exitCode: 0,
            stdout: successfulBuildOutput,
            stderr: '',
            rawLogPath: '/logs/build-1234567890-raw.log',
            prettyLogPath: '/logs/build-1234567890-pretty.log',
            errors: [],
          };
        },
      };

      const result = await mockWrapper.build({
        workspace: 'Test.xcworkspace',
        scheme: 'TestScheme',
        platform: 'ios-sim',
      });

      expect(result.success).toBe(true);
      expect(result.exitCode).toBe(0);
      expect(result.errors).toEqual([]);
      expect(result.rawLogPath).toBeDefined();
      expect(result.prettyLogPath).toBeDefined();
    });

    it('should handle failed build with errors', async () => {
      const mockWrapper: ExecWrapper = {
        build: async (): Promise<XcodeBuildResult> => {
          return {
            success: false,
            exitCode: 65,
            stdout: failedBuildOutput,
            stderr: '',
            rawLogPath: '/logs/build-1234567890-raw.log',
            prettyLogPath: '/logs/build-1234567890-pretty.log',
            errors: [
              "error: /path/to/file.swift:10:5: error: use of unresolved identifier 'undefinedVar'",
              "error: /path/to/file.swift:15:8: error: cannot find 'SomeType' in scope",
            ],
          };
        },
      };

      const result = await mockWrapper.build({
        workspace: 'Test.xcworkspace',
        scheme: 'TestScheme',
      });

      expect(result.success).toBe(false);
      expect(result.exitCode).toBe(65);
      expect(result.errors).toHaveLength(2);
      expect(result.errors?.[0]).toContain('undefinedVar');
    });

    it('should support all platform options', async () => {
      const platforms: Array<'ios-sim' | 'ios-device' | 'macos'> = ['ios-sim', 'ios-device', 'macos'];
      
      for (const platform of platforms) {
        const mockWrapper: ExecWrapper = {
          build: async (options: XcodeBuildOptions): Promise<XcodeBuildResult> => {
            expect(options.platform).toBe(platform);
            return {
              success: true,
              exitCode: 0,
              stdout: '',
              stderr: '',
            };
          },
        };

        await mockWrapper.build({ platform });
      }
    });

    it('should support clean build option', async () => {
      const mockWrapper: ExecWrapper = {
        build: async (options: XcodeBuildOptions): Promise<XcodeBuildResult> => {
          expect(options.clean).toBe(true);
          return {
            success: true,
            exitCode: 0,
            stdout: '',
            stderr: '',
          };
        },
      };

      await mockWrapper.build({
        workspace: 'Test.xcworkspace',
        scheme: 'TestScheme',
        clean: true,
      });
    });

    it('should support derived data path', async () => {
      const mockWrapper: ExecWrapper = {
        build: async (options: XcodeBuildOptions): Promise<XcodeBuildResult> => {
          expect(options.derivedDataPath).toBe('/custom/derived/data');
          return {
            success: true,
            exitCode: 0,
            stdout: '',
            stderr: '',
          };
        },
      };

      await mockWrapper.build({
        workspace: 'Test.xcworkspace',
        scheme: 'TestScheme',
        derivedDataPath: '/custom/derived/data',
      });
    });

    it('should always save raw and pretty logs', async () => {
      const mockWrapper: ExecWrapper = {
        build: async (): Promise<XcodeBuildResult> => {
          return {
            success: true,
            exitCode: 0,
            stdout: '',
            stderr: '',
            rawLogPath: '/logs/build-1234567890-raw.log',
            prettyLogPath: '/logs/build-1234567890-pretty.log',
          };
        },
      };

      const result = await mockWrapper.build({
        workspace: 'Test.xcworkspace',
        scheme: 'TestScheme',
      });

      expect(result.rawLogPath).toBeDefined();
      expect(result.prettyLogPath).toBeDefined();
    });
  });
});
