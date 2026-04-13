---
id: code-review
title: Code Review
description: Review code changes for quality consistency and correctness
trigger: review refactor cleanup improve optimize pr
---

# Code Review

1. Verify every change directly serves the stated objective. Remove unrelated modifications.
2. Check consistency with existing project patterns, naming conventions, and architectural decisions.
3. Identify and eliminate duplicated logic. Extract shared behavior into reusable functions or modules.
4. Confirm all error paths are handled. Functions that can fail must have explicit error handling.
5. Use clear, descriptive names for all variables, functions, and files. Avoid abbreviations unless they are project-standard.
6. Watch for unintended side effects: global state mutations, file system changes, or network calls that are not part of the task.
7. Ensure comments explain why, not what. Remove comments that merely restate the code.
8. Verify no existing interfaces are broken. Check that function signatures, return types, and API contracts remain compatible.
