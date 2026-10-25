# Reports

Every model game and botrun ends in a markdown report. The gem's sections cover what every game has; a game adds its own for what matters in that game.

## Session reports

Each model game's report (`reports/<session_id>.md`) has a header (session, rules version, players and personas, model and settings, seed, decisions, wall time), then the result, model reliability, bot agreement, speed, warnings, the debrief, and the turn log.

`report_sections` adds sections after the gem's own, as an array of markdown strings:

```ruby
def report_sections
  rows = players.map { |p| "| #{p} | #{pstate(p).score} | #{data.dig('tally', p, 'hearts')} |" }
  ["## Hearts\n\n| Player | Score | Hearts taken |\n|---|---|---|\n#{rows.join("\n")}"]
end
```

Tables are aligned automatically. Return `false` from `report_debrief?` to leave out the gem's debrief section and render the answers yourself in `report_sections` (from `data['debrief']`).

Reports are rebuilt from saved state (by `resume` and `debrief`), so compute sections from `data`, not instance variables.

## Botrun reports

A botrun keeps a small result for each game: seed, winner, personas, end reason, decisions, bot rules used, warnings. The report summarizes them: endings, wins by persona and seat, matchups, game length, bot rules, and seeds worth replaying.

To add game-specific numbers:

1. Return them from `botrun_stats` in the runner, as JSON-safe values. It is called once at the end of each game.

   ```ruby
   def botrun_stats = { 'hands' => data['hand'], 'taken' => totals }
   ```

2. Subclass `PlaiTestr::Reporter::BotrunReport` and return extra sections from `extra_sections`. Each game's numbers are in `@played` (games that didn't crash), under `'stats'`. `table(title, headers, rows, note)`, `pct` and `percentile` are available.

   ```ruby
   module Hearts
     module Reporter
       class BotrunReport < PlaiTestr::Reporter::BotrunReport
         private

         def extra_sections
           counts = @played.filter_map { |r| r.dig('stats', 'hands') }.sort
           [table('## Hands per game', %w[Mean Max], ["| #{counts.sum.fdiv(counts.length).round(1)} | #{counts.max} |"])]
         end
       end
     end
   end
   ```

3. Register it: `PlaiTestr.register('hearts', ..., botrun_report_class: Hearts::Reporter::BotrunReport)`.

`botrun_stats` doubles as the debrief facts when a game has no `debrief_facts`.

## Model comparison

`compare` reads every finished session and writes one row per model and host. To add columns, subclass `PlaiTestr::Reporter::ModelComparison`, override `extra_columns` (a list of `[header, ->(sessions) { value }]` pairs; each session is a hash with `:state`, its saved game state, plus `:turns` and `:seed`) and `notes` (footnotes), and register it with `comparison_class:`.
