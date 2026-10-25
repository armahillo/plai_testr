# Changelog

## Development

## 0.2.1

- Docs reorganized: the README is an overview linking to guides in `docs/` (getting started, ingesting a game with an agent or manually, running playtests) and a technical reference in `docs/technical/`.
- The Gin Rummy example reads its deck from `data/components/cards.csv`, like Hearts.
- `new` stamps each example game with its template checksum (`games/<name>/.plai_testr.yml`), so a later update can tell an untouched example (safe to replace) from an edited one (the new version goes alongside).
- Play and botrun reports show the wall time; a resumed session adds each sitting.

## 0.2.0

Upgrading never breaks a game: every new hook has a default, and existing overrides keep working. See *Upgrading an existing app* below.

### Agent guide

- The agent guide moved into the gem (`docs/AGENTS.md`). Each app links to the installed gem at `.plai_testr/gem` (created by `new`, refreshed by every command and the app's spec_helper, copied where symlinks are unavailable) and its `CLAUDE.md` imports `@.plai_testr/gem/docs/AGENTS.md`, so upgrading the gem upgrades the guide. The app's own `AGENTS.md` is now a short file for app-specific notes.
- The guide gained *What the gem already does* and *Debrief* sections.

### Debrief

- Debrief prompts open with a summary the gem builds for each player (`debrief_summary`): the outcome, game facts, the player's own decisions, and its plan each time it changed. Answers must come from the summary and cite the round.
- New hook `debrief_facts(player)`: engine-counted facts for the debrief, as a Hash (default: `botrun_stats`). `check!` warns when a game has neither; preflight builds every player's debrief after its lint games.
- `debrief <session_id> [--model M] [--think]` re-asks a completed session's players and rebuilds its report; earlier answers stay under `debrief_history`.
- `play --debrief-model M --debrief-think`: a separate model and thinking for the debrief. The report names the model that answered.

### Less code per game

- Gem defaults replace code every game repeated: `rules_text_for` reads `data/rules.md` (call `super` to extend it); `recent_events_for` takes its count from `register(..., recent_events:)`; `debrief_view_for` shows the result, scores, view and the player's visible log; `log_turn` / `log_turn_name` set the number stamped on log entries; private helpers `players`, `pstate`, `whose`, `tally`, `sole_leader`.
- `GameState#data_for` now shows each player only the log entries meant for them by default (it showed the whole log). Extend it with `super.except('deck')`.
- `require 'plai_testr/rspec'` and `it_behaves_like 'a PlAI Testr game', '<name>'`: the standard checks every game runs. At every player count, bot games reach an ending, every turn and debrief prompt builds, state survives a JSON round trip, a mid-game resume gives the same result, and no player sees another's hand.
- `generate game` creates a slimmer skeleton: only the hooks a game must write, with a comment listing what the gem provides; its spec runs the standard checks. The examples use the defaults and the standard checks, and implement `debrief_facts`.

### Other

- `plai_testr help`, `games` and `--version`; every command takes `--help` and refuses options it doesn't take.
- Components load from `data/components/*.{csv,yml,json}`, one file per component; `generate game` creates a placeholder.

### Upgrading an existing app

1. `.gitignore`: add `.plai_testr/`.
2. `spec/spec_helper.rb`: add `require 'plai_testr/rspec'` after `require 'plai_testr'`, and `PlaiTestr::Guide.link` after setting `games_dir`.
3. `CLAUDE.md`: add `@.plai_testr/gem/docs/AGENTS.md`. Move app-specific notes from the old copy of the guide into `AGENTS.md`, then delete the rest of the copy.
4. Each game's spec: add `it_behaves_like 'a PlAI Testr game', '<name>'`, then delete specs it now covers (a "builds every prompt" spec, plain botrun specs).
5. Each game: implement `debrief_facts` (see the guide's *Debrief* section), and delete overrides that only repeat a gem default (`rules_text_for` reading `rules.md`, `recent_events_for`, `debrief_view_for`, the log filter in `data_for`, `players`, `pstate`, `whose`, `tally`).
6. Run `bundle exec rspec`.

## 0.1.1 (2026-10-23)

First public release.

- `plai_testr new` creates a playtesting app with two example games (Hearts, Gin Rummy); `plai_testr generate game` adds a game skeleton.
- `play` runs one model game with preflight checks; `botrun` plays many bot-only games and reports balance; `resume`, `compare`, `list` and `preflight` round it out.
- Games list their legal moves as a numbered menu; the model picks one. Bot rules can play obvious moves (hybrid mode) or every move (bot mode).
- Personas (`personas.yml`) and bot parameters (`bots.yml`) per game.
- Checkpoints after every decision; resume refuses sessions whose game has changed.
- Configurable decision limit and model settings in `config/plai_testr.rb`.
