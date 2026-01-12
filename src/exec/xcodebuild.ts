/**
 * Exec wrapper interface for xcodebuild commands
 */

export interface XcodeBuildOptions {
  workspace?: string;
  project?: string;
  scheme?: string;
  configuration?: string;
  platform?: 'ios-sim' | 'ios-device' | 'macos';
  simulator?: string;
  device?: string;
  derivedDataPath?: string;
  clean?: boolean;
}

export interface XcodeBuildResult {
  success: boolean;
  exitCode: number;
  stdout: string;
  stderr: string;
  rawLogPath?: string;
  prettyLogPath?: string;
  errors?: string[];
}

export interface ExecWrapper {
  build(options: XcodeBuildOptions): Promise<XcodeBuildResult>;
}
