# PlAI Testr

Automated tabletop game playtesting with local LLM players via [Ollama](https://ollama.com).

You describe your game to PlAI Testr as a set of rules it can enforce. Each turn it lists the legal moves as a numbered menu, a player picks one, and PlAI Testr applies it, saves the game, and moves on. The player can be a local language model, which reasons about its choices and answers questions about the game afterwards, or a scripted bot, which plays thousands of games in minutes. Every session ends in a markdown report.

- **Botruns**: bots play hundreds or thousands of games for balance numbers: who wins, from which seat, with which strategy, how games end and how long they take.
- **Model games**: language models play a full game, explaining each choice, then answer debrief questions about how it felt and what was confusing.
- **Personas**: give players different strategies and play styles, and compare how each fares.
- **Everything runs on your machine.** No accounts or API keys; bots need no model at all.

## Requirements

Ruby 3.4+, and [Ollama](https://ollama.com) for model games (local or on your network; botruns don't need it).

## Quick start

```sh
gem install plai_testr
plai_testr new my_playtests    # an app with two example games: Hearts and Gin Rummy
cd my_playtests
bundle install

bundle exec plai_testr hearts botrun --games 100   # bots only: a report in seconds
bundle exec plai_testr gin_rummy play              # one model game (downloads qwen3:8b if missing)
```

## Documentation

- [Getting started](docs/getting-started.md): install PlAI Testr and Ollama, create your app, and check that everything works. Start here.
- [Ingesting a game with an agent](docs/ingesting-a-game-with-an-agent.md): have an AI coding assistant (Claude Code or similar) build the harness for your game, and what to give it.
- [Ingesting a game manually](docs/ingesting-a-game-manually.md): build the harness yourself in Ruby, step by step, with links to the technical reference.
- [Running playtests](docs/running-playtests.md): every command and option, settings, output files, and how to get useful results.

Reference:

- [Technical reference](docs/technical/): how the runner, state, components, personas, bots, debriefs, reports and specs work, for anyone writing or reviewing harness code.
- [Agent guide](docs/AGENTS.md): instructions written for AI assistants working in a PlAI Testr app. Your app's `CLAUDE.md` imports it.
- [Changelog](CHANGELOG.md): what changed in each version, and how to upgrade an existing app.

## Development

```sh
bundle install
bundle exec rspec
```

`lib/plai_testr/` holds the gem: [`session/runner.rb`](lib/plai_testr/session/runner.rb) (the decision loop and hooks), [`agents/`](lib/plai_testr/agents) (Ollama client, player and referee prompts), [`reporter/`](lib/plai_testr/reporter), [`state/`](lib/plai_testr/state), [`cli.rb`](lib/plai_testr/cli.rb), [`preflight.rb`](lib/plai_testr/preflight.rb), [`botrun.rb`](lib/plai_testr/botrun.rb). `templates/` holds what `new` and `generate game` copy, including the example games and their specs.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
