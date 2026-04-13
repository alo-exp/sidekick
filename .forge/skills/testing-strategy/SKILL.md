---
id: testing-strategy
title: Testing Strategy
description: Guide test creation and ensure adequate coverage
trigger: test spec coverage unit integration assert expect
---

# Testing Strategy

1. Write tests before implementing the feature. Define expected behavior first, then write the code to satisfy it.
2. Test one behavior per test case. Each test should have a single reason to fail.
3. Cover edge cases: empty input, null values, boundary conditions, maximum lengths, and unexpected types.
4. Verify exit codes for all shell scripts and command-line tools. Non-zero exit codes must indicate failure.
5. Test file operation error cases: missing files, permission denied, disk full, and invalid paths.
6. Keep tests independent. No test should depend on the outcome or side effects of another test.
7. Run the full test suite after every change. A single failing test blocks the commit.
8. Write clear assertion messages that describe what was expected and what was received.
