# Getting started

This guide covers setting up PlAI Testr on your computer and checking that it works. You'll need to be comfortable typing commands into a terminal; you don't need to know Ruby or Ollama.

## Step 0: Prerequisites

### Hardware

Running a language model locally takes a lot of processing power, ideally a GPU. If your computer can't run a model well, PlAI Testr is still useful: botruns use no model at all. Personally, I've found Apple M-series computers well suited to this, but a fairly modern graphics card may be fine too. There's no harm in trying!

Models also take disk space. The default model, `qwen3:8b`, is about 5 GB.

### Ruby

PlAI Testr needs Ruby 3.4 or newer. Check with:

```sh
ruby -v
```

You should see something like `ruby 3.4.4 (...)`. If you don't have Ruby, or it's older, the [official installation guide](https://www.ruby-lang.org/en/documentation/installation/) lists the options. After installing, open a new terminal window before continuing.

### Ollama

[Ollama](https://ollama.com) is a free program that runs language models on your computer, with no internet connection needed once a model is downloaded. If you're on a Mac, I wrote a guide: [Setting up a local LLM on a MacOS device](https://armahillo.dev/guides/local-llm-macos/ollama.html). The steps are similar on other systems.

You don't need to download a model yourself; PlAI Testr downloads the one it needs the first time it runs. Ollama can also run on another computer on your network (see [Running playtests](running-playtests.md#settings)).

## Step 1: Install the gem

PlAI Testr is a Ruby *gem*: a package of Ruby code, installed with Ruby's `gem` command.

```sh
gem install plai_testr
```

## Step 2: Create your app

An *app* is a folder that holds your games, their settings and their results. This guide calls it `my_playtests`; I call mine `game_tester`. Pick a name in lowercase, with `_` instead of spaces and preferably only letters: `game_tester`, `my_playtests` and `simulator` are all fine; `Game Tester Software`, `MyPlaytests` and `Simulator9000` might work, but are best avoided.

```sh
plai_testr new my_playtests
cd my_playtests
bundle install
```

`bundle install` installs the other gems PlAI Testr depends on, at the versions this app needs. Gems depending on other gems is a common Ruby practice, comparable to `import` in Python or JavaScript. Run it again whenever the app's `Gemfile` changes.

From here on, commands start with `bundle exec`, as in `bundle exec plai_testr hearts botrun`. It tells Ruby to use the exact gem versions this app was set up with. Commands often work without it, but using it avoids version mix-ups.

### What's in the app

```
my_playtests/
  games/
    hearts/               Example game: 4-player trick-taking
    gin_rummy/            Example game: 2-player rummy
  config/plai_testr.rb    Settings for the whole app: model, Ollama address (all optional)
  AGENTS.md, CLAUDE.md    Instructions for AI coding assistants (see Ingesting a game with an agent)
  Gemfile                 The gems this app uses
  spec/                   Automated checks for every game
```

Each game lives entirely in its own folder under `games/`. Its results go in `games/<game>/reports/`, and saved games in `games/<game>/sessions/`.

Hearts and Gin Rummy are complete, working games. Use them to check your setup now, and as examples when you add your own game.

## Step 3: Check that it works

Run these in order, from the app folder. Each one tests a little more.

### Preflight (fast)

`preflight` checks that Ollama is running and reachable, downloads the model if it's missing, sends one test prompt, and plays a few quick bot games to catch mistakes in the game's code. The first run may take a while to download the model; after that it takes seconds.

```sh
bundle exec plai_testr gin_rummy preflight
```

```
Ollama at localhost:11434: reachable
  qwen3:8b: ready
  First prompt: 1196 of 8192 tokens
  Lint: 5 bot games played and debriefs built without errors
```

If Ollama isn't reachable, make sure the Ollama app is running and try again.

### A botrun (fast)

A botrun plays many games with scripted bots instead of a model: simple "if this, then that" rules, no reasoning. Bots are fast (100 or even 1000 games take seconds) and good at showing balance problems and dominant strategies.

```sh
bundle exec plai_testr gin_rummy botrun --games 100
```

The summary prints when it finishes and is saved in `games/gin_rummy/reports/`. It shows how games ended, win rates by strategy and seat, game lengths, and which bot rules were used.

### A model game (slow)

A model game is one full game played by a language model, which explains each choice and answers questions about the game at the end. It takes much longer: on my Apple M1 Max, a game of Hearts took 23 minutes for about 550 decisions.

```sh
bundle exec plai_testr hearts play
```

`play` runs preflight first, then shows each decision as it happens:

```
Turn 373 — Moon Shooter (Player 1) · hand 7 · trick 10 (4 options)
  🧠 LLM -> Play 10♦
Turn 374 — Safe Player (Player 2) · hand 7 · trick 10: Play K♦ (wins the trick so far) [only option]
Turn 375 — Moon Shooter (Player 3) · hand 7 · trick 10 (4 options)
  🧠 LLM -> Play 3♠ (cannot win this trick)
```

Press Ctrl+C to stop; the game is saved and can be continued later. When the game finishes, the players are asked the debrief questions, and the report's file name is printed. Reports are in `games/hearts/reports/`.

If all three worked, you're set up. Next:

- [Ingesting a game with an agent](ingesting-a-game-with-an-agent.md) or [manually](ingesting-a-game-manually.md), to add your own game.
- [Running playtests](running-playtests.md), for every command and option.

Looking for an easy first game to try? Model Blackjack ([rules](https://bicyclecards.com/how-to-play/blackjack), public domain) and give its bots a few different strategies. The ingesting guides use it as their example.

## Updating PlAI Testr

```sh
gem update plai_testr
bundle update plai_testr
```

The app's `Gemfile` allows updates within the same minor version (for example 0.2.x). To move to a new one, change the version in the `Gemfile` (`gem 'plai_testr', '~> 0.3'`) and run `bundle update plai_testr`.

Before updating, read the [changelog](../CHANGELOG.md): versions that need changes to existing apps or games list them under *Upgrading an existing app*. Then run `bundle exec rspec` to check every game still works.

A game saved under one version can't be resumed under another; finish interrupted games before updating, or start them again.
