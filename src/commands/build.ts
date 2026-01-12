/**
 * Build command implementation
 */

import chalk from 'chalk';
import ora, { type Ora } from 'ora';
import type { ExecWrapper, XcodeBuildOptions } from '../exec/xcodebuild.js';

export interface BuildCommandOptions {
  profile?: string;
  workspace?: string;
  project?: string;
  scheme?: string;
  configuration?: string;
  platform?: 'ios-sim' | 'ios-device' | 'macos';
  clean?: boolean;
  noQuirk?: boolean;
  execWrapper: ExecWrapper;
}

const QUIRKY_MESSAGES = ['🍪', '☕', '🍕', '🍩', '🥤'];
const NORMAL_MESSAGES = ['Building', 'Compiling', 'Linking', 'Signing'];

function getSpinnerMessage(step: number, noQuirk: boolean): string {
  if (noQuirk) {
    return NORMAL_MESSAGES[step % NORMAL_MESSAGES.length];
  }
  const quirk = QUIRKY_MESSAGES[step % QUIRKY_MESSAGES.length];
  const message = NORMAL_MESSAGES[step % NORMAL_MESSAGES.length];
  return `${message} ${quirk}`;
}

export async function buildCommand(options: BuildCommandOptions): Promise<void> {
  const { 
    execWrapper, 
    workspace, 
    project, 
    scheme, 
    configuration, 
    platform, 
    clean, 
    noQuirk = false 
  } = options;
  // profile will be used when profile loading is implemented
  // const { profile } = options;

  // Build options for exec wrapper
  const buildOptions: XcodeBuildOptions = {
    workspace,
    project,
    scheme: scheme || 'clavis', // Default scheme if not provided
    configuration: configuration || 'Debug', // Default to Debug
    platform,
    clean,
    derivedDataPath: undefined, // TODO: Load from profile
  };

  // Create spinner with quirky message
  let spinner: Ora | null = null;
  let step = 0;

  const updateSpinner = () => {
    if (spinner) {
      spinner.text = getSpinnerMessage(step, noQuirk);
      step++;
    }
  };

  try {
    spinner = ora({
      text: getSpinnerMessage(0, noQuirk),
      color: 'cyan',
    }).start();

    // Simulate progress updates
    const progressInterval = setInterval(() => {
      updateSpinner();
    }, 500);

    // Execute build
    const result = await execWrapper.build(buildOptions);

    clearInterval(progressInterval);

    if (result.success) {
      spinner.succeed(chalk.green('✅ Build succeeded'));

      // Show log paths
      if (result.rawLogPath || result.prettyLogPath) {
        console.log('\n' + chalk.dim('Logs saved to:'));
        if (result.rawLogPath) {
          console.log(chalk.dim(`  Raw: ${result.rawLogPath}`));
        }
        if (result.prettyLogPath) {
          console.log(chalk.dim(`  Pretty: ${result.prettyLogPath}`));
        }
      }
    } else {
      spinner.fail(chalk.red('❌ Build failed'));

      // Show errors
      if (result.errors && result.errors.length > 0) {
        console.log('\n' + chalk.red('Errors:'));
        result.errors.forEach(error => {
          console.log(chalk.red(`  ${error}`));
        });
      }

      // Show log path
      if (result.rawLogPath) {
        console.log('\n' + chalk.dim(`See full log: ${result.rawLogPath}`));
      }

      process.exit(result.exitCode);
    }
  } catch (error) {
    if (spinner) {
      spinner.fail(chalk.red('Build error'));
    }
    console.error(chalk.red(`Error: ${error instanceof Error ? error.message : String(error)}`));
    process.exit(1);
  }
}
