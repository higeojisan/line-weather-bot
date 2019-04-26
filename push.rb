load "vendor/bundle/bundler/setup.rb"

require 'json'
require 'line/bot'
require 'aws-sdk'
require 'csv'

def weather_info(event:, context:)
  ## クライアントの作成
  line_bot_client = Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }

  ## 設定情報の取得
  ### S3バケット(line-weather-bot-user-information)から.csvファイルの一覧を取得する
  s3_client = Aws::S3::Client.new
  resp = s3_client.list_objects_v2(bucket: ENV["USER_INFO_BUCKET"])
  resp.contents.each do |obj|
    ## ファイルからuser_idとcity_idを取得する
    resp = s3_client.get_object(bucket: ENV["USER_INFO_BUCKET"], key: obj.key)
    csv_data = resp.body.read
    CSV.parse(csv_data, headers: true) do |row|
      user_id = row['user_id']
      city_id = row['city_id']
    end
  end
  #weatherInfo = getWeatherInfo(ENV['CITY_ID'])

  message = {
    type: 'text',
    text: "consecutive push message test"
  }

  line_bot_client.push_message(user_id, message)
end