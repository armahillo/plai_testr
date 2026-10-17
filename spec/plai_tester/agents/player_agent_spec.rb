require 'spec_helper'

RSpec.describe PlaiTester::Agents::PlayerAgent do
  let(:rules) do
    {
      'game' => { 'name' => 'Test Game', 'version' => '1.0' }
    }
  end

  let(:client) { instance_double(PlaiTester::Agents::OllamaClient) }

  subject(:agent) { described_class.new(name: 'Alice', model: 'test-model', client: client, rules: rules) }

  def chat_response(json_str)
    { 'message' => { 'content' => json_str } }
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

    it 'turns thinking on, with room for the thoughts, when built with think: true' do
      thinker = described_class.new(name: 'Alice', model: 'test-model', client: client, rules: rules, think: true)
      expect(client).to receive(:chat) do |args|
        expect(args).to include(think: true, num_ctx: 16_384, num_predict: 8192)
        chat_response('{"choice":1,"reasoning":"r","plan":"p"}')
      end

      thinker.choose(rules_text: 'RULES', view_text: 'VIEW', labels: labels)
    end

    it 'skips thinking on a turn the game marks think: false, keeping the context size so the model is not reloaded' do
      thinker = described_class.new(name: 'Alice', model: 'test-model', client: client, rules: rules, think: true)
      expect(client).to receive(:chat) do |args|
        expect(args).to include(think: false, num_ctx: 16_384, num_predict: 512)
        chat_response('{"choice":1,"reasoning":"r","plan":"p"}')
      end

      thinker.choose(rules_text: 'RULES', view_text: 'VIEW', labels: labels, think: false)
    end

    it 'puts the persona into the system prompt when one is given' do
      expect(client).to receive(:chat) do |args|
        expect(args[:messages].first[:content]).to include('YOUR STRATEGY', 'Win by attrition')
        chat_response('{"choice":1,"reasoning":"r","plan":"p"}')
      end

      agent.choose(rules_text: 'RULES', view_text: 'VIEW', labels: labels, persona: 'Win by attrition.')
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

  describe '#choose_many' do
    let(:labels) { ['Card A', 'Card B', 'Card C', 'Card D'] }

    def choose_many(min: 2, max: 2)
      agent.choose_many(rules_text: 'RULES', view_text: 'VIEW', labels: labels, min: min, max: max)
    end

    it 'returns the chosen options' do
      allow(client).to receive(:chat).and_return(chat_response('{"choices":[4,2],"reasoning":"r","plan":"p"}'))

      expect(choose_many).to include('choices' => [4, 2], 'attempts' => 1, 'fallback' => false)
    end

    it 'tells the model how many to choose and requests the pick schema' do
      expect(client).to receive(:chat) do |args|
        expect(args[:messages].last[:content]).to include('Choose between 0 and 3 different options')
        expect(args[:format]).to eq(described_class::PICK_SCHEMA)
        chat_response('{"choices":[],"reasoning":"r","plan":"p"}')
      end

      choose_many(min: 0, max: 3)
    end

    it 're-prompts on the wrong count, duplicates, or out-of-range numbers' do
      allow(client).to receive(:chat).and_return(
        chat_response('{"choices":[1],"reasoning":"r","plan":"p"}'),
        chat_response('{"choices":[2,2],"reasoning":"r","plan":"p"}'),
        chat_response('{"choices":[1,3],"reasoning":"r","plan":"p"}')
      )

      expect(choose_many).to include('choices' => [1, 3], 'attempts' => 3)
    end

    it 'falls back to the first options and flags it' do
      allow(client).to receive(:chat).and_return(chat_response('nope'))

      expect(choose_many).to include('choices' => [1, 2], 'fallback' => true)
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
