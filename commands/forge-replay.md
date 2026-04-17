---
name: forge-replay
description: Replay a past Forge task as an HTML transcript using the conversation UUID from .forge/conversations.idx.
argument-hint: <conversation-id>
---

# /forge:replay <conversation-id>

Open a Forge conversation as an HTML transcript and show token/cost stats.

## Procedure

1. Validate that `$ARGUMENTS` matches the RFC 4122 UUID regex `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`. If not, tell the user: "Expected a lowercase UUID. Use `/forge:history` to find the UUID for a past task."

2. Generate the HTML transcript:

   ```
   forge conversation dump "$ARGUMENTS" --html > /tmp/forge-replay-"$ARGUMENTS".html
   ```

3. Open the HTML in the default browser (platform-dependent):

   - macOS: `open /tmp/forge-replay-"$ARGUMENTS".html`
   - Linux: `xdg-open /tmp/forge-replay-"$ARGUMENTS".html`

4. Show token/cost stats inline in the Claude turn:

   ```
   forge conversation stats "$ARGUMENTS" --porcelain
   ```

   Render the porcelain output as a compact summary (tokens in/out, total cost) rather than dumping raw key=value lines.

## Failure modes

- `forge conversation dump` exits non-zero → the conversation ID does not exist in `~/forge/.forge.db`. Tell the user the ID was not found and suggest `/forge:history` to browse valid IDs.
- Browser-open command fails → report the path to the HTML file and let the user open it manually.
- The `forge` binary is not on PATH → this should not happen when `/forge` mode is active (activation health-checks it), but if it does, direct the user to re-run `/forge`.
