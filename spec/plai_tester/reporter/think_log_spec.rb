require 'spec_helper'

RSpec.describe PlaiTester::Reporter::ThinkLog do
  let(:text) do
    <<~LOG
      [2026-10-14T10:00:00Z] model=qwen3:8b prompt_tokens=4000 prompt_tps=800.0 eval_tokens=90 eval_tps=40.5 load_s=2.0 total_s=7.5
      {"choice": 1, "reasoning": "[not a header] model=nope"}
      ---

      [2026-10-14T10:03:00Z] model=qwen3:8b prompt_tokens=5000 prompt_tps=1000.0 eval_tokens=110 eval_tps=39.5 load_s=0.0 total_s=6.5
      {"choice": 2}
      ---
      [2026-10-14T10:04:00Z] model=llama3.2:3b prompt_tokens=300
    LOG
  end

  subject(:log) { described_class.new(text) }

  it 'reads one call per header line' do
    expect(log.calls.map { |c| c['model'] }).to eq(['qwen3:8b', 'qwen3:8b', 'llama3.2:3b'])
  end

  it 'averages a stat over the calls that logged it' do
    expect(log.average('total_s')).to eq(7.0)
    expect(log.average('prompt_tokens')).to eq(3100.0)
  end

  it 'measures minutes from the first call to the last' do
    expect(log.minutes).to eq(4.0)
  end

  it 'handles a missing log' do
    empty = described_class.load('/nonexistent/think.log')

    expect([empty.calls, empty.minutes, empty.average('total_s')]).to eq([[], nil, nil])
  end
end
