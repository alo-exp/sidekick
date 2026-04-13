---
id: security
title: Security Review
description: Check for common security issues in code changes
trigger: security auth credential secret password token api-key encrypt
---

# Security Review

1. Never hardcode secrets, API keys, passwords, or tokens in source files. Use environment variables or dedicated credential stores.
2. Store all sensitive configuration values in environment variables. Reference them by name, never by value.
3. Verify `.gitignore` includes credential files, `.env` files, key files, and any other sensitive artifacts.
4. Validate and sanitize all external input before processing. Assume all user-provided data is untrusted.
5. Ensure error messages and logs do not leak internal details such as stack traces, file paths, database schemas, or credentials.
6. Restrict file permissions on credential files to owner-only access (mode 600 or equivalent).
7. Never log sensitive data including API keys, passwords, tokens, or personally identifiable information.
