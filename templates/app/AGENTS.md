# Agent guide

This app playtests tabletop games with [PlaiTester](https://github.com/armahillo/plai_testr). Local LLM players (via Ollama) and scripted bots play a game; every session produces a markdown report for the designer. If you are an AI assistant helping build or change a test harness here, read this first.

## Start here

When you open this project:

1. Read this file, then `README.md`.
2. Run `bundle exec rspec`. It is fast, needs no model, and shows the state of every game.
3. Look at `games/`. Each game's `data/rules.md` is its rulebook, and `NOTES.md` (if present) holds rulings and open questions.
4. Read the gem's docs when you need them. They ship with the installed gem, so they match the version in use; `bundle info plai_tester --path` prints its directory:
   - `README.md`: every runner hook, the state classes, configuration
   - `docs/frame_queue.md`: decisions inside decisions (attacks and responses, triggered effects), with a complete example
   - `docs/referee.md`: yes/no rulings on free-text conditions by a second model, with an example
   - `templates/examples/`: pristine copies of the example games, in case they were deleted from `games/`

The example games show working patterns to copy:

- `games/hearts`: 4 players, hidden hands, a pick-3 pass (`pick_range`), a session report section (`report_sections`), and a botrun report subclass (`botrun_stats` + `Reporter::BotrunReport`)
- `games/gin_rummy`: 2 players, engine-computed facts on every option, melds computed in plain Ruby (`melds.rb`), personas (`data/personas.yml`, `persona_for`), and a **Simplifications** section in `data/rules.md`

## Who you are working for

The user is a game designer. The harness exists to tell them how their game plays, so:

- Never change the game's rules to make the harness easier. When the rules are unclear or silent, ask the designer and record the answer (see *Rulings*).
- Ask before running model games (`start`, `batch`, `bin/playtest`) or pulling models: they take minutes to hours and use the machine. Specs and `botrun` are fast and safe to run.
- Bot results describe how the bot plays, not how people play. Say so when reporting them.

## Layout

```
games/<name>/
  lib/<name>.rb             Requires the game and calls PlaiTester.register
  lib/<name>/game.rb        Constants
  lib/<name>/state/         GameState (and PlayerState) subclasses: what is stored, what each player may see
  lib/<name>/session/runner.rb   The rules engine: steps, legal moves, effects, views, prompts
  lib/<name>/session/policy.rb   Bot rules (scripted_choice)
  lib/<name>/reporter/      Optional report classes
  data/rules.json           Machine-readable rules: game name, version, player_count, card_deck, numbers the engine uses
  data/rules.md             Rules text the model players read
  NOTES.md                  Optional: open questions and unconfirmed engine choices
  spec/                     The game's specs
  sessions/ reports/        Output (gitignored)
```

Every file a game needs lives under `games/<name>/`, so a game is removed by deleting its directory. Keep it that way. Shared code goes in the plai_tester gem, not in another game.

`bundle exec plai_tester generate game <name>` creates the skeleton. `games/hearts` (4 players, hidden hands, a pick-3 pass) and `games/gin_rummy` (2 players, draw/discard turns, engine-computed melds) are complete examples.

## How a game runs

Each turn the runner asks `next_player` who acts, builds a numbered menu from `legal_moves(player)`, and the player (model or bot) picks a number. `apply_action_effects` applies the chosen move's `action` to `@game_state`. The game ends when `flags['game_over']` is true; set `flags['winner']` and `flags['end_reason']` too.

A move is `{ 'label' => text the player sees, 'public' => what other players see, 'log' => short console text, 'action' => { 'action' => name, 'parameters' => {...} } }`. A menu with one move is applied without asking anyone. `pick_range(player)` returning `[min, max]` turns the menu into a pick-N choice, applied as `parameters['values']` (each move's `parameters['value']`).

The gem's `README.md` (see *Start here*) lists every hook.

## Building a harness: the order that works

1. **Rules first.** Put the rules text in `data/rules.md` and the numbers in `data/rules.json`. Read them closely; list every gap or ambiguity and ask the designer before coding around it.
2. **State.** Decide what lives in `@game_state.custom` (decks, piles, step, active player, a `log` array). Use stable ids (card `uid`s, fixed pile indexes); never re-index things players refer to.
3. **Steps.** Model a turn as a small state machine in `custom['step']`. `legal_moves` and `apply_action_effects` switch on it.
4. **Specs for the rules.** Before any model plays, write specs that set up a situation and check the menu (`legal_moves`) and the effects. This is where rules bugs are cheapest.
5. **Bot rules.** Implement `scripted_choice` so the game can play itself. Then `bundle exec plai_tester <game> botrun --games 1000` must finish with no crashes and sensible endings. Add a botrun spec over a few seeds.
6. **Views and prompts.** Write `view_text_for`, `rules_text_for`, `turn_phase`, `debrief_questions`. Read a few prompts yourself (see *Checking a prompt*).
7. **Model games.** With the designer's go-ahead: one game with `--mode hybrid` (the bot plays obvious moves), then `--mode llm`.

## Designing what the model sees

Small local models (4B–14B) play well only when the engine does the bookkeeping.

- **The engine lists the legal moves; the model picks a number.** Never ask the model to name a card, type a move, or check legality.
- **Put engine-computed facts on each option, never advice.** "Discard 9♥ (deadwood after: 31)" is a fact; "Discard 9♥ (best)" decides for the model and ruins the test.
- **Generate views from state; never hand-write summaries.** Hand-written summaries leak hidden information or go stale.
- **Show each player only what they may know.** Override `custom_for(observer)` in GameState (and `serialize_for` in PlayerState) to hide decks and other hands. Use `PlaiTester::EventLog` with `to:` for private events ("You drew the 2♠").
- **Keep menus short.** Merge equivalent options (identical cards, interchangeable targets). Split one huge decision into steps.
- **Hide safety caps from players.** Turn or hand limits that stop runaway games (`MAX_HANDS`) must not appear in views or rules text, or models play for the cap.
- **Scope long rules.** If `rules.md` is long, `rules_text_for` can send only the sections the current step needs.
- **Personas** (optional): `persona_for(player)` adds a path to victory and play style to the system prompt. List names in `self.persona_names` so `botrun --personas all` can cycle every arrangement; it needs at least as many personas as seats. Let the bot policy read the persona too, so botruns compare styles (see `games/gin_rummy`).

## Reports

- `report_sections` adds markdown sections to each session report: game-specific tallies the designer cares about.
- `botrun_stats` returns numbers for one bot game; a `PlaiTester::Reporter::BotrunReport` subclass (registered as `botrun_report_class:`) turns them into sections with `extra_sections`. See `games/hearts`.
- Keep the counters in `@game_state.custom` so they survive checkpoints and resume.

## Bot rules

`scripted_choice(player, moves, pick: nil)` returns `nil` or `{ 'choice' => n, 'rule' => 'name', 'obvious' => bool }` (`'choices' => [...]` for pick-N).

- Mark a rule `obvious` only when the move is never worse than any alternative. `--mode hybrid` plays obvious moves without calling the model, and the report scores the model against them.
- Name rules after the idea (`duck`, `dump_queen`, `shed_deadwood`); the botrun report counts them.
- Keep the bot simple and readable. It is a baseline and a crash test, not a strong player.

## Rulings and simplifications

- When the designer settles a rules question, add it to a **Rulings** section in `data/rules.md` (dated), so models and future readers see it.
- When the harness deliberately simplifies a rule, list it in a **Simplifications** section in `data/rules.md` (see `games/gin_rummy`).
- Keep open questions and engine choices the designer has not confirmed in `games/<name>/NOTES.md`, marked as unconfirmed, and move them into **Rulings** once settled.

## Specs

- Unit specs drive the runner directly: build it with `mode: 'bot', persist: false`, call `setup`, arrange the state, and check `legal_moves` or the effects of `apply_action_effects`. The examples' `spec/` folders show the pattern.
- Every game keeps a botrun spec: a handful of seeds, no crashes, a winner every time.
- If `data/` is copied from another repository, add a spec that fails when the copy is behind.
- `bundle exec rspec` runs every game; `bundle exec rspec games/<name>` runs one.

## Checking a prompt

```ruby
# bundle exec ruby -e '...'
require 'plai_tester'
game   = PlaiTester.load('hearts')
rules  = PlaiTester::Compiler::RulesLoader.load(game.rules_file)
runner = game.runner_class.new(rules: rules, players: game.players, models: {}, game_state_class: game.game_state_class, seed: 1, mode: 'bot', persist: false)
runner.send(:setup)
5.times { runner.send(:play_turn) }
player = runner.send(:next_player)
puts runner.send(:view_text_for, player), runner.send(:legal_moves, player).map { |m| m['label'] }
```

## Commands

```
bundle exec plai_tester <game> botrun --games 1000 [--personas all]    Bots only; report in games/<game>/reports/
bundle exec plai_tester <game> start --seed 1 [--mode hybrid]          One model game (ask first)
bundle exec plai_tester <game> batch --seeds 1,2,3                     Several model games (ask first)
bundle exec plai_tester <game> resume <session_id>
bundle exec plai_tester <game> compare | list | preflight
bin/playtest <game> [quick|thorough]                                   Full unattended run (ask first)
bundle exec plai_tester generate game <name>
bundle exec rspec
```
