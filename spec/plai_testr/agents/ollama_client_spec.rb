require 'spec_helper'

RSpec.describe PlaiTestr::Agents::OllamaClient do
  subject(:client) { described_class.new }

  let(:done) { { 'message' => { 'content' => '{}' }, 'prompt_eval_count' => 100, 'model' => 'm' } }

  it 'sends think, format and keep_alive as top-level fields, not inside options' do
    expect(client).to receive(:post) do |path, payload|
      expect(path).to eq('/api/chat')
      expect(payload).to include(think: false, format: 'json', keep_alive: '30m')
      expect(payload[:options]).to eq(temperature: 0.2, num_ctx: 4096)
      done
    end

    client.chat(model: 'm', messages: [], temperature: 0.2, think: false, num_ctx: 4096, format: 'json', keep_alive: '30m')
  end

  it 'omits optional fields that were not given' do
    expect(client).to receive(:post) do |_path, payload|
      expect(payload.keys).to contain_exactly(:model, :messages, :stream, :options)
      done
    end

    client.chat(model: 'm', messages: [])
  end

  it 'flags a prompt that nearly fills the context window (Ollama truncates silently)' do
    allow(client).to receive(:post).and_return(done.merge('prompt_eval_count' => 3900))

    expect(client.chat(model: 'm', messages: [], num_ctx: 4096)).to include('context_full' => true)
    expect(client.chat(model: 'm', messages: [], num_ctx: 8192)).not_to have_key('context_full')
  end

  it 'raises a ModelError when Ollama cannot be reached' do
    unreachable = described_class.new(host: '127.0.0.1', port: 1)

    expect { unreachable.model_names }.to raise_error(PlaiTestr::ModelError, /Cannot reach Ollama at 127.0.0.1:1/)
  end

  it 'formats Ollama timing stats for the think log, and the think log reads them back' do
    stats = { 'prompt_eval_count' => 4000, 'prompt_eval_duration' => 4_000_000_000, 'eval_count' => 80,
              'eval_duration' => 2_000_000_000, 'load_duration' => 500_000_000, 'total_duration' => 7_000_000_000 }

    line = client.send(:format_stats, stats)
    call = PlaiTestr::Reporter::ThinkLog.new("[2026-10-14T10:00:00Z] model=m#{line}").calls.first

    expect(line).to eq(' prompt_tokens=4000 prompt_tps=1000.0 eval_tokens=80 eval_tps=40.0 load_s=0.5 total_s=7.0')
    expect(call).to include('prompt_tps' => 1000.0, 'eval_tps' => 40.0, 'total_s' => 7.0)
  end
end
