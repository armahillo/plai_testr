# PlaiTester

Automated board game playtesting using locally-hosted LLM agents via [Ollama](https://ollama.com).

PlaiTester runs sessions of a board game autonomously — player agents make decisions, a referee agent enforces the rules, and the platform records the full session to a markdown report for review.

## Requirements

- Ruby 3.1+
- Ollama running on a local machine
- Ollama models pulled for player and referee roles (see [Models](#models))

## Installation

Add to your game project's `Gemfile`:

```ruby
gem 'plai_tester', path: '/path/to/plai_tester'
```

Or once published:

```ruby
gem 'plai_tester'
```

Then:

```bash
bundle install
```

## Usage

```bash
# Start a new session
bundle exec plai_tester start rules/my_game.json

# Resume an interrupted session
bundle exec plai_tester resume <session_id>

# List all sessions
bundle exec plai_tester list

# Generate a report from a saved session
bundle exec plai_tester report <session_id>
```

Interrupt a running session at any time with `Ctrl+C` — state is saved automatically. Resume with the session ID printed on exit.

## Configuration

All configuration is via environment variables.

| Variable | Default | Description |
|---|---|---|
| `PLAITESTER_PLAYER_MODEL` | `llama3.2:3b` | Ollama model for player agents |
| `PLAITESTER_REFEREE_MODEL` | `qwen3:8b` | Ollama model for referee agent |
| `PLAITESTER_OLLAMA_HOST` | `localhost` | Ollama host |
| `PLAITESTER_OLLAMA_PORT` | `11434` | Ollama port |

To run against a separate machine on your network:

```bash
PLAITESTER_OLLAMA_HOST=192.168.1.x bundle exec plai_tester start rules/my_game.json
```

## Models

| Role | Recommended model | Notes |
|---|---|---|
| Players | `llama3.2:3b` | Fast, ~2GB RAM, no GPU required |
| Referee | `qwen3:8b` or `mistral:7b` | Better reasoning for rules validation |

With 32GB RAM you can run 2 player agents and a referee concurrently without issue. Ollama will automatically offload referee model layers to the GPU if available.

## Extending PlaiTester for your game

The base gem handles the session loop, checkpointing, agent communication, and reporting. Game-specific behavior — richer player state, custom serialization, game-specific action vocabulary — is added by subclassing the state layer in your own project.

### Project layout

A typical game extension lives in its own directory (or gem):

```
my_game/
  lib/
    my_game.rb               require file
    my_game/
      state/
        player_state.rb      subclass of PlaiTester::State::PlayerState
        game_state.rb        subclass of PlaiTester::State::GameState
  spec/
    my_game/
      state/
        player_state_spec.rb
        game_state_spec.rb
  rules/
    my_game.json             rules file (see Rules format below)
```

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

      # Full state — referee and checkpoints see everything
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
- `serialize` — full state, used by the referee and for checkpoints. Call `super` and merge your additions.
- `serialize_for(observer)` — per-observer view. Return `serialize` for self; filter for opponents. The base implementation hides hand contents and shows only hand size.
- `apply_changes(changes)` — receives a hash from the referee's `state_changes` response. Call `super` first, then handle your additions.
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
      # The full @custom is always sent to the referee and checkpoints via serialize.
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

Global state that doesn't need typed methods can be passed through `apply_changes` using the `custom` key and accessed via `@custom` directly. Typed accessors are recommended for anything the referee or runner needs to reason about explicitly.

### Wiring it together

In your `my_game.rb` require file:

```ruby
require 'plai_tester'

require_relative 'my_game/state/player_state'
require_relative 'my_game/state/game_state'
```

To start a session using your custom state classes, pass `game_state_class:` to `Runner`. You can also subclass `Runner` itself to override the `setup` hook, which runs once before the game loop on new sessions (not on resume) and has access to `@random` (`PlaiTester::Random::Engine`) and `@game_state`:

```ruby
module MyGame
  class Runner < PlaiTester::Session::Runner
    private

    def setup
      deck = @random.shuffle(build_deck)
      @game_state.apply_changes('custom' => { 'shared_deck' => deck })
    end
  end
end
```

To start a session using your custom state classes, pass `game_state_class:` to `Runner`. The runner uses it to instantiate state for new sessions and to deserialize checkpoints on resume.

```ruby
require 'my_game'

rules = PlaiTester::Compiler::RulesLoader.load('rules/my_game.json')

PlaiTester::Session::Runner.new(
  rules:            rules,
  players:          ['Player 1', 'Player 2'],
  models:           { player: 'llama3.2:3b', referee: 'qwen3:8b' },
  game_state_class: MyGame::State::GameState
).run
```

Resume works the same way:

```ruby
PlaiTester::Session::Runner.resume(
  session_id:       '4a3f...',
  models:           { player: 'llama3.2:3b', referee: 'qwen3:8b' },
  game_state_class: MyGame::State::GameState
).run
```

### Rules format

Rules are defined as JSON files. The schema is at `rules/schema.json` in this repo and the annotated example at `rules/example.json` covers a simple two-player card game.

Required top-level keys: `game`, `components`, `setup`, `turn_structure`, `actions`, `win_conditions`.

Because converting human-readable rules to this format is semantically complex, the recommended workflow is to use a capable LLM (e.g. Claude) with this prompt:

> I am using PlaiTester, an automated board game playtesting platform. I need to compile my human-readable rules into the PlaiTester structured rules format. Please convert the following rules document into valid JSON conforming to the schema. Flag any ambiguities as a `notes` field on the relevant section.
>
> **Schema:** `[paste contents of rules/schema.json]`
>
> **Rules:** `[paste your rules document]`

Save the output to `rules/<game_name>.json`.

### Running tests

```bash
bundle exec rspec
```

To include your game extension's specs, add the extension's `lib` path to `spec_helper.rb`:

```ruby
$LOAD_PATH.unshift File.expand_path('../my_game/lib', __dir__)
require 'my_game'
```

## Project structure

```
bin/
  plai_tester              CLI entry point
lib/
  version.rb
  plai_tester.rb           Main require file
  plai_tester/
    agents/
      ollama_client.rb     HTTP wrapper for Ollama /api/chat
      player_agent.rb      Builds turn prompts, parses JSON responses
      referee_agent.rb     Validates actions, computes state changes
    compiler/
      rules_loader.rb      Loads and validates a rules JSON file
    random/
      engine.rb            Dice rolls, shuffles, coin flips
    reporter/
      report_builder.rb    Generates markdown report from session data
    session/
      manager.rb           Checkpoint save/load, transcript append
      runner.rb            Main game loop and SIGINT handler
    state/
      base.rb              Abstract base: serialize / serialize_for interface
      player_state.rb      Per-player state: score, hand, flags
      game_state.rb        Global state: turn, phase, player_states collection
rules/
  schema.json              Rules file schema definition
  example.json             Annotated example (simple High Card game)
sessions/                  Per-session state checkpoints and transcripts (runtime)
reports/                   Generated markdown reports (runtime)
```

## Session output

Each session produces:

- `sessions/<id>/state.json` — full game state checkpoint, updated after every turn
- `sessions/<id>/transcript.jsonl` — turn-by-turn log with player reasoning (one JSON object per line)
- `reports/<id>.md` — markdown summary report generated at session end
