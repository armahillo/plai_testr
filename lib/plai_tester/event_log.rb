module PlaiTester
  class EventLog
    def initialize(entries)
      @entries = entries
    end

    def add(text, turn:, to: nil)
      @entries << { 'turn' => turn, 'text' => text, 'to' => to }
    end

    def visible_to(player)
      @entries.select { |e| e['to'].nil? || e['to'] == player }
    end

    def recent_for(player, count)
      visible_to(player).last(count).map { |e| e['to'] ? "(private) #{e['text']}" : e['text'] }
    end
  end
end
