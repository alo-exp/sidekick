---
id: quality-gates
title: Quality Gates
description: Enforce code quality standards before committing changes
trigger: test lint commit quality review push
---

# Quality Gates

1. Run the full test suite before declaring any task complete. Do not skip tests even for "trivial" changes.
2. Run the project linter if configured. Fix all warnings and errors before committing.
3. Search for TODO and FIXME comments in changed files. Resolve them or document why they must remain.
4. Verify no debug statements (console.log, print, debugger, binding.pry) exist in committed code.
5. Confirm all functions, variables, and files use descriptive names consistent with the project's existing conventions.
6. Run the full test suite one final time before pushing. All tests must pass with zero failures.
7. Verify commit messages follow the project's convention (check recent git log for the pattern).
