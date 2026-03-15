# TESTR

Automated board game playtesting using locally-hosted LLM agents via [Ollama](https://ollama.com).

TESTR runs sessions of a board game autonomously — player agents make decisions, a referee agent enforces the rules, and the platform records the full session to a markdown report for review.

## Requirements

- Ruby 3.0+
- Ollama running on a local machine
- Ollama models pulled for player and referee roles (see [Models](#models))

## Setup

```bash
bundle install
```

## Usage

```bash
# Start a new session
bundle exec bin/testr start rules/my_game.json

# Resume an interrupted session
bundle exec bin/testr resume <session_id>

# List all sessions
bundle exec bin/testr list

# Generate a report from a saved session
bundle exec bin/testr report <session_id>
```

Interrupt a running session at any time with `Ctrl+C` — state is saved automatically. Resume with the session ID printed on exit.

## Configuration

All configuration is via environment variables.

| Variable | Default | Description |
|---|---|---|
| `TESTR_PLAYER_MODEL` | `llama3.2:3b` | Ollama model for player agents |
| `TESTR_REFEREE_MODEL` | `qwen3:8b` | Ollama model for referee agent |
| `TESTR_OLLAMA_HOST` | `localhost` | Ollama host |
| `TESTR_OLLAMA_PORT` | `11434` | Ollama port |

To run against a separate machine on your network:

```bash
TESTR_OLLAMA_HOST=192.168.1.x bundle exec bin/testr start rules/my_game.json
```

## Models

| Role | Recommended model | Notes |
|---|---|---|
| Players | `llama3.2:3b` | Fast, ~2GB RAM, no GPU required |
| Referee | `qwen3:8b` or `mistral:7b` | Better reasoning for rules validation |

With 32GB RAM you can run 2 player agents and a referee concurrently without issue. Ollama will automatically offload referee model layers to the GPU if available.

## Project structure

```
bin/
  testr                    CLI entry point
lib/testr/
  agents/
    ollama_client.rb       HTTP wrapper for Ollama /api/chat
    player_agent.rb        Builds turn prompts, parses JSON responses
    referee_agent.rb       Validates actions, computes state changes
  compiler/
    rules_loader.rb        Loads and validates a rules JSON file
  random/
    engine.rb              Dice rolls, shuffles, card draws
  reporter/
    report_builder.rb      Generates markdown report from session data
  session/
    manager.rb             Checkpoint save/load, transcript append
    runner.rb              Main game loop and SIGINT handler
  state/
    game_state.rb          Mutable game state: turn, scores, flags, custom
rules/
  schema.json              Rules file schema definition
  example.json             Annotated example (simple High Card game)
sessions/                  Per-session state checkpoints and transcripts (runtime)
reports/                   Generated markdown reports (runtime)
```

## Session output

Each session produces two files:

- `sessions/<id>/state.json` — full game state checkpoint, updated after every turn
- `sessions/<id>/transcript.jsonl` — turn-by-turn log with player reasoning (one JSON object per line)
- `reports/<id>.md` — markdown summary report generated at session end

## Rules format

Rules are defined as JSON files conforming to `rules/schema.json`. See `rules/example.json` for a working example.

Because converting human-readable rules to this format is semantically complex, the recommended workflow is to use a capable LLM (e.g. Claude) to compile your rules document. Once the project is set up, use this prompt:

> I am using TESTR, an automated board game playtesting platform. I need to compile my human-readable rules into the TESTR structured rules format. Please convert the following rules document into valid JSON conforming to the schema. Flag any ambiguities as a `notes` field on the relevant section.
>
> **Schema:** `[paste contents of rules/schema.json]`
>
> **Rules:** `[paste your rules document]`

Save the output to `rules/<game_name>.json` and pass it to `testr start`.

## Running tests

```bash
bundle exec rspec
```
