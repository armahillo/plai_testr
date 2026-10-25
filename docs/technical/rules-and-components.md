# Rules and components

A game's `data/` folder describes the game: what the model players read, the numbers the engine uses, and the components.

## `data/rules.md`

The rules text the model players read every turn (the default `rules_text_for`). Write it for a player, not a programmer.

- End it with a **Rulings** section: rules questions settled with the designer, dated, so models and future readers see them.
- Add a **Simplifications** section for any rule the harness deliberately simplifies (see `games/gin_rummy`).
- Keep open questions and engine choices the designer hasn't confirmed out of `rules.md`, in `games/<name>/NOTES.md`, until they're settled.
- If the rules are long, override `rules_text_for` to send only the sections the current step needs, calling `super` for the file.

## `data/rules.json`

```json
{
  "game": {
    "name": "Hearts",
    "version": "1.0.0",
    "description": "A 4-player trick-taking card game. ...",
    "player_count": { "min": 4, "max": 4, "default": 4 }
  },
  "points_to_end": 100
}
```

- `game.name` and `game.version` are required. The version appears in every report, so bump it when the rules change.
- `game.description` is what the model players read first.
- `game.player_count` sets the allowed `--players` range and the default. The [standard checks](specs.md) play every count in the range.
- Anything else is the game's: points to win, hand sizes, limits. The runner reads them from `@rules` (`@rules['points_to_end']`), so tuning a number needs no code change.

The file is validated when the game loads, and errors name the field.

## Components

Card lists, tiles and other components go in `data/components/`, one file per component, named after the file:

```ruby
PlaiTestr::Deck.build(@rules, component: 'cards')   # data/components/cards.csv (or .yml, .json)
PlaiTestr::Deck.build(@rules)                       # the first component
```

`Deck.build` returns a list of hashes with string keys, one per copy, each with its own `uid` (1, 2, 3, … in file order). Shuffle it with `@rng`: `Deck.build(@rules).shuffle(random: @rng)`.

A component file is a list of records:

- **CSV**: a header row, then one row per entry. Numbers become numbers; empty cells are left out.
- **YAML or JSON**: a list of hashes.

A `copies` field makes that many copies. A malformed file fails to load with the file and entry named. Both example games read `data/components/cards.csv`.

A component can also be inline under `components` in `rules.json` (`{ "name": "deck", "type": "card_deck", "values": [...] }`), but files are easier to edit and review.

### Converting a designer's files

PlAI Testr reads only this format. Converting a designer's own files (spreadsheets, YAML with metadata, exports from card tools) is the game's job:

- Keep the fields the engine or the players need; leave out print layout, art notes and other metadata.
- If the source keeps changing, write a small rerunnable script in the game folder (`games/<name>/import.rb`) that rebuilds the file, and a spec that fails when the copy is behind.
- Check the counts (cards per type, total) after converting.
