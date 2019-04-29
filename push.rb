load "vendor/bundle/bundler/setup.rb"
$LOAD_PATH.unshift("./lib/")

require 'json'
require 'line/bot'
require 'aws-sdk'
require 'csv'
require 'jsonclient'
require 'utils'

def weather_info(event:, context:)
  ## クライアントの作成
  line_bot_client = Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }

  ## 設定情報の取得 & メッセージの送信
  s3_client = Aws::S3::Client.new
  list_objects_resp = s3_client.list_objects_v2(bucket: ENV["USER_INFO_BUCKET"])
  list_objects_resp.contents.each do |s3_object|
    
    ## ファイルからuser_idとcity_idを取得する
    user_id, city_id = get_user_id_and_city_id_from_s3_obj(s3_client, ENV["USER_INFO_BUCKET"], s3_object.key)
    
    ## city_idで指定した地域の明日の天気予報を取得する
    weatherInfo = get_weather_info_from_city_id(city_id)

    ## メッセージを送信する
    message = {
      type: 'text',
      text: "#{weatherInfo}"
    }
    line_bot_client.push_message(user_id, message)
  end
end