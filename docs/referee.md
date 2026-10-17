# Yes/no rulings with the referee

Prefer encoding rules in Ruby: it is fast, deterministic and testable. Some conditions are awkward to encode, though, especially free-text card conditions in a game that is still changing ("If your opponent is ahead…", "If this is your first attack this turn…"). The referee is a second model that answers one yes/no question about such a condition.

## How it works

Run with `--referee <model>` (or set `PLAITESTER_REFEREE_MODEL`). The runner then has `@referee`, an `Agents::RefereeAgent`; without the option, `@referee` is `nil`.

```ruby
@referee.ruling(question: 'Is the condition on Ambush met?', facts: "...")
# => { 'met' => true, 'why' => 'The opponent has 12 points and the player has 8.', 'fallback' => false }
```

The referee sees only the game's name, the question and the facts you pass, with thinking on and temperature 0.1. If it cannot produce a valid answer after retries, it returns `met: false` with `fallback: true`.

Nothing calls the referee for you, and rulings are not added to reports automatically. Your runner asks, records and reports.

## Example: a card with a free-text condition

Cards in `rules.json` carry their condition as text:

```json
{ "name": "Ambush", "value": 2, "condition": "your opponent has more points than you", "bonus": 3, "copies": 2 }
```

When a card with a condition is played, the runner asks for a ruling and records it (`custom` and `log` are the helpers the example games define):

```ruby
def bonus_for(player, card)
  return 0 unless card['condition']

  ruling = ruling("Is this condition met for #{player}: #{card['condition']}?", view_text_for(player))
  ruling['met'] ? card['bonus'] : 0
end

def ruling(question, facts)
  result = if @referee
             @referee.ruling(question: question, facts: facts)
           else
             { 'met' => false, 'why' => 'no referee: run with --referee to rule on conditions', 'fallback' => true }
           end
  (custom['rulings'] ||= []) << result.merge('turn' => @game_state.turn + 1, 'question' => question)
  log("Ruling: #{question} #{result['met'] ? 'Yes' : 'No'} (#{result['why']})")
  result
end

def report_sections
  rows = custom.fetch('rulings', []).map { |r| "| #{r['turn']} | #{r['question']} | #{r['met'] ? 'yes' : 'no'} | #{r['why']}#{' (fallback)' if r['fallback']} |" }
  ["## Rulings\n\n| Turn | Question | Met | Why |\n|---|---|---|---|\n#{rows.join("\n")}"]
end
```

## Things to know

- **Facts are everything.** The referee knows nothing about the game state except the facts string. Passing the deciding player's view (`view_text_for`) is a good default; add anything the question depends on.
- **Botruns and `--mode bot` have no referee.** Decide the fallback on purpose (above: the condition is not met) and say so in the log, or give the bot its own Ruby check for the condition.
- **Rulings break seed reproducibility.** The same seed can play differently when a ruling changes. Record every ruling, as above, so a report shows why.
- **Rulings are slow.** Each is a model call with thinking on. Ask only when the condition actually matters (a card with a condition was played), never on every turn.
- **Turn rulings into code.** When a condition comes up often and the designer agrees on what it means, encode it in Ruby and keep the referee for the rest.
