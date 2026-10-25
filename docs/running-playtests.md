# Running playtests

This guide covers running PlAI Testr from the command line: every command and its options, settings, where results go, and how to work through a game efficiently. It assumes your app is set up ([Getting started](getting-started.md)) and you're comfortable with command-line options and a little shell scripting.

Run every command from the app folder, with `bundle exec`.

## Commands

```
plai_testr <game> play      [--seed N] [--model M] [--think] [--mode llm|hybrid|bot] [--players N] [--personas A,B]
                            [--referee M] [--debrief-model M] [--debrief-think] [--skip-preflight] [--quiet | --verbose]
plai_testr <game> botrun    [--games N | --seeds 1,2,3] [--players N] [--personas all|A,B] [--quiet | --verbose]
plai_testr <game> resume    <session_id> [--skip-preflight] [--quiet | --verbose]
plai_testr <game> debrief   <session_id> [--model M] [--think] [--skip-preflight] [--verbose]
plai_testr <game> preflight [--seed N] [--model M] [--think] [--referee M] [--players N] [--personas A,B]
plai_testr <game> compare   [--since ID]
plai_testr <game> list
plai_testr new <dir>
plai_testr generate game <name>
plai_testr games
plai_testr help [<command>]
plai_testr --version
```

Every command takes `--help` to list its options (`plai_testr hearts botrun --help`, or `plai_testr help botrun`). A command refuses options it doesn't take.

```
$ bundle exec plai_testr hearts botrun --help
Usage: plai_testr hearts botrun [options]

Play many games with bot rules only (no model), then report

Options:
        --games N                    Number of games, seeds 1..N (default 100)
        --seeds LIST                 Comma-separated seeds, instead of --games
        --players N                  Number of players, within the game's player_count (default: the game's default)
        --personas LIST              One persona per player, comma-separated; * for random, "all" to cycle every arrangement (default: random)
        --quiet                      Show only a progress line and the result
        --verbose                    Show every game
```

### botrun

Plays many games with bots only, no model, and writes one report:

```sh
bundle exec plai_testr hearts botrun --games 1000
bundle exec plai_testr hearts botrun --seeds 4,17,52
bundle exec plai_testr hearts botrun --games 500 --personas all
```

`--games N` plays seeds 1 to N. Nothing is saved but the report, `games/<game>/reports/botrun-<time>.md`:

- how games ended, with the share of each ending
- wins by persona and by seat, and persona matchups, each with a 95% range
- game length, and how often each bot rule was used
- warnings, crashes, and seeds worth replaying

A *95% range* is how far the true win rate could plausibly be from this sample. Two ranges that overlap are not a real difference; play more games to narrow them.

Bot results describe how the bots play, not how people play. Confirm a surprising result with a few model games before changing your rules.

### play

Plays one game with model players:

```sh
bundle exec plai_testr hearts play
bundle exec plai_testr hearts play --seed 12 --model qwen3:30b --think
```

Before playing, `play` runs preflight: it checks Ollama, downloads missing models, warms them up, checks the first prompt fits the model's context, and plays 5 bot games to catch bugs. `--skip-preflight` skips it.

| Option | Effect |
|---|---|
| `--seed N` | The seed for shuffles and dice. Without it, a random seed from 1 to 100 is picked and printed. |
| `--model M` | The Ollama model for the players (default `qwen3:8b`). |
| `--think` | The model reasons before each choice. Stronger play, several times slower. |
| `--mode hybrid` | The bot plays moves its rules mark *obvious*; the model plays the rest. Faster. |
| `--mode bot` | No model at all; one bot game saved as a session. |
| `--players N` | Number of players, within the game's player count. |
| `--personas A,B` | One persona per player, in seat order; `*` for a random one (`--personas moon_shooter,*,*,*`). Default: random. |
| `--referee M` | A second model for yes/no rulings, for games that ask for them. |
| `--debrief-model M`, `--debrief-think` | A different model, or thinking, for the end-of-game debrief only. |

When the game ends, each player answers the game's debrief questions, and the report goes in `games/<game>/reports/<session_id>.md`:

- the result, model reliability (retries, invalid answers)
- how often the model agreed with the bot's obvious moves
- speed and wall time
- the debrief answers, and every decision with the model's reasoning

### resume

Ctrl+C (or `kill`, which sends SIGTERM) stops a game after the current move and saves it. Continue it with the session id it prints:

```sh
bundle exec plai_testr hearts resume 20261024-143012-a1b2
```

A resumed game plays exactly as it would have without the interruption. If the game's data, code or the PlAI Testr version changed since the game started, `resume` refuses, because it could no longer replay exactly; start a new game with `play`. Ctrl+C twice quits at once, losing only the move in progress.

### debrief

Asks a finished game's players the debrief questions again and rebuilds its report:

```sh
bundle exec plai_testr hearts debrief 20261024-143012-a1b2 --model qwen3:30b --think
```

By default it uses the game's player model, without thinking. Use it to try a bigger model, thinking, or changed debrief questions on the same game without replaying it. Earlier answers are kept in the saved game.

### preflight, compare, list

- `preflight` runs `play`'s checks without playing.
- `compare` writes a table of every finished model game, grouped by model and host: games, speed, reliability, endings and wins by persona. `--since 20261020` limits it to sessions from that date on (session ids start with the date and time).
- `list` shows every saved session with its status.

## Settings

`config/plai_testr.rb` holds settings for the whole app. All are commented out until you set them:

```ruby
PlaiTestr.configure do |config|
  config.max_decisions  = 100_000       # stops any game that runs this long
  config.player_model   = 'qwen3:8b'
  config.ollama_host    = 'localhost'
  config.ollama_port    = 11434
  config.model_settings = { context_size: 8192 }
end
```

Environment variables set the same defaults, handy for one-off runs: `PLAI_TESTR_PLAYER_MODEL`, `PLAI_TESTR_REFEREE_MODEL`, `PLAI_TESTR_OLLAMA_HOST`, `PLAI_TESTR_OLLAMA_PORT`.

```sh
PLAI_TESTR_OLLAMA_HOST=studio.local bundle exec plai_testr hearts play
```

To use Ollama on another computer, set `ollama_host` to its name or address, and start Ollama there with `OLLAMA_HOST=0.0.0.0` so it accepts connections from the network.

### Model settings

| Setting | Default | Used for |
|---|---|---|
| `context_size` | 8192 | How much text the model reads per turn (without `--think`); the referee |
| `long_context_size` | 16384 | Games with `--think`; the debrief |
| `menu_budget` | 512 | The longest answer allowed for a menu choice |
| `think_budget` | 8192 | The longest answer allowed for a thinking turn |
| `debrief_budget` | 1024 | The longest answer allowed for the debrief |
| `referee_budget` | 2048 | The longest answer allowed for a ruling |
| `temperature` | 0.6 | How varied the players' choices are |

Sizes and budgets are in tokens (roughly ¾ of a word each). Values outside sensible limits are adjusted with a warning, and the values used are listed in each report. A game can set its own in its registration.

## Output files

Each game folder holds:

- `reports/<session_id>.md`: a model game's report
- `reports/botrun-<time>.md`, `reports/comparison-<time>.md`: botrun and compare reports
- `sessions/<session_id>/state.json`: the saved game, replaced after every decision
- `sessions/<session_id>/transcript.jsonl`: one JSON object per decision, with the model's reasoning. After a crash the last line may be cut off.
- `sessions/<session_id>/think.log`: every model reply, with Ollama's timings

Both folders are ignored by git. Delete old sessions freely; reports don't depend on them, except that `resume` and `debrief` need theirs.

## Working effectively

A sequence that works well, from fast and cheap to slow and detailed:

1. **Botrun first.** `botrun --games 1000 --personas all` gives balance numbers in seconds to minutes, and finds crashes and games that never end. Rerun it after every rules change.
2. **Replay what looks odd.** The report lists seeds worth a look. `play --seed N --mode bot` replays one as a saved session, with every decision in its report.
3. **Hybrid model games.** `play --mode hybrid` checks a surprising bot result with model players, at a fraction of the time of a full model game.
4. **Full model games**, a few seeds at a time, for reasoning and debrief feedback. Use the same seeds when comparing models or rules versions, so the deals match.
5. **Compare.** `compare` puts models and hosts side by side.
6. **Re-debrief** instead of replaying, when you only want better answers about a game.

Larger models and `--think` play better but take far longer: try a small model without thinking first.

### Scripting

To play several seeds in a row:

```sh
for seed in 1 2 3; do
  bundle exec plai_testr hearts play --seed "$seed" --quiet || break
done
```

- `--quiet` prints only a progress line and the result; `--verbose` adds the raw model output (`play`) or every game (`botrun`).
- An interrupted `play` exits with status 130, so `|| break` stops the loop on Ctrl+C.
- Errors print one line. `PLAI_TESTR_DEBUG=1` shows the full backtrace.
- A botrun prints its report when it finishes, so it can be piped: `bundle exec plai_testr hearts botrun --games 1000 | less`.
