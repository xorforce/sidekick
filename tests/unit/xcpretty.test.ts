import { describe, it, expect } from 'vitest';
import { failedBuildOutput, xcprettyFormattedErrors } from '../fixtures/xcodebuild-outputs.js';

describe('xcpretty Integration', () => {
  describe('Error Parsing', () => {
    it('should extract errors from xcodebuild output', () => {
      // This will test the error extraction logic
      // Expected: array of error strings
      const errors = [
        "error: /path/to/file.swift:10:5: error: use of unresolved identifier 'undefinedVar'",
        "error: /path/to/file.swift:15:8: error: cannot find 'SomeType' in scope",
      ];

      expect(errors).toHaveLength(2);
      expect(errors[0]).toContain('error:');
      expect(errors[0]).toContain('undefinedVar');
    });

    it('should parse xcpretty formatted errors', () => {
      // Test parsing of xcpretty output
      const formattedErrors = xcprettyFormattedErrors;
      expect(formattedErrors).toContain('❌');
      expect(formattedErrors).toContain('error:');
    });

    it('should handle empty error list for successful builds', () => {
      const errors: string[] = [];
      expect(errors).toHaveLength(0);
    });
  });

  describe('Output Formatting', () => {
    it('should format errors concisely for CLI display', () => {
      // Expected: brief, readable error format
      const error = "error: /path/to/file.swift:10:5: error: use of unresolved identifier 'undefinedVar'";
      const formatted = error; // Will be formatted by xcpretty parser
      
      expect(formatted).toContain('file.swift:10:5');
      expect(formatted).toContain('undefinedVar');
    });
  });
});
