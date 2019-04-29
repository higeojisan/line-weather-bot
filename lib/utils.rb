load "vendor/bundle/bundler/setup.rb"

require 'logger'
require 'json'
require 'open-uri'
require 'oga'

def get_user_id_and_city_id_from_s3_obj(s3_client = Aws::S3::Client.new, s3_bucket_name = "", s3_object_key = "")
  result = []
  begin
    resp = s3_client.get_object(bucket: s3_bucket_name, key: s3_object_key)
  rescue Aws::S3::Errors::NoSuchKey => e
    puts e.message
    puts "#{s3_object_key} does not exist in #{s3_bucket_name}."
    return
  end
  s3_object_content = resp.body.read
  CSV.parse(s3_object_content, headers: true) do |row|
    result.push(row['user_id'],row['city_id'])
  end
  result
end

def reply_error_message(line_client, reply_token)
  message = { type: 'text', text: "エラーが発生しました。\n時間をおいて再度試してください。" }
  resp = line_client.reply_message(reply_token, message)
  p resp
  return
end

def city_select_template(citys)
  actions = []
  count = 0
  citys.each do |city|
    break if count > 3 ## ボタンテンプレートは最大4アクションまでという制限のため
    action = {
      type: "postback",
      label: "#{city[:name]}",
      data: "#{city[:id]}"
    }
    actions.push(action)
    count += 1
  end
  message = {
    "type": "template",
    "altText": "This is a buttons template",
    "template": {
      "type": "buttons",
      "title": "地域設定",
      "text": "近い地域を選んでね",
      "defaultAction": {
        "type": "postback",
        "label": "View detail",
        "data": "default"
      }
    }
  }
  message[:template][:actions] = actions
  message
end

## TODO: 取得と整形の分離
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

def get_xml_from_livedoor_rss()
  logger = Logger.new(STDOUT)

  charset = nil
  url = ENV['LIVEDOOR_PRIMARY_AREA_RSS']

  begin
    xml = open(url, {:redirect => false}) do |f|
      charset = f.charset
      f.read
    end
    xml
  rescue => e
    logger.fatal("failed to connect #{url}: #{e.message}")
    nil
  end
end

def get_prefectures_from_livedoor_rss(rss)
  prefectures = []
  xml = Oga.parse_xml(rss)
  xml.xpath('/rss/channel/ldWeather:source/pref').each do |pref|
    prefectures.push(pref.get('title'))
  end
  prefectures
end

def get_city_ids_from_livedoor_rss(rss, prefecture)
  citys = []
  xml = Oga.parse_xml(rss)
  xml.xpath("/rss/channel/ldWeather:source/pref[contains(@title, '#{prefecture}')]/city").each do |city|
    temp = {}
    temp[:name] = (city.get('title'))
    temp[:id] = (city.get('id'))
    citys.push(temp)
  end
  citys
end