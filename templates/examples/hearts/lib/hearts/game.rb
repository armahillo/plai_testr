module Hearts
  SUITS      = %w[clubs diamonds spades hearts].freeze
  HAND_SIZE  = 13
  PASS_COUNT = 3
  PASSES     = %w[left right across hold].freeze
  SEAT_SHIFT = { 'left' => 1, 'right' => -1, 'across' => 2 }.freeze
  QUEEN      = 'Q♠'
  OPENER     = '2♣'
  MOON       = 26

  def self.points(card)
    return 13 if card['name'] == QUEEN

    card['suit'] == 'hearts' ? 1 : 0
  end
end
