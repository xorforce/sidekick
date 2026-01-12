/**
 * Test fixtures for xcodebuild outputs
 */

export const successfulBuildOutput = `
=== BUILD TARGET MyApp OF PROJECT MyApp WITH CONFIGURATION Debug ===

Check dependencies
Compile Sources
Link Binary
Code Sign
Build succeeded
`;

export const failedBuildOutput = `
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

export const xcprettyFormattedErrors = `
❌  /path/to/file.swift:10:5: error: use of unresolved identifier 'undefinedVar'
    undefinedVar = 5
    ^

❌  /path/to/file.swift:15:8: error: cannot find 'SomeType' in scope
    let x: SomeType = ...
           ^

2 errors found
`;

export const xcodebuildRawLog = `xcodebuild: error: The workspace "MyApp.xcworkspace" does not exist.
`;
