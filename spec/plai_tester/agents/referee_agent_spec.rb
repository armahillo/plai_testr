require 'spec_helper'

RSpec.describe PlaiTester::Agents::RefereeAgent do
  let(:rules) do
    {
      'game'           => { 'name' => 'Test Game', 'version' => '1.0' },
      'turn_structure' => [],
      'win_conditions' => [],
      'actions'        => []
    }
  end

  let(:client) { instance_double(PlaiTester::Agents::OllamaClient) }

  subject(:referee) { described_class.new(model: 'test-model', client: client, rules: rules) }

  def chat_response(json_str)
    { 'message' => { 'content' => json_str } }
  end

  describe '#compute_initial_state' do
    it 'returns parsed initial state from setup steps' do
      response = '{"flags":{},"custom":{"deck":[1,2,3]},"player_states":{"Alice":{"hand":[4,5],"score":0,"flags":{}}}}'
      allow(client).to receive(:chat).and_return(chat_response(response))

      result = referee.compute_initial_state(
        setup_steps: [{ 'step' => 1, 'description' => 'Deal 2 cards to each player.' }],
        components:  [{ 'name' => 'Deck', 'type' => 'card_deck' }],
        players:     ['Alice']
      )

      expect(result['player_states']['Alice']['hand']).to eq([4, 5])
      expect(result['custom']['deck']).to eq([1, 2, 3])
    end

    it 'uses a higher temperature than validate for distribution variety' do
      allow(client).to receive(:chat)
        .with(hash_including(temperature: (be > 0.1)))
        .and_return(chat_response('{"flags":{},"custom":{},"player_states":{}}'))

      referee.compute_initial_state(setup_steps: [], components: [], players: ['Alice'])
    end
  end

  describe '#validate' do
    let(:valid_json) { '{"valid":true,"reason":"legal","state_changes":{}}' }

    it 'returns parsed validation response' do
      allow(client).to receive(:chat).and_return(chat_response(valid_json))

      result = referee.validate(player: 'Alice', action: { 'action' => 'move' }, game_state: {})

      expect(result['valid']).to  be true
      expect(result['reason']).to eq('legal')
    end

    it 'defaults to turn_action context' do
      expect(client).to receive(:chat) do |args|
        expect(args[:messages].last[:content]).to include("Alice's regular turn action")
        chat_response(valid_json)
      end

      referee.validate(player: 'Alice', action: { 'action' => 'move' }, game_state: {})
    end

    it 'includes the reaction trigger in the prompt when context is a reaction' do
      context = PlaiTester::Protocol::Context.reaction(
        acting_player:    'Bob',
        triggering_action: { 'action' => 'attack' }
      )

      expect(client).to receive(:chat) do |args|
        prompt = args[:messages].last[:content]
        expect(prompt).to include('reacting to Bob')
        expect(prompt).to include('attack')
        chat_response(valid_json)
      end

      referee.validate(player: 'Alice', action: { 'action' => 'block' }, game_state: {}, context: context)
    end

    it 'raises when the response contains no JSON' do
      allow(client).to receive(:chat).and_return(chat_response('The action is valid.'))

      expect {
        referee.validate(player: 'Alice', action: {}, game_state: {})
      }.to raise_error(/No JSON found/)
    end
  end
end
