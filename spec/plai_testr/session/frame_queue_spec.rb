require 'spec_helper'

RSpec.describe PlaiTestr::Session::FrameQueue do
  let(:machine_class) do
    Class.new do
      include PlaiTestr::Session::FrameQueue

      attr_reader :queue, :events
      attr_accessor :over, :hand

      def initialize
        @queue  = []
        @events = []
        @over   = false
        @hand   = 1
      end

      def start = advance_frames

      def choose(params) = resolve_frame(params)

      def current = frame

      private

      def frame_queue = @queue

      def game_over? = @over

      def schedule_frames
        @events << :scheduled
        frame_queue.push(frame_for('score', auto: true))
        frame_queue.push(frame_for('attack', 'Alice'))
      end

      def intercept_frame(current)
        return false unless current['type'] == 'attack' && @hand.zero?

        frame_queue.push(frame_for('refill', 'Alice'))
      end

      def on_attack(_frame, params) = @events << [:attack, params['target']]

      def on_refill(_frame, _params)
        @hand = 1
        @events << :refill
      end

      def on_score(_frame)
        @events << :score
        @over = true
      end
    end
  end

  subject(:machine) { machine_class.new }

  it 'schedules frames when the queue is empty and stops at the first decision' do
    machine.start

    expect(machine.current).to include('type' => 'attack', 'player' => 'Alice')
    expect(machine.events).to eq([:scheduled])
  end

  it 'resolves a decision, then runs automatic frames until the game ends' do
    machine.start
    machine.choose('target' => 'left')

    expect(machine.events).to eq([:scheduled, [:attack, 'left'], :score])
    expect(machine.queue).to be_empty
  end

  it 'lets the game intercept a decision frame with a frame of its own' do
    machine.hand = 0
    machine.start

    expect(machine.current).to include('type' => 'refill')
    machine.choose({})
    expect(machine.current).to include('type' => 'attack')
  end
end
