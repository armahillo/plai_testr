require 'spec_helper'

RSpec.describe PlaiTestr::Reporter::BotrunReport do
  def report(results, personas: nil)
    described_class.new(results, game: 'Test', version: '1.0.0', seconds: 1.0, personas: personas).to_markdown
  end

  let(:plain)   { [{ 'seed' => 1, 'winner' => 'Player 1', 'names' => { 'Player 1' => 'Player 1' }, 'decisions' => 3, 'rules' => {} }] }
  let(:persona) { [plain.first.merge('personas' => { 'Player 1' => 'grinder' })] }

  it 'leaves personas out of the header for games without them' do
    expect(report(plain)).not_to include('**Personas**')
  end

  it 'shows personas the games assigned at random' do
    expect(report(persona)).to include('| **Personas** | random per seed |')
  end

  it 'shows the personas that were asked for' do
    expect(report(persona, personas: %w[grinder riposter])).to include('| **Personas** | grinder, riposter |')
  end
end
