require 'spec_helper'

RSpec.describe GinRummy::Melds do
  let(:deck) { PlaiTester::Deck.build(PlaiTester::Compiler::RulesLoader.load(PlaiTester.load('gin_rummy').rules_file)) }

  def cards(*names) = names.map { |name| deck.find { |c| c['name'] == name } }
  def names(cards)  = cards.map { |c| c['name'] }

  it 'finds the arrangement with the least deadwood' do
    best = described_class.best(cards('7♣', '7♦', '7♥', '8♥', '9♥', 'K♠', 'A♣'))

    expect(best.melds.map { |m| names(m) }).to eq([%w[7♥ 8♥ 9♥]])
    expect(best.points).to eq(25)
  end

  it 'plays aces low only' do
    expect(described_class.best(cards('A♠', '2♠', '3♠')).points).to eq(0)
    expect(described_class.best(cards('Q♠', 'K♠', 'A♠')).points).to eq(21)
  end

  it 'lays off deadwood onto runs and sets' do
    melds = [cards('4♠', '5♠', '6♠'), cards('9♣', '9♦', '9♥')]

    expect(names(described_class.lay_off(cards('3♠', '7♠', '9♠', 'K♦'), melds))).to eq(['K♦'])
  end
end
