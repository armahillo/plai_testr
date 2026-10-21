require 'spec_helper'

RSpec.describe PlaiTestr::EventLog do
  let(:entries) { [] }

  subject(:log) { described_class.new(entries) }

  before do
    log.add('Alice attacks.', turn: 1)
    log.add('You see Bob\'s hand.', turn: 2, to: 'Alice')
    log.add('Bob dodges.', turn: 3)
  end

  it 'writes into the array it was given, so the log lives in game state' do
    expect(entries.length).to eq(3)
  end

  it 'shows private entries only to their player' do
    expect(log.visible_to('Bob').map { |e| e['text'] }).to eq(['Alice attacks.', 'Bob dodges.'])
    expect(log.recent_for('Alice', 2)).to eq(["(private) You see Bob's hand.", 'Bob dodges.'])
  end

  it 'tags a line logged during a bot or random decision for the acting player only' do
    log.add('Bob plays 3♣.', turn: 4, actor: 'Bob', tag: 'BOT')

    expect(log.recent_for('Bob', 1)).to eq(['BOT: Bob plays 3♣.'])
    expect(log.recent_for('Alice', 1)).to eq(['Bob plays 3♣.'])
  end
end

RSpec.describe PlaiTestr, '.rename' do
  it 'swaps player ids for display names, longest id first' do
    names = { 'Player 1' => 'grinder', 'Player 10' => 'hunter' }

    expect(PlaiTestr.rename('Player 10 attacks Player 1.', names)).to eq('hunter attacks grinder.')
  end
end
