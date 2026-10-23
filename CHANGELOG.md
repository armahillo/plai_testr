# Changelog

## 0.1.1 (2026-10-23)

- Author name in the gemspec and license.

## 0.1.0 (2026-10-23, yanked)

First public release.

- `plai_testr new` creates a playtesting app with two example games (Hearts, Gin Rummy); `plai_testr generate game` adds a game skeleton.
- `play` runs one model game with preflight checks; `botrun` plays many bot-only games and reports balance; `resume`, `compare`, `list` and `preflight` round it out.
- Games list their legal moves as a numbered menu; the model picks one. Bot rules can play obvious moves (hybrid mode) or every move (bot mode).
- Personas (`personas.yml`) and bot parameters (`bots.yml`) per game.
- Checkpoints after every decision; resume refuses sessions whose game has changed.
- Configurable decision limit and model settings in `config/plai_testr.rb`.
