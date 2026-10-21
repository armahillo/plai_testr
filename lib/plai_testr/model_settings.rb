module PlaiTestr
  module ModelSettings
    MIN_CONTEXT = 2048

    def self.resolve(game_settings, model_max: nil)
      settings = PlaiTestr.config.model_settings.merge(game_settings)
      unknown  = settings.keys - Config::MODEL_SETTINGS.keys
      raise UsageError, "Unknown model setting(s): #{unknown.join(', ')} (known: #{Config::MODEL_SETTINGS.keys.join(', ')})" if unknown.any?

      notes = []
      clamp = lambda do |key, min, max|
        bounded = settings[key].clamp(min, max)
        notes << "#{key} #{settings[key]} is outside #{min}–#{max}; using #{bounded}" unless bounded == settings[key]
        settings[key] = bounded
      end

      %i[context_size long_context_size].each { |key| clamp.call(key, MIN_CONTEXT, model_max || [settings[key], MIN_CONTEXT].max) }
      clamp.call(:temperature, 0.0, 2.0)
      %i[menu_budget referee_budget].each { |key| clamp.call(key, 1, settings[:context_size] - 1) }
      %i[think_budget debrief_budget].each { |key| clamp.call(key, 1, settings[:long_context_size] - 1) }

      [settings, notes]
    end
  end
end
