# PLAI_TESTR

PlAI Testr is a Ruby gem for playtesting tabletop games with local LLM players (Ollama) and scripted bots. A game lists its legal moves as a numbered menu; a model or bot picks one; the gem applies it, checkpoints, and writes markdown reports.

Third parties install the gem, run `plai_testr new <dir>` to get an app with example games, and build harnesses for their own games, often by letting their own coding agent follow the generated `AGENTS.md`. This repository is the gem, not an app.

## Names

| Where | Name |
|---|---|
| GitHub repo, gem, executable | `plai_testr` |
| Ruby module | `PlaiTestr` |
| Environment variables | `PLAI_TESTR_*` (e.g. `PLAI_TESTR_PLAYER_MODEL`, `PLAI_TESTR_DEBUG`) |
| Prose | PLAI_TESTR, or "PlAI Testr" written out |

## Layout

```
lib/plai_testr.rb               Requires everything; games_dir / sessions_dir / reports_dir
lib/plai_testr/
  session/runner.rb             The decision loop and every game hook (the public API games build on)
  session/frame_queue.rb        Optional stack of nested decisions
  session/manager.rb            Checkpoints (atomic), transcripts, session ids
  agents/                       Ollama client, player prompts (menu, pick-N, debrief), referee
  state/                        GameState (turn, status, data, player_states) and PlayerState
  reporter/                     Session report, botrun report, model comparison, think log
  cli.rb  preflight.rb  botrun.rb
  game.rb                       PlaiTestr.register / load, Game (rules, personas, fingerprint, check!)
  personas.rb                   personas.yml + bots.yml
  config.rb  model_settings.rb  errors.rb  rules_loader.rb  deck.rb  event_log.rb  names.rb  generator.rb
templates/app/                  What `plai_testr new` copies (AGENTS.md is the guide for the app's agent)
templates/game/                 What `plai_testr generate game` copies (ERB)
templates/examples/             Hearts and Gin Rummy: complete games, copied into every new app
docs/                           frame_queue.md, referee.md (shipped with the gem)
spec/                           Gem specs; spec/support/test_game.rb builds a throwaway game on disk
```

## Working here

- `bundle exec rspec` runs the gem specs, including one that generates an app and runs the example games' specs. It needs no model.
- The example games are part of the product: users copy their patterns, so keep them idiomatic and current with the API. Changing a hook, move shape or state key means updating `templates/examples/`, `templates/game/`, `templates/app/AGENTS.md`, the docs and `README.md` together.
- Hooks on `Session::Runner` are public and form the stable API; internals are private. Don't add a public method a game could collide with (games commonly define helpers like `step`, `players`, `hand`).
- Raise `PlaiTestr::Error` subclasses (`RulesError`, `PersonaError`, `SessionError`, `ModelError`, `UsageError`, `MoveError`) for anything a user can cause. The CLI prints their message; `PLAI_TESTR_DEBUG=1` shows the backtrace.
- Output goes through `out` (an IO passed in), never bare `puts` or a swapped `$stdout`, so botruns and specs can silence it.
- Randomness in games comes from `@rng`, reseeded per decision from the seed and decision number. Don't add other sources of randomness to the decision path.
- `../game-testrs` is a separate app that uses this gem through a path gem; check it when changing the public API.
- Bump `lib/plai_testr/version.rb` and add a `CHANGELOG.md` entry for releases. A changed version invalidates saved sessions (resume compares a fingerprint that includes it).

## Conventions

- Ruby 3.2+. Keep code readable for people who don't know Ruby: plain hashes with string keys for game data, no metaprogramming in the game-facing API.
- Specs test public behaviour; build runners with `build_game` from `spec/support/test_game.rb`.
- Don't commit; the maintainer handles git.
