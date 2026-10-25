# PlAI Testr agent guide

PlAI Testr playtests tabletop games: local LLM players (via Ollama) and scripted bots play a game, and every session produces a markdown report for the designer. If you are an AI assistant helping build or change a test harness in a PlAI Testr app, read this first.

This guide ships with the gem. An app reaches it through `.plai_testr/gem`, a link to the installed gem that every `plai_testr` command and spec run keeps current, and its `CLAUDE.md` imports it with `@.plai_testr/gem/docs/AGENTS.md`. The app's own `AGENTS.md` holds only what is specific to that app. Put gem-wide guidance here, in the gem, not in an app.

## Start here

When you open an app:

1. Read the app's `AGENTS.md` and `README.md`.
2. Run `bundle exec rspec`. It is fast, needs no model, shows the state of every game, and refreshes `.plai_testr/gem`.
3. Look at `games/`. Each game's `data/rules.md` is its rulebook, and `NOTES.md` (if present) holds rulings and open questions.
4. Read the gem's docs when you need them, under `.plai_testr/gem/` (they match the installed version):
   - `README.md`: every runner hook, the state classes, configuration
   - `docs/frame_queue.md`: decisions inside decisions (attacks and responses, triggered effects), with a complete example
   - `docs/referee.md`: yes/no rulings on free-text conditions by a second model, with an example
   - `templates/examples/`: pristine copies of the example games, in case they were deleted from `games/`

The example games show working patterns to copy:

- `games/hearts`: 4 players, hidden hands, a pick-3 pass (`pick_range`), a session report section (`report_sections`), a botrun report subclass (`botrun_stats` + `Reporter::BotrunReport`), debrief facts (`debrief_facts`), and personas whose bots play differently (`lib/hearts/bot.rb`, `data/personas.yml`, `data/bots.yml`)
- `games/gin_rummy`: 2 players, engine-computed facts on every option, melds computed in plain Ruby (`melds.rb`), a bot (`lib/gin_rummy/bot.rb`) with a per-persona parameter (`knock_at` in `data/bots.yml`), and a **Simplifications** section in `data/rules.md`

## Who you are working for

The user is a game designer. The harness exists to tell them how their game plays, so:

- Never change the game's rules to make the harness easier. When the rules are unclear or silent, ask the designer and record the answer (see *Rulings*).
- Ask before running model games (`play`, `resume`, `preflight`, `debrief`) or pulling models: they take minutes to hours and use the machine. Specs and `botrun` are fast and safe to run.
- Debrief answers are model opinions, and small models invent details. Check a claim against the game facts or the turn log before passing it on to the designer.
- Bot results describe how the bot plays, not how people play. Say so when reporting them.

## Layout

```
games/<name>/
  lib/<name>.rb             Requires the game and calls PlaiTestr.register
  lib/<name>/game.rb        Constants
  lib/<name>/state/         GameState (and PlayerState) subclasses: what is stored, what each player may see
  lib/<name>/session/runner.rb   The rules engine: steps, legal moves, effects, views, prompts
  lib/<name>/bot.rb         Bot rules (bot_choice), included in the runner
  lib/<name>/reporter/      Optional report classes
  data/rules.json           Machine-readable rules: game name, version, player_count, numbers the engine uses
  data/components/          Card lists and other components: one file per component (.csv, .yml or .json)
  data/rules.md             Rules text the model players read
  data/personas.yml         Optional: shared strategy and play styles the model players follow
  data/bots.yml             Optional: parameters the bot reads, per persona
  NOTES.md                  Optional: open questions and unconfirmed engine choices
  spec/                     The game's specs
  sessions/ reports/        Output (gitignored)
```

Every file a game needs lives under `games/<name>/`, so a game is removed by deleting its directory. Keep it that way. Shared code goes in the plai_testr gem, not in another game.

App-wide settings (the decision limit backstop, model, Ollama host, model settings) live in `config/plai_testr.rb`. A game can set its own `max_decisions:`, `model_settings:` and `recent_events:` (how many log lines each turn prompt shows) in `PlaiTestr.register`.

## What the gem already does

Anything every game needs lives in the gem, so a gem upgrade reaches every game without editing it. Before writing a hook or helper, check that the gem doesn't already provide it, and don't copy gem behavior into a game:

- `rules_text_for` reads the game's `data/rules.md`. Override it only to scope the rules to a step or to append generated text, calling `super` for the file.
- `recent_events_for` shows the last events the player may see (`recent_events:` in `register` sets how many).
- `debrief_view_for` shows the result, final scores, `view_text_for` and the player's visible log. `debrief_summary` (outcome, game facts, the player's decisions and plans) always comes first.
- `GameState#data_for` shows each player only the log entries meant for them. Hide more with `super.except('deck').merge('deck_size' => ...)`.
- `log_turn` stamps log entries with the decision number; a game with rounds returns its round (and `log_turn_name` its word for it).
- Private helpers: `players`, `pstate(player)`, `whose(player, viewer)`, `tally(player, key, amount)` (counts in `data['tally']`), `sole_leader(scores)`.
- `plai_testr/rspec` provides the standard checks every game runs (see *Specs*).

When several games need the same thing and the gem lacks it, add it to the gem, not to each game.

`bundle exec plai_testr generate game <name>` creates the skeleton. `games/hearts` (4 players, hidden hands, a pick-3 pass) and `games/gin_rummy` (2 players, draw/discard turns, engine-computed melds) are complete examples.

## How a game runs

Each turn the runner asks `next_player` who acts, builds a numbered menu from `legal_moves(player)`, and the player (model or bot) picks a number. `apply_action_effects` applies the chosen move's `action` to `@game_state`. The game ends when `status['game_over']` is true; set `status['winner']` and `status['end_reason']` too (`@game_state.apply_changes('status' => {...})`). A game that never ends is stopped at the decision limit with `end_reason: 'decision_limit_reached'`.

Build each menu entry with `option(label, public: ..., log: ..., name => params)`:

```ruby
option('Play 3♣', public: 'played 3♣', play: { value: card['uid'] })
# => { label: 'Play 3♣', public: 'played 3♣', action: { play: { value: 42 } } }

def apply_action_effects(player, action)
  case action
  in { play: { value: uid } } then play(player, uid)
  end
end
```

`label` is what the acting player sees, `public` what other players see, `log` the short console text. The action has exactly one name; `value:` is the main parameter, and others sit beside it. Moves and actions use symbol keys (the runner converts hand-written string keys), so `apply_action_effects` and the bot rules can pattern-match them. The runner checks every menu before using it and raises `PlaiTestr::MoveError` for a misspelled key or a malformed action.

A menu with one move is applied without asking anyone. `pick_range(player)` returning `[min, max]` turns the menu into a pick-N choice, applied as one action whose `value` lists the chosen moves' values: `{ pass: { value: [42, 17, 9] } }`.

Randomness comes from `@rng`. It is reset for each decision from the seed and the decision number, so the same seed and the same choices always give the same game, interrupted or not.

The gem's `README.md` (`.plai_testr/gem/README.md`) lists every hook.

## Components

Card lists, tiles and other components go in `data/components/`, one file per component, named after the file. `PlaiTestr::Deck.build(@rules, component: 'cards')` returns `data/components/cards.csv` (or `.yml`, `.json`) with a `uid` on every card; without `component:` it returns the first deck. A file is a list of records: a CSV with a header row (numbers become numbers, empty cells are left out) or a YAML or JSON list of hashes. A `copies` field makes that many copies. `games/hearts` reads `data/components/cards.csv`; `games/gin_rummy` keeps its deck inline under `components` in `rules.json`, which suits small generated decks. `generate game` creates a placeholder `data/components/cards.yml`; replace it.

- Ask the designer for their component list in whatever form they have it (a spreadsheet or CSV export, YAML, a pasted table, a PDF). Don't retype it from the rules text.
- Convert it to the format above. Keep the fields the engine or the players need; leave out print layout, art notes and other metadata.
- If the source will keep changing, write a small rerunnable script in the game folder (`games/<name>/import.rb`) that rebuilds the file from the source, so the designer can refresh it, and a spec that fails when the copy is behind (see *Specs*).
- After converting, check the counts with the designer (cards per type, total), and run `bundle exec rspec games/<name>`: a malformed file fails with the file and entry named.

## Building a harness: the order that works

1. **Rules first.** Put the rules text in `data/rules.md`, the numbers in `data/rules.json`, and the components in `data/components/` (see *Components*). Read them closely; list every gap or ambiguity and ask the designer before coding around it.
2. **State.** Decide what lives in `data` (`@game_state.data`: decks, piles, step, active player). `status` belongs to the runner. Use stable ids (card `uid`s, fixed pile indexes); never re-index things players refer to. A GameState subclass can name its keys with readers (`def step = @data['step']`).
3. **Steps.** Model a turn as a small state machine in `data['step']`. `legal_moves` and `apply_action_effects` switch on it.
4. **Specs for the rules.** Before any model plays, write specs that set up a situation and check the menu (`legal_moves`) and the effects. This is where rules bugs are cheapest.
5. **Bot rules.** Implement `bot_choice` so the game can play itself. Then `bundle exec plai_testr <game> botrun --games 1000` must finish with no crashes and sensible endings. Add a botrun spec over a few seeds.
6. **Views and prompts.** Write `view_text_for`, `rules_text_for`, `turn_phase`, then `debrief_facts` and `debrief_questions` together (see *Debrief*). Read a few prompts yourself, including a debrief (see *Checking a prompt*).
7. **Model games.** With the designer's go-ahead: one game with `--mode hybrid` (the bot plays obvious moves), then `--mode llm`.

## Designing what the model sees

Small local models (4B–14B) play well only when the engine does the bookkeeping.

- **The engine lists the legal moves; the model picks a number.** Never ask the model to name a card, type a move, or check legality.
- **Put engine-computed facts on each option, never advice.** "Discard 9♥ (deadwood after: 31)" is a fact; "Discard 9♥ (best)" decides for the model and ruins the test.
- **Generate views from state; never hand-write summaries.** Hand-written summaries leak hidden information or go stale.
- **Show each player only what they may know.** The gem already filters the event log per player; override `data_for(observer)` in GameState with `super.except(...)` (and `serialize_for` in PlayerState) to hide decks and other hands. Log events with `log(text)`, and `log(text, to: player)` for private ones ("You drew the 2♠"); `recent_events_for` shows each player what they may see.
- **Keep menus short.** Merge equivalent options (identical cards, interchangeable targets). Split one huge decision into steps.
- **Hide safety caps from players.** Turn or hand limits that stop runaway games (`MAX_HANDS`, `max_decisions`) must not appear in views or rules text, or models play for the cap.
- **Scope long rules.** If `rules.md` is long, override `rules_text_for` to send only the sections the current step needs.
- **Personas** (optional): `data/personas.yml` holds a shared `basic_strategy` and play styles under `personas`; each player gets one (`--personas a,b`, or at random) and its strategy goes into the system prompt. `data/bots.yml` holds parameters the bot policy reads with `bot_strategy_for(player)`, so botruns compare styles (see `games/hearts` and `games/gin_rummy`; the generated files explain the format). `botrun --personas all` cycles every arrangement and needs at least as many personas as seats.

## Reports

- `report_sections` adds markdown sections to each session report: game-specific tallies the designer cares about.
- Debrief answers get their own section in each session report. A game that renders them itself in `report_sections` returns false from `report_debrief?`.
- `botrun_stats` returns numbers for one bot game; a `PlaiTestr::Reporter::BotrunReport` subclass (registered as `botrun_report_class:`) turns them into sections with `extra_sections`. See `games/hearts`.
- Keep the counters in `data` so they survive checkpoints and resume.

## Debrief

After a model game each player answers the game's `debrief_questions`. The gem builds the prompt in a fixed order, the same for every game:

1. `debrief_summary(player)`, built by the gem (do not override): the outcome and final scores; **GAME FACTS** from `debrief_facts(player)`; the player's own decisions; and its plan each time it changed.
2. `debrief_view_for(player)`: the final position (default: the result, final scores, `view_text_for` and the player's visible log).

Small local models cannot reliably recall a long game from its log, and they invent what they cannot recall. The facts are what keep the answers honest, so every game implements both hooks deliberately:

- **`debrief_facts(player)`** returns a Hash with plain-language keys (the model sees it as YAML). Per player: final score and points by source, counts of the actions the questions ask about, races or majorities and who won them; and who ended the game, when and how. Count anything a question might make a player guess at.
- **Compute facts only from saved state** (`data`, player state). `debrief <session_id>` rebuilds them from the checkpoint, possibly after the code changed, so instance variables and anything recomputed from discarded state are unavailable. Keep the counters the facts need in `data` as the game is played.
- **Facts, not conclusions.** "Player 3 had 4 Candy Corn, the most" is a fact; "Candy Corn was the strongest card" answers the question for the model.
- **`debrief_questions`** ask about the player's own experience and point at something the facts or its plans can answer ("Which of your plays scored less than you expected? Name the round."). Avoid open questions with nothing behind them ("what felt pointless?"): models fill those with invented events.
- Personas shape the answers: a player told to love a card will praise it. Read debriefs across personas before concluding anything.
- `check!` warns when a game defines neither `debrief_facts` nor `botrun_stats`; preflight builds every debrief after its lint games; the standard checks (`plai_testr/rspec`) build them too.
- `debrief <session_id> [--model M] [--think]` re-asks a completed session (ask first: it calls the model) and rebuilds its report, keeping earlier answers under `debrief_history`. Use it to try a better `debrief_facts`, other questions, or a bigger model on the same game without replaying it.

## Bot rules

`bot_choice(player, moves, pick: nil)` returns `nil` or `{ 'choice' => n, 'rule' => 'name', 'obvious' => bool }` (`'choices' => [...]` for pick-N). When the model never gives a valid answer, the runner plays the bot's choice instead (or a random legal move when there is none) and flags the turn.

- Mark a rule `obvious` only when the move is never worse than any alternative. `--mode hybrid` plays obvious moves without calling the model, and the report scores the model against them.
- Name rules after the idea (`duck`, `dump_queen`, `shed_deadwood`); the botrun report counts them.
- Keep the bot simple and readable. It is a baseline and a crash test, not a strong player.

## Rulings and simplifications

- When the designer settles a rules question, add it to a **Rulings** section in `data/rules.md` (dated), so models and future readers see it.
- When the harness deliberately simplifies a rule, list it in a **Simplifications** section in `data/rules.md` (see `games/gin_rummy`).
- Keep open questions and engine choices the designer has not confirmed in `games/<name>/NOTES.md`, marked as unconfirmed, and move them into **Rulings** once settled.

## Specs

- Unit specs drive the runner directly: build it with `game.runner_class.new(game: game, players: game.players, seed: 1, mode: 'bot', persist: false, out: StringIO.new)`, call `setup`, arrange the state (`runner.game_state`, `runner.data`), and check `legal_moves` or the effects of `apply_action_effects`. Hooks are public, so specs call them directly. The examples' `spec/` folders show the pattern.
- Every game runs the gem's standard checks: `it_behaves_like 'a PlAI Testr game', '<name>'` (from `plai_testr/rspec`, required by the app's spec_helper). At every player count in `rules.json`, over a few seeds, they check that bot games reach an ending; that every turn prompt and, at the end, every debrief prompt builds (botruns never build prompts, so this is the only check before a model game); that state survives a JSON round trip; that resuming from a mid-game checkpoint gives the same result; and that no player sees another's hand. They come from the installed gem, so an upgrade adds checks without editing the game. Don't copy them into a game; `seeds:` sets how many games, and `pending:` holds them while a new game is built.
- Game specs add what is specific to the game: rules situations, card counts, report sections.
- If `data/` is copied from another repository, add a spec that fails when the copy is behind.
- `bundle exec rspec` runs every game; `bundle exec rspec games/<name>` runs one.

## Checking a prompt

```ruby
# bundle exec ruby -e '...'
require 'plai_testr'
game   = PlaiTestr.load('hearts')
runner = game.runner_class.new(game: game, players: game.players, seed: 1, mode: 'bot', persist: false, out: StringIO.new)
runner.setup
5.times { runner.play_turn }
player = runner.next_player
puts runner.persona_for(player), runner.view_text_for(player), runner.menu(player).map { |m| m[:label] }

runner.play_turn until runner.game_over?
puts runner.debrief_summary(player), runner.debrief_view_for(player)
```

## Commands

```
bundle exec plai_testr <game> botrun --games 1000 [--personas all]    Bots only; report in games/<game>/reports/
bundle exec plai_testr <game> play [--seed 1] [--mode hybrid]         One model game, after preflight checks (ask first)
bundle exec plai_testr <game> resume <session_id>                     (ask first)
bundle exec plai_testr <game> debrief <session_id> [--model M] [--think]   Re-ask a completed session's debrief (ask first)
bundle exec plai_testr <game> compare | list | preflight
bundle exec plai_testr generate game <name>
bundle exec rspec

bundle exec plai_testr <game> <command> --help lists a command's options.
play --debrief-model M --debrief-think gives the debrief its own model and thinking.
--quiet shows only progress and the result; --verbose adds the raw model output (play) or every game (botrun).
Set PLAI_TESTR_DEBUG=1 to see the full backtrace of an error.
```
