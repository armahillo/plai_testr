# Technical reference

How PlAI Testr works, for anyone writing or reviewing harness code. [Ingesting a game manually](../ingesting-a-game-manually.md) gives the order to build a game in; these pages cover each part in depth.

- [The runner](runner.md): the decision loop, every hook, moves and actions, helpers, randomness and limits, checking a prompt
- [State](state.md): game and player state, hidden information, checkpoints and resume
- [Rules and components](rules-and-components.md): `rules.json`, `rules.md`, and component files
- [Personas and bots](personas-and-bots.md): `personas.yml`, `bots.yml`, `bot_choice`, and the bot's part in model games
- [Debrief](debrief.md): how the debrief prompt is built, and writing good facts and questions
- [Reports](reports.md): adding sections to session and botrun reports
- [Specs](specs.md): the standard checks every game runs, and writing rules specs
- [Nested decisions with FrameQueue](frame-queue.md): attacks and responses, triggered effects, decisions inside decisions
- [Yes/no rulings with the referee](referee.md): rulings on free-text conditions by a second model

The source is the final word: hooks and their defaults are in [`lib/plai_testr/session/runner.rb`](../../lib/plai_testr/session/runner.rb), and the example games in [`templates/examples/`](../../templates/examples) use most of what's described here.
