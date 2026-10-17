module GinRummy
  module Melds
    Arrangement = Data.define(:melds, :deadwood) do
      def points = Melds.points(deadwood)
    end

    def self.value(card)   = [card['rank'], 10].min
    def self.points(cards) = cards.sum { |c| value(c) }

    def self.best(cards) = search(cards, candidates(cards))

    def self.lay_off(cards, melds)
      melds = melds.map(&:dup)
      cards = cards.dup

      while (card = cards.find { |c| melds.any? { |m| fits?(c, m) } })
        melds.find { |m| fits?(card, m) } << card
        cards.delete(card)
      end
      cards
    end

    def self.candidates(cards)
      sets = cards.group_by { |c| c['rank'] }.values.select { |g| g.length >= 3 }
                  .flat_map { |g| g.length == 4 ? [g, *g.combination(3)] : [g] }
      runs = cards.group_by { |c| c['suit'] }.values.flat_map do |suited|
        suited.sort_by { |c| c['rank'] }.slice_when { |a, b| b['rank'] != a['rank'] + 1 }.flat_map do |streak|
          (3..streak.length).flat_map { |size| streak.each_cons(size).to_a }
        end
      end
      sets + runs
    end

    def self.search(cards, candidates)
      candidates.each_with_index.reduce(Arrangement.new(melds: [], deadwood: cards)) do |best, (meld, i)|
        next best unless (meld - cards).empty?

        rest = search(cards - meld, candidates.drop(i + 1))
        rest.points < best.points ? Arrangement.new(melds: [meld, *rest.melds], deadwood: rest.deadwood) : best
      end
    end

    def self.fits?(card, meld)
      ranks = meld.map { |c| c['rank'] }

      if ranks.uniq.one? then card['rank'] == ranks.first && meld.length < 4
      else card['suit'] == meld.first['suit'] && [ranks.min - 1, ranks.max + 1].include?(card['rank'])
      end
    end
  end
end
