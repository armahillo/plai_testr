require 'spec_helper'

RSpec.describe PlaiTestr::Reporter::ModelComparison do
  let(:tmp) { Dir.mktmpdir('plai_comparison_spec_') }

  def write_session(id, host:, model: 'qwen3:8b', status: 'completed', total_s: 6.0)
    dir = File.join(tmp, id)
    FileUtils.mkdir_p(dir)
    state = { 'status' => { 'end_reason' => 'yield' }, 'data' => { 'player_model' => model, 'host' => host, 'seed' => 1 } }
    File.write(File.join(dir, 'state.json'), JSON.generate('status' => status, 'game_state' => state, 'turn_log' => [{ 'attempts' => 2 }]))
    File.write(File.join(dir, 'think.log'), "[2026-10-14T10:00:00Z] model=#{model} prompt_tokens=4000 total_s=#{total_s} eval_tps=40.0\n")
  end

  after { FileUtils.rm_rf(tmp) }

  it 'puts each model and host on its own row with speed and reliability' do
    write_session('a', host: 'desktop', total_s: 4.0)
    write_session('b', host: 'laptop',  total_s: 8.0)
    write_session('c', host: 'laptop',  status: 'interrupted')

    table = described_class.new(tmp).to_markdown

    expect(table).to include('| `qwen3:8b` | desktop | 1 | 1 | — | 4.0 |', '| `qwen3:8b` | laptop | 1 | 1 | — | 8.0 |', 'yield 1')
  end

  it 'adds the columns a game supplies' do
    write_session('a', host: 'desktop')
    game_comparison = Class.new(described_class) do
      private

      def extra_columns = [['Seeds squared', ->(list) { list.sum { |s| s[:seed]**2 } }]]
    end

    table = game_comparison.new(tmp).to_markdown

    expect(table).to include('| Seeds squared |', '| 1 | — |')
  end
end
