# Gin Rummy harness notes

For the designer and anyone working on this harness. Model players never see this file.

## Hidden safety caps

- `MAX_TURNS` (120 turns in one hand): the hand is a draw, logged as an ordinary drawn hand and counted as `turn_cap` in `data['results']`. Small models can swap the same few cards through the discard pile forever; a 2026-10-17 qwen3:8b test went 155 turns in hand 1 before the draw options showed deadwood.
- `MAX_HANDS` (50 hands): the game ends and the higher score wins (`hand_limit`).

## Open questions

- None yet.
