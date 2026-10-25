module PlaiTestr
  module Reporter
    module Tables
      ROW       = /\A\|.*\|\s*\z/
      SEPARATOR = /\A:?-+:?\z/

      def self.align(markdown)
        fenced = false

        markdown.lines.chunk_while { |a, b| a.match?(ROW) && b.match?(ROW) }.flat_map do |lines|
          fenced = !fenced if lines.first.start_with?('```')
          !fenced && lines.first.match?(ROW) ? table(lines) : lines
        end.join
      end

      def self.table(lines)
        rows   = lines.map { |line| line.strip.delete_prefix('|').delete_suffix('|').split(/(?<!\\)\|/, -1).map(&:strip) }
        count  = rows.map(&:length).max
        rows   = rows.map { |cells| cells + [''] * (count - cells.length) }
        widths = Array.new(count) { |i| [3, *rows.map { |cells| width(cells[i]) }].max }

        rows.map do |cells|
          padded = cells.each_with_index.map { |cell, i| cell.match?(SEPARATOR) ? rule(cell, widths[i]) : cell + ' ' * (widths[i] - width(cell)) }
          "| #{padded.join(' | ')} |\n"
        end
      end

      def self.rule(cell, width)
        left  = cell.start_with?(':') ? ':' : '-'
        right = cell.end_with?(':') && cell.length > 1 ? ':' : '-'
        left + '-' * (width - 2) + right
      end

      def self.width(cell) = cell.each_grapheme_cluster.count
    end
  end
end
