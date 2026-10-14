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

  describe '#choose' do
    let(:labels) { ['Take card A', 'Take card B', 'Take card C'] }

    def choose
      agent.choose(rules_text: 'RULES', view_text: 'VIEW', labels: labels, plan: 'old plan', recent: ['Bob: took X'])
    end

    it 'returns the chosen option with reasoning and plan' do
      allow(client).to receive(:chat).and_return(chat_response('{"choice":2,"reasoning":"B is better","plan":"take B"}'))

      result = choose

      expect(result).to include('choice' => 2, 'reasoning' => 'B is better', 'plan' => 'take B', 'attempts' => 1, 'fallback' => false)
    end

    it 'numbers the legal moves and requests schema-constrained JSON with thinking off' do
      expect(client).to receive(:chat) do |args|
        expect(args[:messages].last[:content]).to include("1. Take card A\n2. Take card B\n3. Take card C")
        expect(args[:messages].last[:content]).to include('YOUR PLAN SO FAR: old plan', '- Bob: took X')
        expect(args).to include(think: false, num_ctx: 8192, format: described_class::MENU_SCHEMA)
        chat_response('{"choice":1,"reasoning":"r","plan":"p"}')
      end

      choose
    end

    it 're-prompts after an out-of-range choice' do
      allow(client).to receive(:chat).and_return(
        chat_response('{"choice":9,"reasoning":"r","plan":"p"}'),
        chat_response('{"choice":3,"reasoning":"r","plan":"p"}')
      )

      expect(choose).to include('choice' => 3, 'attempts' => 2, 'fallback' => false)
    end

    it 'falls back to option 1 and flags it when no valid choice is ever made' do
      allow(client).to receive(:chat).and_return(chat_response('not json at all'))

      expect(choose).to include('choice' => 1, 'fallback' => true)
    end
  end

  describe '#debrief' do
    let(:questions) { ['Strongest card?', 'Weakest card?'] }

    def debrief
      agent.debrief(rules_text: 'RULES', view_text: 'FINAL VIEW', questions: questions)
    end

    it 'asks every question once and pairs each answer with its question' do
      expect(client).to receive(:chat).once do |args|
        expect(args[:messages].last[:content]).to include('FINAL VIEW', 'q1: Strongest card?', 'q2: Weakest card?')
        expect(args[:format]['required']).to eq(%w[q1 q2])
        chat_response('{"q1":"Crushing","q2":"nothing"}')
      end

      expect(debrief).to eq([{ 'question' => 'Strongest card?', 'answer' => 'Crushing' },
                             { 'question' => 'Weakest card?',   'answer' => 'nothing' }])
    end

    it 'returns empty answers instead of raising when the model never replies usefully' do
      allow(client).to receive(:chat).and_return(chat_response('not json'))

      expect(debrief.map { |a| a['answer'] }).to eq(['', ''])
    end
  end
end
