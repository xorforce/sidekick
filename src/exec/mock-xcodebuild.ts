/**
 * Mock implementation of ExecWrapper for testing and prototyping
 */

import type { ExecWrapper, XcodeBuildOptions, XcodeBuildResult } from './xcodebuild.js';

// Mock outputs - in real implementation these would come from xcodebuild
const successfulBuildOutput = `
=== BUILD TARGET MyApp OF PROJECT MyApp WITH CONFIGURATION Debug ===

Check dependencies
Compile Sources
Link Binary
Code Sign
Build succeeded
`;

const failedBuildOutput = `
=== BUILD TARGET MyApp OF PROJECT MyApp WITH CONFIGURATION Debug ===

Compile Sources
error: /path/to/file.swift:10:5: error: use of unresolved identifier 'undefinedVar'
    undefinedVar = 5
    ^
error: /path/to/file.swift:15:8: error: cannot find 'SomeType' in scope
    let x: SomeType = ...
           ^
Build failed
`;

export class MockXcodeBuild implements ExecWrapper {
  private shouldFail: boolean = false;
  private delay: number = 100; // Simulate build time

  constructor(options?: { shouldFail?: boolean; delay?: number }) {
    this.shouldFail = options?.shouldFail ?? false;
    this.delay = options?.delay ?? 100;
  }

  async build(_options: XcodeBuildOptions): Promise<XcodeBuildResult> {
    // Simulate build time
    // options will be used when mock becomes more realistic
    await new Promise(resolve => setTimeout(resolve, this.delay));

    if (this.shouldFail) {
      return {
        success: false,
        exitCode: 65,
        stdout: failedBuildOutput,
        stderr: '',
        rawLogPath: '/logs/build-mock-raw.log',
        prettyLogPath: '/logs/build-mock-pretty.log',
        errors: [
          "error: /path/to/file.swift:10:5: error: use of unresolved identifier 'undefinedVar'",
          "error: /path/to/file.swift:15:8: error: cannot find 'SomeType' in scope",
        ],
      };
    }

    return {
      success: true,
      exitCode: 0,
      stdout: successfulBuildOutput,
      stderr: '',
      rawLogPath: '/logs/build-mock-raw.log',
      prettyLogPath: '/logs/build-mock-pretty.log',
      errors: [],
    };
  }
}
