load "vendor/bundle/bundler/setup.rb"

require 'json'
require 'line/bot'

def weather_info(event:, context:)
  ## クライアントの作成
  client = Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }

  ## 設定情報の取得
  ### S3バケット(line-weather-bot-user-information)から.csvファイルの一覧を取得する


  #weatherInfo = getWeatherInfo(ENV['CITY_ID'])

  message = {
    type: 'text',
    text: "consecutive push message test"
  }

  client.push_message(ENV["MY_LINE_USER_ID"], message)
end