module PlaiTestr
  class Error < StandardError; end
  class RulesError < Error; end
  class PersonaError < Error; end
  class SessionError < Error; end
  class ModelError < Error; end
  class UsageError < Error; end
  class MoveError < Error; end
end
