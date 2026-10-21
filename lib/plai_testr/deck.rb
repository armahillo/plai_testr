module PlaiTestr
  module Deck
    def self.build(rules, component: nil)
      deck = rules.fetch('components', []).find { |c| c['type'] == 'card_deck' && (component.nil? || c['name'] == component) }
      return [] unless deck

      deck.fetch('values', []).flat_map { |card| Array.new(card.fetch('copies', 1)) { card.except('copies') } }
          .each.with_index(1).map { |card, uid| card.merge('uid' => uid) }
    end
  end
end
