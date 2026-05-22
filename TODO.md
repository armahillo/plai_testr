# PlaiTester TODO

## Thinking output

- Capture `<think>...</think>` content from referee (and optionally player) responses into the session transcript
- Approach: accumulate extracted thinking in `@last_thinking` on `RefereeAgent`; after each referee call in `Runner`, fold it into the transcript entry under a `"referee_thinking"` key
- Player agents would need the same treatment if a thinking-capable model is used for players

## Gemspec / publishing

- Fill in `spec.homepage` in `plai_tester.gemspec` before publishing to RubyGems
