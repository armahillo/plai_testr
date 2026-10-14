require 'spec_helper'

RSpec.describe PlaiTester::Agents::RefereeAgent do
  let(:rules)  { { 'game' => { 'name' => 'Test Game', 'version' => '1.0' } } }
  let(:client) { instance_double(PlaiTester::Agents::OllamaClient) }

  subject(:referee) { described_class.new(model: 'test-model', client: client, rules: rules) }

  def chat_response(json_str)
    { 'message' => { 'content' => json_str } }
  end

  describe '#ruling' do
    def ruling = referee.ruling(question: 'Did the opponent just PARRY?', facts: 'last action: parry')

    it 'returns the yes/no answer with its reason' do
      allow(client).to receive(:chat).and_return(chat_response('<think>hmm</think>{"met":true,"why":"they parried"}'))

      expect(ruling).to eq('met' => true, 'why' => 'they parried', 'fallback' => false)
    end

    it 'sends the question and facts with the ruling schema at low temperature' do
      expect(client).to receive(:chat) do |args|
        expect(args[:messages].last[:content]).to include('Did the opponent just PARRY?', 'last action: parry')
        expect(args).to include(format: described_class::RULING_SCHEMA, temperature: 0.1)
        chat_response('{"met":false,"why":"no"}')
      end

      ruling
    end

    it 'falls back to not met, flagged, when no usable answer comes back' do
      allow(client).to receive(:chat).and_return(chat_response('{"met":"maybe"}'))

      expect(ruling).to include('met' => false, 'fallback' => true)
    end
  end
end
