require_relative 'hearts/game'
require_relative 'hearts/state/game_state'
require_relative 'hearts/bot'
require_relative 'hearts/session/runner'
require_relative 'hearts/reporter/botrun_report'

PlaiTestr.register('hearts',
                    runner_class:        Hearts::Session::Runner,
                    game_state_class:    Hearts::State::GameState,
                    botrun_report_class: Hearts::Reporter::BotrunReport,
                    players:             ['Player 1', 'Player 2', 'Player 3', 'Player 4'],
                    recent_events:       12)
