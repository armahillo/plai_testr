require_relative 'gin_rummy/game'
require_relative 'gin_rummy/melds'
require_relative 'gin_rummy/state/game_state'
require_relative 'gin_rummy/bot'
require_relative 'gin_rummy/session/runner'

PlaiTestr.register('gin_rummy',
                   runner_class:     GinRummy::Session::Runner,
                   game_state_class: GinRummy::State::GameState,
                   recent_events:    10)
