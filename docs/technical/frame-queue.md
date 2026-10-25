# Nested decisions with FrameQueue

Most turns are one decision: the active player picks from a menu. Some games need decisions *inside* other decisions: an attack the defender may block, a card that triggers an opponent's response, an effect that asks someone else to choose. `PlaiTestr::Session::FrameQueue` handles these.

## The idea

A **frame** is one pending step: a hash with a `type`, the `player` who decides it (if anyone), and any data the step needs. Frames live on a stack in game state, so a checkpoint saved in the middle of an attack resumes in the middle of that attack.

- The frame on top of the stack is the current decision. `next_player` and `legal_moves` read it.
- When the player picks a move, `resolve_frame(params)` pops the frame and calls `on_<type>(frame, params)`.
- Handlers push new frames for whatever happens next. **The last frame pushed resolves first.**
- Frames marked `auto: true` need no decision: they are popped and resolved with `on_<type>(frame)` as soon as they reach the top.
- When the stack is empty, `schedule_frames` pushes the next normal turn.

## What you implement

| Method | Purpose |
|---|---|
| `frame_queue` | The array that holds the frames, kept in `@game_state.data` |
| `schedule_frames` | Push the next turn's frame(s) when the stack is empty |
| `on_<type>(frame, params)` | Resolve a decision frame |
| `on_<type>(frame)` | Resolve an `auto` frame |
| `halt_frames?` | Optional. Stop resolving (default: `game_over?`). A good place for end checks and safety caps |
| `intercept_frame(frame)` | Optional. Return true to stop before a frame and handle it in your own code (e.g. hand maintenance) |

You call `advance_frames` once at the end of `setup`, and `resolve_frame(action.values.first)` from `apply_action_effects`. `frame_for(type, player, **data)` builds a frame. The hooks in the table are public; `advance_frames`, `resolve_frame`, `frame` and `frame_for` are private helpers your runner calls.

## Example: attack and block

Each turn the attacker plays a card. The defender may block with a card of equal or higher value, or take the damage. Damage is an `auto` frame, so it resolves without a decision; reaching 10 damage loses.

```ruby
module Strike
  module Session
    class Runner < PlaiTestr::Session::Runner
      include PlaiTestr::Session::FrameQueue

      HAND_SIZE = 4
      KNOCKOUT  = 10

      def setup
        deck = PlaiTestr::Deck.build(@rules).shuffle(random: @rng)
        players.each { |p| hand(p).concat(deck.shift(HAND_SIZE)) }
        data.merge!('queue' => [], 'deck' => deck, 'damage' => players.to_h { |p| [p, 0] }, 'attacker' => players.first)
        advance_frames
      end

      def frame_queue = data['queue']

      def schedule_frames
        attacker = data['attacker']
        hand(attacker).concat(data['deck'].shift(HAND_SIZE - hand(attacker).length))
        frame_queue.push(frame_for('attack', attacker))
      end

      def halt_frames?
        end_game(nil, 'deck_empty') if !game_over? && data['deck'].empty? && hand(data['attacker']).empty?
        game_over?
      end

      def next_player = frame['player']

      def legal_moves(player)
        case frame['type']
        when 'attack'
          hand(player).map { |c| option("Attack with #{c['name']}", attack: { value: c['uid'] }) }
        when 'block'
          blockers = hand(player).select { |c| c['value'] >= frame['value'] }
          blockers.map { |c| option("Block with #{c['name']}", block: { value: c['uid'] }) } + [option("Take #{frame['value']} damage", block: {})]
        end
      end

      def apply_action_effects(_player, action) = resolve_frame(action.values.first)

      private

      def on_attack(frame, params)
        card     = take(frame['player'], params[:value])
        defender = opponent(frame['player'])
        frame_queue.push(frame_for('block', defender, value: card['value']))
      end

      def on_block(frame, params)
        if params[:value]
          take(frame['player'], params[:value])
        else
          frame_queue.push(frame_for('damage', frame['player'], auto: true, amount: frame['value']))
        end
        data['attacker'] = frame['player']
      end

      def on_damage(frame)
        data['damage'][frame['player']] += frame['amount']
        end_game(opponent(frame['player']), 'knockout') if data['damage'][frame['player']] >= KNOCKOUT
      end

      def end_game(winner, reason)
        @game_state.apply_changes('status' => { 'game_over' => true, 'winner' => winner, 'end_reason' => reason })
      end

      def take(player, uid) = hand(player).delete_at(hand(player).index { |c| c['uid'] == uid })
      def opponent(player)  = (players - [player]).first
      def players           = @game_state.players
      def hand(player)      = @game_state.player_state(player).hand
    end
  end
end
```

The sequence for one exchange:

1. The stack is empty, so `schedule_frames` pushes `attack` for Player 1.
2. Player 1 attacks; `on_attack` pushes `block` for Player 2. It is not `auto`, so play stops for Player 2's decision.
3. Player 2 takes the damage; `on_block` pushes an `auto` `damage` frame, which resolves at once.
4. The stack is empty again, so `schedule_frames` pushes `attack` for Player 2.

## Tips

- **Stack order.** To have A happen before B, push B first, then A.
- **Pick-N frames.** Put `pick: [min, max]` on the frame and return `frame['pick']` from `pick_range`.
- **Say what the frame is for.** `turn_phase` can return `frame['type']`, and views should say why the player is deciding ("Player 1 attacks with Blade 5: block or take 5 damage").
- **Cap runaway auto-frame loops in `halt_frames?`.** The decision limit (`max_decisions`) counts only decisions, so a loop of `auto` frames never reaches it. Count resolved frames and end the game past a limit the players never see.
- **Bot rules** read `frame['type']` the same way `legal_moves` does.
