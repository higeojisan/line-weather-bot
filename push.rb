load "vendor/bundle/bundler/setup.rb"

require 'json'
require 'line/bot'
require 'aws-sdk'
require 'csv'
require 'jsonclient'

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

def get_user_id_and_city_id_from_s3_obj(s3_client = Aws::S3::Client.new, s3_bucket_name = "", s3_object_key = "")
  result = []
  resp = s3_client.get_object(bucket: s3_bucket_name, key: s3_object_key)
  s3_object_content = resp.body.read
  CSV.parse(s3_object_content, headers: true) do |row|
    result.push(row['user_id'],row['city_id'])
  end
  result
end

def get_weather_info_from_city_id(city_id)
  client = JSONClient.new
  res = client.get("http://weather.livedoor.com/forecast/webservice/json/v1?city=#{city_id}")
  return "情報が取得出来ませんでした" unless res.status == 200
  body = res.body.to_h
  forecasts = body['forecasts']
  result = "明日の天気\n\n"
  link = body['link']
  forecasts.each do |forecast|
    if forecast['dateLabel'] == '明日'
      result += forecast['telop'] + "\n\n"
      max_temp = forecast['temperature']['max']['celsius']
      min_temp = forecast['temperature']['min']['celsius']
      result += "最高気温: #{max_temp}" + "\n"
      result += "最低気温: #{min_temp}" + "\n"
      result += "\n" + link
    end
  end
  result
end