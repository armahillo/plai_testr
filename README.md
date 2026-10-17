# PlaiTester

Automated board game playtesting with locally hosted LLM players via [Ollama](https://ollama.com).

PlaiTester is game-agnostic. A game supplies the rules engine: every turn it lists the legal moves as a numbered menu, the player model picks a number, and the game applies it. PlaiTester handles the model calls, retries and fallbacks, checkpoints and resume, transcripts, and reports. An optional referee answers yes/no rules questions for conditions that are awkward to encode.

## Requirements

- Ruby 3.1+
- Ollama running locally (or reachable on your network)
- A pulled player model, e.g. `ollama pull qwen3:8b`

## Installation

```ruby
gem 'plai_tester', path: '/path/to/plai_testr'
```

## Guides

- [Nested decisions with FrameQueue](docs/frame_queue.md): attacks and responses, triggered effects, decisions inside decisions
- [Yes/no rulings with the referee](docs/referee.md): free-text conditions judged by a second model
- Complete example games ship with `plai_tester new`, under `templates/examples/` in this repository: Hearts (4 players, hidden hands, pick-N passing, custom report sections and botrun report) and Gin Rummy (2 players, engine-computed melds, personas)

## Writing a game

A game is a `Session::Runner` subclass plus state classes. The runner implements:

| Hook | Required | Purpose |
|---|---|---|
| `setup` | yes | Build the starting state (not called on resume). `@rng` is seeded. |
| `legal_moves(player)` | yes | Array of moves: `{ 'label' => …, 'action' => { 'action' => …, 'parameters' => … }, 'public' => …, 'log' => … }`. `label` is what the model sees; optional `log` is a shorter line for the console and report |
| `apply_action_effects(player, action)` | yes | Apply the chosen move's `action` to `@game_state` |
| `next_player` | | Who acts next (default: alternate) |
| `pick_range(player)` | | `[min, max]` to have the player pick several moves at once; applied as `parameters['values']` |
| `persona_for(player)` | | Strategy text added to the player's system prompt (path to victory, playstyle); games can read `--personas` from `@persona_request` and list them in `custom['personas']` for the report |
| `turn_phase(player)` | | Short label for the step, shown on each turn line and in the report's turn log |
| `game_over?` | | Default: `flags['game_over'] == true`. Set `flags['winner']` and `flags['end_reason']` for the report. |
| `rules_text_for`, `view_text_for`, `prompt_note_for` | | Prompt text: rules, the player's view, a one-off note |
| `recent_events_for` | | Recent events shown to the player (default: own labels, others' `public` text) |
| `debrief_questions`, `debrief_view_for` | | End-of-game designer feedback questions |
| `report_sections` | | Extra markdown sections for the session report |
| `scripted_choice(player, moves, pick: nil)` | | Bot rules: `nil`, or `{ 'choice' => n }` (`'choices' => [...]` on pick turns) with `'rule'` and `'obvious'`. Used by `--mode hybrid` (obvious moves skip the model), `--mode bot` and `botrun`; in model games the bot's choice is logged beside the model's |
| `botrun_stats` | | Game-specific numbers for one botrun game |
| `think_about?(player)` | | With `--think`: whether this turn is worth thinking about (default: every turn). Other turns run without thinking, at the same context size so Ollama does not reload the model |
| `self.persona_names` | | Persona names, so `botrun --personas all` can cycle every pairing |

A menu with one move is applied without calling the model. Unparseable replies are retried, then fall back to option 1 and are flagged in the report.

For nested decisions (responses, triggered effects, interrupts), include `Session::FrameQueue`: a stack of frames kept in game state, so checkpoints resume mid-sequence. Implement `frame_queue` (the array), `schedule_frames` (what happens when it is empty), and `on_<type>(frame, params)` handlers; frames marked `auto` resolve without a player. Optional: `intercept_frame(frame)` (e.g. hand maintenance) and `halt_frames?`.

A rules JSON file needs only `game` (name, version, description); everything else in it is for your game. See `rules/schema.json` and `rules/example.json`.

### State classes

### PlayerState subclass

`PlaiTester::State::PlayerState` tracks a player's score, hand, and flags. Override it to add game-specific per-player state (e.g. ordered card piles, board position, resource pools) and to control what opponents can see.

```ruby
module MyGame
  module State
    class PlayerState < PlaiTester::State::PlayerState

      attr_reader :tableau  # example: a face-up card pile

      def initialize(name:, score: 0, hand: [], flags: {}, tableau: [])
        super(name: name, score: score, hand: hand, flags: flags)
        @tableau = tableau
      end

      def self.from_h(data)
        new(
          name:    data['name'],
          score:   data.fetch('score', 0),
          hand:    data.fetch('hand', []),
          flags:   data.fetch('flags', {}),
          tableau: data.fetch('tableau', [])
        )
      end

      def apply_changes(changes)
        return if changes.nil? || changes.empty?
        super
        @tableau = changes['tableau'] if changes.key?('tableau')
      end

      # Full state — checkpoints see everything
      def serialize
        super.merge('tableau' => @tableau)
      end

      # Opponent-visible state — override to hide or expose fields as your rules require
      def serialize_for(observer)
        return serialize if observer == @name
        super  # base: shows score, hand_size; add fields here as needed
      end
    end
  end
end
```

Key methods:
- `serialize` — full state, used for checkpoints. Call `super` and merge your additions.
- `serialize_for(observer)` — per-observer view. Return `serialize` for self; filter for opponents. The base implementation hides hand contents and shows only hand size.
- `apply_changes(changes)` — merges a hash of changes (`score`, `hand`, `flags`, plus your additions). Call `super` first, then handle your additions.
- `from_h(data)` — deserializes a checkpoint; must round-trip with `serialize`.

### GameState subclass

`PlaiTester::State::GameState` tracks turn, phase flags, and the collection of player states. Override it to add global game state (shared decks, discard piles, round counters) and to point at your `PlayerState` subclass.

```ruby
module MyGame
  module State
    class GameState < PlaiTester::State::GameState

      # Typed accessors over @custom for global game state
      def round        = @custom.fetch('round', 1)
      def shared_deck  = @custom['shared_deck'] ||= []

      def draw_from_deck
        shared_deck.shift
      end

      # serialize is inherited — @custom is included automatically.
      # Override custom_for to filter global state per observer (e.g. hide face-down deck contents).
      # The full @custom is always saved in checkpoints via serialize.
      def custom_for(observer)
        @custom.except('shared_deck').merge('deck_size' => shared_deck.length)
      end

      private

      # Point the framework at your PlayerState subclass
      def player_state_class = PlayerState
    end
  end
end
```

Global state that doesn't need typed methods can be passed through `apply_changes` using the `custom` key and accessed via `@custom` directly. Typed accessors are recommended for anything the runner needs to reason about explicitly.

### Running a game

`PlaiTester::CLI` gives a game `start`, `batch`, `resume`, `preflight`, `compare`, `list` and `botrun`. Pass it any object that responds to `name`, `runner_class`, `game_state_class`, `rules_file`, `players`, `sessions_dir`, `reports_dir`, `comparison_class` and `botrun_report_class`:

```ruby
PlaiTester::CLI.new(my_game).run(ARGV)
```

`Reporter::ModelComparison` compares completed sessions by model and host (speed, reliability, endings); subclass it and override `extra_columns` and `notes` to add game-specific columns.

`botrun --games N` (or `--seeds`) plays N games with the bot rules alone, in memory (`Runner#play_out`, no checkpoints or transcripts), and writes one `Reporter::BotrunReport`: endings, wins by persona, matchup and seat (with 95% ranges), game length, bot rules used, crashes and outlier seeds. Subclass it and override `extra_sections` for game-specific sections.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `PLAITESTER_PLAYER_MODEL` | `qwen3:8b` | Ollama model for player agents |
| `PLAITESTER_REFEREE_MODEL` | none | Ollama model for yes/no rulings (only if the game asks for them) |
| `PLAITESTER_OLLAMA_HOST` | `localhost` | Ollama host |
| `PLAITESTER_OLLAMA_PORT` | `11434` | Ollama port |

`--think` (CLI) turns on the player model's thinking for menu turns: a larger context (16384) and output budget (8192 tokens), several times slower. A game can limit it to the decisions that matter with `think_about?`. The setting is stored in the session, so `resume` keeps it; the thoughts go in `think.log` between `<think>` tags.

## Running tests

```bash
bundle exec rspec
```

## Project structure

```
lib/
  version.rb
  plai_tester.rb           Main require file
  plai_tester/
    agents/
      ollama_client.rb     HTTP wrapper for Ollama /api/chat; logs timings to think.log
      player_agent.rb      Menu choice, pick-N, and debrief prompts with JSON schemas
      referee_agent.rb     Optional yes/no rulings
    compiler/
      rules_loader.rb      Loads a rules JSON file (requires `game`)
    reporter/
      think_log.rb         Reads per-call timings from think.log
      report_builder.rb    Session report: result, reliability, speed, game sections, turn log
      model_comparison.rb  Compares sessions by model and host; games add columns
      botrun_report.rb     Summary of a botrun; games add sections
    session/
      manager.rb           Checkpoint save/load, transcript append
      runner.rb            Menu-turn loop and SIGINT handler
      frame_queue.rb       Optional stack of pending decisions for nested sequences
    state/
      base.rb              Abstract base: serialize / serialize_for interface
      player_state.rb      Per-player state: score, hand, flags
      game_state.rb        Global state: turn, flags, custom, player_states collection
    cli.rb                 start / batch / resume / preflight / compare / list / botrun for a game
    botrun.rb              Plays many in-memory bot games and collects their results
rules/
  schema.json              Rules file schema
  example.json             Annotated example
```

## Session output

Each session produces:

- `sessions/<id>/state.json` — full game state checkpoint, updated after every turn
- `sessions/<id>/transcript.jsonl` — turn-by-turn log with player reasoning (one JSON object per line)
- `sessions/<id>/think.log` — every model reply, with Ollama's timings per call
- `reports/<id>.md` — markdown report generated at session end
