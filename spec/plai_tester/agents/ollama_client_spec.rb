require 'spec_helper'

RSpec.describe PlaiTester::Agents::OllamaClient do
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

  it 'warns when the prompt nearly fills the context window (Ollama truncates silently)' do
    allow(client).to receive(:post).and_return(done.merge('prompt_eval_count' => 3900))

    expect { client.chat(model: 'm', messages: [], num_ctx: 4096) }.to output(/context nearly full: 3900\/4096/).to_stderr
  end
end
