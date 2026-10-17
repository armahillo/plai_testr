module PlaiTester
  def self.rename(text, names)
    return text if names.empty?

    text.gsub(Regexp.union(names.keys.sort_by { |id| -id.length })) { |id| names[id] }
  end
end
