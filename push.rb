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

  ## 設定情報の取得
  ### S3バケット(line-weather-bot-user-information)から.csvファイルの一覧を取得する
  s3_client = Aws::S3::Client.new
  resp = s3_client.list_objects_v2(bucket: ENV["USER_INFO_BUCKET"])
  resp.contents.each do |obj|
    ## ファイルからuser_idとcity_idを取得する
    resp = s3_client.get_object(bucket: ENV["USER_INFO_BUCKET"], key: obj.key)
    csv_data = resp.body.read
    user_id = nil
    city_id = nil
    CSV.parse(csv_data, headers: true) do |row|
      user_id = row['user_id']
      city_id = row['city_id']
    end
    p city_id
    weatherInfo = getWeatherInfo(city_id)
    message = {
      type: 'text',
      text: "#{weatherInfo}"
    }
    line_bot_client.push_message(user_id, message)
  end
end

def getWeatherInfo(city_id)
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