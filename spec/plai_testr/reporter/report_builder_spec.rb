require 'spec_helper'
require 'tmpdir'

RSpec.describe PlaiTestr::Reporter::ReportBuilder do
  around do |example|
    Dir.mktmpdir do |dir|
      PlaiTestr.reports_dir = dir
      example.run
    ensure
      PlaiTestr.reports_dir = nil
    end
  end

  let(:answers) { { 'Player 1' => [{ 'question' => 'What was unclear?', 'answer' => 'When hearts are broken.' }, { 'question' => 'What felt automatic?', 'answer' => '' }] } }
  let(:state)   { PlaiTestr::State::GameState.new(players: ['Player 1', 'Player 2'], current_state: { 'data' => { 'debrief' => answers } }) }
  let(:rules)   { { 'game' => { 'name' => 'Test', 'version' => '1.0.0' } } }

  def report(**options)
    File.read(described_class.new(session_id: 'test', rules: rules, game_state: state, turn_log: [], names: { 'Player 1' => 'Ana' }, **options).build)
  end

  it 'lists each player’s debrief answers' do
    expect(report).to include("## Debrief\n\n**Ana**\n\n- *What was unclear?*\n  When hearts are broken.\n- *What felt automatic?*\n  _(no answer)_")
  end

  it 'leaves the debrief out for games that report it themselves' do
    expect(report(debrief: false)).not_to include('## Debrief')
  end

  it 'marks who decided each turn and shows display names in the turn log text' do
    turns = [{ 'turn' => 1, 'player' => 'Player 1', 'label' => 'Player 1 plays 3♣', 'decider' => 'BOT', 'rule' => 'lead_low' },
             { 'turn' => 2, 'player' => 'Player 2', 'label' => 'Play 4♣', 'decider' => 'RNG', 'fallback' => true }]
    text  = File.read(described_class.new(session_id: 'test', rules: rules, game_state: state, turn_log: turns, names: { 'Player 1' => 'Ana' }).build)

    expect(text).to include('- **1. Ana:** 🤖 Ana plays 3♣ _(rule: lead_low)_', '- **2. Player 2:** 🎲 Play 4♣ **[FALLBACK]**')
  end

  it 'lists warnings once each, with a count' do
    expect(report(warnings: %w[dup dup other])).to include("## Warnings\n\n- dup (×2)\n- other")
  end

  it 'leaves the debrief out when there was none' do
    state.data.delete('debrief')

    expect(report).not_to include('## Debrief')
  end
end
