#!/usr/bin/env node

import { Command } from 'commander';
import { buildCommand } from '../commands/build.js';
import { MockXcodeBuild } from '../exec/mock-xcodebuild.js';

const program = new Command();

program
  .name('sidekick')
  .description('A quirky CLI for building, running, and testing iOS/macOS apps')
  .version('0.1.0');

// Placeholder commands - will be implemented in future tasks
program
  .command('init')
  .description('Interactive first-time setup')
  .action(() => {
    console.log('init command - coming soon');
  });

program
  .command('build')
  .description('Build for simulator, device, or macOS')
  .option('--profile <name>', 'Use named profile')
  .option('--platform <type>', 'Platform: ios-sim, ios-device, macos')
  .option('--clean', 'Clean before building')
  .option('--no-quirk', 'Disable quirky progress messages')
  .action(async (options) => {
    // Use mock exec wrapper for now
    const execWrapper = new MockXcodeBuild();
    
    await buildCommand({
      profile: options.profile,
      platform: options.platform,
      clean: options.clean,
      noQuirk: options.noQuirk,
      execWrapper,
    });
  });

program
  .command('run')
  .description('Build and launch app')
  .option('--profile <name>', 'Use named profile')
  .option('--args <args...>', 'Arguments to pass to app')
  .action(() => {
    console.log('run command - coming soon');
  });

program
  .command('test')
  .description('Run tests')
  .option('--profile <name>', 'Use named profile')
  .option('--filter <pattern>', 'Filter tests by pattern')
  .option('--retry', 'Retry failed tests')
  .action(() => {
    console.log('test command - coming soon');
  });

program
  .command('context')
  .description('Show project context (schemes, configs, sims, devices)')
  .action(() => {
    console.log('context command - coming soon');
  });

program
  .command('profile')
  .description('Manage named profiles')
  .action(() => {
    console.log('profile command - coming soon');
  });

program
  .command('logs')
  .description('Show or tail saved logs')
  .option('--json', 'Output as JSON')
  .action(() => {
    console.log('logs command - coming soon');
  });

program
  .command('stop')
  .description('Stop running app session')
  .action(() => {
    console.log('stop command - coming soon');
  });

program
  .command('sim')
  .description('Simulator helpers')
  .action(() => {
    console.log('sim command - coming soon');
  });

program.parse();
