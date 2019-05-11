load 'vendor/bundle/bundler/setup.rb'
$LOAD_PATH.unshift('./lib/')

require 'json'
require 'line/bot'
require 'aws-sdk'
require 'csv'
require 'jsonclient'
require 'utils'
require 'livedoor_weather'

def weather_info(event:, context:)
  livedoor_weather = LivedoorWeather.new
  ## 設定情報の取得 & メッセージの送信
  s3_client = Aws::S3::Client.new
  list_objects_resp = s3_client.list_objects_v2(bucket: ENV['USER_INFO_BUCKET'])
  list_objects_resp.contents.each do |s3_object|
    ## ファイルからuser_idとcity_idを取得する
    user_id, city_id = get_user_id_and_city_id_from_s3_obj(s3_object_key: s3_object.key)
    ## メッセージを送信する
    line_bot_client.push_message(user_id, { type: 'text', text: livedoor_weather.format_weather_info_hash(city_id) })
  end
end
