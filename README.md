# PlAI Testr

Automated tabletop game playtesting with local LLM players via [Ollama](https://ollama.com).

Your game lists the legal moves each turn as a numbered menu; a model (or a scripted bot) picks one; PlAI Testr applies it, checkpoints, and writes a markdown report. Bots alone can play thousands of games in minutes for balance numbers; model players add reasoning and end-of-game feedback.

## Requirements

- Ruby 3.2+
- [Ollama](https://ollama.com), local or on your network (not needed for bot-only runs)

## Quick start

```sh
gem install plai_testr        # or in a Gemfile: gem 'plai_testr', github: 'armahillo/plai_testr'
plai_testr new my_playtests   # an app with two example games: Hearts and Gin Rummy
cd my_playtests
bundle install

bundle exec plai_testr hearts botrun --games 100   # bots only, no model: a report in seconds
bundle exec plai_testr gin_rummy play              # one model game (pulls qwen3:8b if missing)
```

Reports land in `games/<game>/reports/`. Add your own game with `bundle exec plai_testr generate game my_game`, then fill in the hooks below. The generated app's `AGENTS.md` walks an AI coding assistant through building a harness, so you can have your own agent do it.

## Commands

```
plai_testr <game> play      [--seed N] [--model M] [--think] [--mode llm|hybrid|bot] [--players N] [--personas A,B] [--referee M]
plai_testr <game> botrun    [--games N | --seeds 1,2,3] [--players N] [--personas all|A,B]
plai_testr <game> resume    <session_id>
plai_testr <game> preflight
plai_testr <game> compare   [--since ID]
plai_testr <game> list
plai_testr new <dir>
plai_testr generate game <name>
```

- `play` runs one game. Without `--seed` it picks one from 1–100 and prints it. Before playing, preflight checks Ollama, pulls missing models, warms them up, measures the first prompt against the context size, and plays 5 bot games to catch menu bugs. `--skip-preflight` skips all of that.
- `--mode hybrid` lets the bot play moves it marks *obvious*; `--mode bot` uses no model.
- `botrun` plays many bot-only games in memory and writes one report: endings, wins by persona and seat with 95% ranges, game length, bot rules used, warnings and crashes.
- `--quiet` shows a progress line and the result; `--verbose` adds raw model output (`play`) or every game (`botrun`).
- Ctrl+C (or SIGTERM) saves and stops after the current move; a botrun finishes its game and reports. A second Ctrl+C quits at once.
- Errors print one line. `PLAI_TESTR_DEBUG=1` shows the backtrace; mistakes in game code (`MoveError`) always do.

## Writing a game

`generate game` creates `games/<name>/` with everything below. The examples in [`templates/examples/`](templates/examples) are complete games to copy from.

```
games/<name>/
  lib/<name>.rb             Requires the game and calls PlaiTestr.register
  lib/<name>/bot.rb         Bot rules (bot_choice), included in the runner
  lib/<name>/session/       Runner (rules engine)
  lib/<name>/state/         GameState / PlayerState subclasses
  data/rules.json           Name, version, player count, card deck, numbers the engine uses
  data/rules.md             Rules text the model players read
  data/personas.yml         Optional: strategy and play styles for model players
  data/bots.yml             Optional: parameters the bot rules read
  spec/
```

### Hooks

A game subclasses `PlaiTestr::Session::Runner`. These hooks are its public API ([`runner.rb`](lib/plai_testr/session/runner.rb)):

| Hook | Required | Purpose |
|---|---|---|
| `setup` | yes | Build the starting state. Not called on resume. |
| `legal_moves(player)` | yes | The menu: an array of `option(...)` entries |
| `apply_action_effects(player, action)` | yes | Apply the chosen move's action to `@game_state` |
| `next_player` | | Who acts next (default: alternate) |
| `pick_range(player)` | | `[min, max]` to pick several options at once |
| `game_over?` | | Default: `status['game_over']` |
| `turn_phase(player)` | | Short step label for the console and report |
| `rules_text_for`, `view_text_for`, `prompt_note_for` | | Prompt text: rules, the player's view, a one-off note |
| `recent_events_for(player)` | | Recent events from the event log (default: the last 8 this player may see) |
| `persona_for(player)` | | Strategy text for the system prompt (default: built from `personas.yml`) |
| `display_name(player)` | | Name in the console and reports (default: the persona's key, title-cased, else the player id) |
| `bot_choice(player, moves, pick: nil)` | | Bot rules: `nil` or `{ 'choice' => n, 'rule' => name, 'obvious' => bool }` (`'choices'` on pick turns) |
| `think_about?(player)` | | With `--think`: whether this turn gets thinking (default: every turn) |
| `debrief_questions`, `debrief_view_for` | | End-of-game feedback questions |
| `report_sections`, `report_debrief?` | | Extra report sections; false to render the debrief yourself |
| `botrun_stats` | | Game-specific numbers for one botrun game |

Helpers for hooks: `option`, `menu(player)` (the menu as the runner sees it), `data`, `log(text, to: nil)`, `event_log`, `persona(player)`, `bot_strategy_for(player)`, `@rng`, `@rules`, `@game_state`, `out`. Specs drive a runner with `setup`, `play_turn`, `play_out` and the hooks above.

### Moves

```ruby
def legal_moves(player)
  hand(player).map { |card| option("Play #{card['name']}", public: "played #{card['name']}", play: { value: card['uid'] }) }
end

def apply_action_effects(player, action)
  case action
  in { play: { value: uid } }  then play(player, uid)
  in { pass: { value: uids } } then pass(player, uids)
  end
end
```

`label` (the first argument) is what the acting player sees; `public:` is what others see; `log:` is a shorter console line. An action has one name; `value:` is the main parameter and others sit beside it. Moves and actions have symbol keys, so `apply_action_effects` can pattern-match them; a hand-written move with string keys is converted. On a pick turn the chosen values arrive together: `{ pass: { value: [42, 17, 9] } }`. Every menu is checked before it is used: a misspelled key or a malformed action raises `PlaiTestr::MoveError` naming the hook, player, decision and option. A menu with one option is applied without asking anyone.

### State

`@game_state` ([`game_state.rb`](lib/plai_testr/state/game_state.rb)) holds `turn` (decisions so far), `players`, `status` and `data`; each `player_state(name)` ([`player_state.rb`](lib/plai_testr/state/player_state.rb)) holds `score`, `hand` and `data`.

- `status` belongs to the runner: set `game_over`, `winner` and `end_reason` when the game ends, with `@game_state.apply_changes('status' => {...})`.
- `data` is the game's own state, as plain JSON-safe values so checkpoints work without extra code.
- Subclass `GameState` to name your keys (`def step = @data['step']`) and to hide information per player with `data_for(observer)`; subclass `PlayerState` and override `serialize_for` / `public_data` to choose what opponents see. The examples show both.

### Personas and bots

`data/personas.yml` gives model players a shared `basic_strategy` and play styles under `personas`; `data/bots.yml` gives the bot rules parameters, per persona, read with `bot_strategy_for(player)`. Both files are optional and the generated copies explain their format. Each player gets a persona from `--personas a,b` or at random per seed; `botrun --personas all` cycles every pairing.

### Randomness and limits

- Use `@rng` for all randomness. It is reset for each decision from the seed and the decision number, so the same seed and the same choices always give the same game, interrupted or not.
- When the model never gives a valid answer, the bot's choice is played instead (or a random legal move from a separate generator), and the turn is flagged.
- Every game stops at a decision limit (`end_reason: 'decision_limit_reached'`, no winner) so a buggy game cannot run forever. Set `max_decisions:` in `PlaiTestr.register`; otherwise the app backstop applies.

### Nested decisions and rulings

- [FrameQueue](docs/frame_queue.md): attacks and responses, triggered effects, decisions inside decisions.
- [Referee](docs/referee.md): yes/no rulings on free-text conditions by a second model.

## Configuration

`config/plai_testr.rb` in the app (generated, all commented out):

```ruby
PlaiTestr.configure do |config|
  config.max_decisions  = 100_000       # backstop for games without their own limit
  config.player_model   = 'qwen3:8b'
  config.ollama_host    = 'localhost'
  config.ollama_port    = 11434
  config.model_settings = { context_size: 8192 }
end
```

A game can override model settings in `PlaiTestr.register(..., model_settings: { ... })`.

| Model setting | Default | Used for |
|---|---|---|
| `context_size` | 8192 | Menu turns without `--think`; the referee |
| `long_context_size` | 16384 | Sessions with `--think`; the debrief |
| `menu_budget` | 512 | Output tokens for a menu answer |
| `think_budget` | 8192 | Output tokens for a thinking turn |
| `debrief_budget` | 1024 | Output tokens for the debrief |
| `referee_budget` | 2048 | Output tokens for a ruling |
| `temperature` | 0.6 | Player sampling |

Values outside the hard limits are clamped with a warning: context sizes between 2048 and the model's own maximum, temperature 0–2, budgets above 0 and below the context size. The values used are recorded in each report. Environment variables set the defaults: `PLAI_TESTR_PLAYER_MODEL`, `PLAI_TESTR_REFEREE_MODEL`, `PLAI_TESTR_OLLAMA_HOST`, `PLAI_TESTR_OLLAMA_PORT`.

## Session output

- `sessions/<id>/state.json`: the checkpoint, replaced atomically after every decision
- `sessions/<id>/transcript.jsonl`: one JSON object per decision, with the model's reasoning. After a crash the last line may be cut off; skip lines that do not parse.
- `sessions/<id>/think.log`: every model reply with Ollama's timings
- `reports/<id>.md`: the session report

`resume` continues an interrupted session exactly, or refuses: if the game's data, code or the gem version changed since the session started, start a new one with `play`.

## Development

```sh
bundle install
bundle exec rspec
```

`lib/plai_testr/` holds the gem: [`session/runner.rb`](lib/plai_testr/session/runner.rb) (the decision loop and hooks), [`agents/`](lib/plai_testr/agents) (Ollama client, player and referee prompts), [`reporter/`](lib/plai_testr/reporter), [`state/`](lib/plai_testr/state), [`cli.rb`](lib/plai_testr/cli.rb), [`preflight.rb`](lib/plai_testr/preflight.rb), [`botrun.rb`](lib/plai_testr/botrun.rb). `templates/` holds what `new` and `generate game` copy, including the example games and their specs.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
