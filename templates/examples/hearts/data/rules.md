# Hearts

v1.0.0

A trick-taking game for 4 players. Points are bad: the player with the **fewest** points when the game ends wins.

## Cards

A standard 52-card deck. Aces are high. Each heart (♥) is worth 1 point; the Queen of Spades (Q♠) is worth 13. All other cards are worth nothing.

## Each hand

1. **Deal.** Every player gets 13 cards.
2. **Pass.** Each player chooses 3 cards to pass, without seeing what they receive. The direction rotates every hand: left, right, across, then no passing (hold), and repeats.
3. **Tricks.** The player holding the 2♣ leads it to start the first trick. Going clockwise, each player plays one card. You must follow the suit that was led if you can; if you cannot, you may play any card. The highest card of the suit led wins the trick, and its winner leads the next trick.
4. **Restrictions.**
   - On the first trick, you may not play a heart or the Q♠ unless you have nothing else.
   - You may not lead a heart until hearts are broken (a heart has been played on an earlier trick), unless your hand has only hearts.
5. **Scoring.** After all 13 tricks, each player adds the points in the tricks they took.
   - **Shooting the moon:** a player who takes all 13 hearts and the Q♠ scores 0, and every other player scores 26.

## End of the game

When any player has 100 or more points at the end of a hand, the game ends. The player with the fewest points wins; tied low scores share the win.

## Strategy notes

- Pass away the Q♠, high spades (A♠, K♠) and high hearts unless you have many low spades to protect them.
- Play just under the winning card to avoid taking tricks that carry points.
- When you cannot follow suit, it is a chance to drop the Q♠ or high hearts on someone else.
