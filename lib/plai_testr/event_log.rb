module PlaiTestr
  class EventLog
    def initialize(entries)
      @entries = entries
    end

    def add(text, turn:, to: nil, actor: nil, tag: nil)
      entry = { 'turn' => turn, 'text' => text, 'to' => to }
      entry.merge!('actor' => actor, 'tag' => tag) if tag
      @entries << entry
    end

    def visible_to(player)
      @entries.select { |e| e['to'].nil? || e['to'] == player }
    end

    def recent_for(player, count)
      visible_to(player).last(count).map do |e|
        text = e['to'] ? "(private) #{e['text']}" : e['text']
        e['tag'] && e['actor'] == player ? "#{e['tag']}: #{text}" : text
      end
    end
  end
end
