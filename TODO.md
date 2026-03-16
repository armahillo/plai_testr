# PlaiTester TODO

## Random::Engine wiring

_Completed. `Runner` owns `@random`, has a `setup` hook, and handles `random_ops` in referee responses._

## Runner improvements

- Add a `setup` phase to `Runner` that runs before the game loop: calls `Random::Engine` to shuffle and deal, then populates initial state before handing off to agents
- `available_actions` passed to `PlayerAgent` currently contains all actions from the rules regardless of game phase or context — should be filtered to only legal actions for the current state

## State layer

- `GameState#apply_changes` uses `merge!` for `@custom`, which replaces array values wholesale — for pile operations `Runner` should call discrete `PlayerState` methods directly rather than routing through `apply_changes`

## Custom game implementation (separate project)

- Wire `Custom::State::GameState` into `Runner` via `game_state_class: Custom::State::GameState`
- Determine whether `RefereeAgent` and `PlayerAgent` need Custom-specific subclasses for prompt shaping, or whether the base prompts are sufficient
- Establish the game-specific action protocol: what the referee response vocabulary looks like for Custom-specific state changes (stance pile ops, aggressor transfer, phase transitions)

## Gemspec / publishing

- Add `spec.homepage` to `plai_tester.gemspec` before publishing to RubyGems
