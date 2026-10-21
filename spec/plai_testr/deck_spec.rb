require 'spec_helper'

RSpec.describe PlaiTestr::Deck do
  let(:rules) do
    { 'components' => [
      { 'type' => 'token', 'name' => 'Aggressor' },
      { 'type' => 'card_deck', 'name' => 'Cards', 'values' => [{ 'name' => 'A', 'copies' => 2 }, { 'name' => 'B' }] }
    ] }
  end

  it 'expands copies and numbers every card from 1' do
    expect(described_class.build(rules)).to eq([{ 'name' => 'A', 'uid' => 1 }, { 'name' => 'A', 'uid' => 2 }, { 'name' => 'B', 'uid' => 3 }])
  end

  it 'returns no cards when there is no card deck' do
    expect(described_class.build({ 'components' => [] })).to eq([])
  end
end
