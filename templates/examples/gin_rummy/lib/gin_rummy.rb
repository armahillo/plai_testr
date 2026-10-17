require 'yaml'

require_relative 'gin_rummy/game'
require_relative 'gin_rummy/melds'
require_relative 'gin_rummy/state/game_state'
require_relative 'gin_rummy/session/policy'
require_relative 'gin_rummy/session/runner'

PlaiTester.register('gin_rummy',
                    runner_class:     GinRummy::Session::Runner,
                    game_state_class: GinRummy::State::GameState)
