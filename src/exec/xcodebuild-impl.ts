/**
 * Real implementation of ExecWrapper using xcodebuild
 */

import { spawn } from 'child_process';
import { writeFile, mkdir } from 'fs/promises';
import { join } from 'path';
import type { ExecWrapper, XcodeBuildOptions, XcodeBuildResult } from './xcodebuild.js';

export class XcodeBuildImpl implements ExecWrapper {
  private logDir: string;

  constructor(logDir: string = './.sidekick/logs') {
    this.logDir = logDir;
  }

  async build(options: XcodeBuildOptions): Promise<XcodeBuildResult> {
    const args = this.buildCommandArgs(options);
    const timestamp = Date.now();
    
    // Create log directory
    const logPath = join(this.logDir, `build-${timestamp}`);
    await mkdir(logPath, { recursive: true });

    const rawLogPath = join(logPath, 'raw.log');
    const prettyLogPath = join(logPath, 'pretty.log');

    return new Promise((resolve) => {
      const rawLog: string[] = [];
      const stdout: string[] = [];
      const stderr: string[] = [];

      // Spawn xcodebuild process
      const xcodebuild = spawn('xcodebuild', args, {
        stdio: ['ignore', 'pipe', 'pipe'],
      });

      // Collect stdout
      xcodebuild.stdout?.on('data', (data: Buffer) => {
        const text = data.toString();
        rawLog.push(text);
        stdout.push(text);
      });

      // Collect stderr
      xcodebuild.stderr?.on('data', (data: Buffer) => {
        const text = data.toString();
        rawLog.push(text);
        stderr.push(text);
      });

      // Handle process completion
      xcodebuild.on('close', async (code) => {
        const rawLogContent = rawLog.join('');
        const stdoutContent = stdout.join('');
        const stderrContent = stderr.join('');

        // Save raw log
        try {
          await writeFile(rawLogPath, rawLogContent, 'utf-8');
        } catch (error) {
          // Log error but don't fail the build
          console.error(`Failed to save raw log: ${error}`);
        }

        // For now, pretty log is same as raw (xcpretty will be added later)
        try {
          await writeFile(prettyLogPath, rawLogContent, 'utf-8');
        } catch (error) {
          console.error(`Failed to save pretty log: ${error}`);
        }

        // Extract errors (basic extraction for now)
        const errors = this.extractErrors(stdoutContent + stderrContent);

        const result: XcodeBuildResult = {
          success: code === 0,
          exitCode: code ?? 1,
          stdout: stdoutContent,
          stderr: stderrContent,
          rawLogPath,
          prettyLogPath,
          errors: errors.length > 0 ? errors : undefined,
        };

        resolve(result);
      });

      xcodebuild.on('error', async (error) => {
        // Handle spawn errors (e.g., xcodebuild not found)
        const errorMessage = `Failed to spawn xcodebuild: ${error.message}`;
        
        try {
          await writeFile(rawLogPath, errorMessage, 'utf-8');
        } catch {}

        resolve({
          success: false,
          exitCode: 1,
          stdout: '',
          stderr: errorMessage,
          rawLogPath,
          prettyLogPath,
          errors: [errorMessage],
        });
      });
    });
  }

  private buildCommandArgs(options: XcodeBuildOptions): string[] {
    const args: string[] = [];

    if (options.workspace) {
      args.push('-workspace', options.workspace);
    } else if (options.project) {
      args.push('-project', options.project);
    }

    if (options.scheme) {
      args.push('-scheme', options.scheme);
    }

    if (options.configuration) {
      args.push('-configuration', options.configuration);
    }

    if (options.platform === 'ios-sim') {
      args.push('-sdk', 'iphonesimulator');
      if (options.simulator) {
        args.push('-destination', `platform=iOS Simulator,name=${options.simulator}`);
      } else {
        // Use generic destination - xcodebuild will pick an available simulator
        args.push('-destination', 'generic/platform=iOS Simulator');
      }
    } else if (options.platform === 'ios-device') {
      args.push('-sdk', 'iphoneos');
      if (options.device) {
        args.push('-destination', `generic/platform=iOS,id=${options.device}`);
      }
    } else if (options.platform === 'macos') {
      args.push('-sdk', 'macosx');
      args.push('-destination', 'platform=macOS');
    }

    if (options.derivedDataPath) {
      args.push('-derivedDataPath', options.derivedDataPath);
    }

    if (options.clean) {
      args.push('clean');
    }

    args.push('build');

    return args;
  }

  private extractErrors(output: string): string[] {
    const errors: string[] = [];
    const errorRegex = /error:\s*(.+)/gi;
    let match;

    while ((match = errorRegex.exec(output)) !== null) {
      const errorLine = match[1]?.trim();
      if (errorLine && !errors.includes(errorLine)) {
        errors.push(`error: ${errorLine}`);
      }
    }

    return errors;
  }
}
