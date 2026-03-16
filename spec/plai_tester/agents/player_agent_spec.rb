require 'spec_helper'

RSpec.describe PlaiTester::Agents::PlayerAgent do
  let(:rules) do
    {
      'game'           => { 'name' => 'Test Game', 'version' => '1.0' },
      'turn_structure' => [{ 'name' => 'Act', 'description' => 'Do something' }],
      'win_conditions' => [{ 'type' => 'score_threshold', 'description' => 'Score points', 'threshold' => 10 }],
      'actions'        => [
        { 'type' => 'move',  'description' => 'Move a piece' },
        { 'type' => 'block', 'description' => 'Block an attack', 'reaction' => true }
      ]
    }
  end

  let(:client) { instance_double(PlaiTester::Agents::OllamaClient) }

  subject(:agent) { described_class.new(name: 'Alice', model: 'test-model', client: client, rules: rules) }

  def chat_response(json_str)
    { 'message' => { 'content' => json_str } }
  end

  describe '#take_turn' do
    it 'sends messages to the client and returns parsed JSON' do
      allow(client).to receive(:chat).and_return(chat_response('{"action":"move","parameters":{},"reasoning":"best move"}'))

      result = agent.take_turn({}, ['move', 'end_turn'], [])

      expect(result['action']).to    eq('move')
      expect(result['reasoning']).to eq('best move')
    end

    it 'raises when the response contains no JSON' do
      allow(client).to receive(:chat).and_return(chat_response('I think I will move the piece.'))

      expect { agent.take_turn({}, [], []) }.to raise_error(/No JSON found/)
    end

    it 'summarizes prior turn history using the actions array format' do
      history = [
        {
          'turn'    => 1,
          'player'  => 'Alice',
          'actions' => [
            { 'action' => 'move',     'parameters' => {}, 'reasoning' => '...', 'reactions' => [] },
            { 'action' => 'end_turn', 'parameters' => {}, 'reasoning' => '...', 'reactions' => [] }
          ]
        }
      ]

      expect(client).to receive(:chat) do |args|
        expect(args[:messages].last[:content]).to include('Alice played move')
        chat_response('{"action":"end_turn","parameters":{},"reasoning":"done"}')
      end

      agent.take_turn({}, ['end_turn'], history)
    end

    it 'omits end_turn from the history summary, leaving an empty action list for that turn' do
      history = [
        {
          'turn'    => 1,
          'player'  => 'Bob',
          'actions' => [
            { 'action' => 'end_turn', 'parameters' => {}, 'reasoning' => '...', 'reactions' => [] }
          ]
        }
      ]

      expect(client).to receive(:chat) do |args|
        # "Turn 1: Bob played " with nothing after — end_turn was filtered out
        expect(args[:messages].last[:content]).to match(/Turn 1: Bob played\s*$/)
        chat_response('{"action":"move","parameters":{},"reasoning":"go"}')
      end

      agent.take_turn({}, ['move'], history)
    end
  end

  describe '#react_to' do
    it 'returns parsed response' do
      allow(client).to receive(:chat).and_return(chat_response('{"action":"no_op","parameters":{},"reasoning":"no reaction"}'))

      result = agent.react_to('Bob', { 'action' => 'attack' }, {}, ['block'])

      expect(result['action']).to eq('no_op')
    end

    it 'includes the acting player and triggering action in the prompt' do
      expect(client).to receive(:chat) do |args|
        prompt = args[:messages].last[:content]
        expect(prompt).to include('Bob')
        expect(prompt).to include('attack')
        chat_response('{"action":"no_op","parameters":{},"reasoning":"pass"}')
      end

      agent.react_to('Bob', { 'action' => 'attack' }, {}, ['block'])
    end

    it 'raises when the response contains no JSON' do
      allow(client).to receive(:chat).and_return(chat_response('I choose not to react.'))

      expect { agent.react_to('Bob', {}, {}, []) }.to raise_error(/No JSON found/)
    end
  end
end
