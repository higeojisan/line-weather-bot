load "vendor/bundle/bundler/setup.rb"

require 'json'
require 'line/bot'

def input(event:, context:)
  client = Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }

  p client
end
