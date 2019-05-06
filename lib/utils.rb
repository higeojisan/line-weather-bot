load "vendor/bundle/bundler/setup.rb"

require 'logger'
require 'json'
require 'open-uri'
require 'oga'
require 'jsonclient'

LIVEDOOR_WEATHER_INFO_URL = 'http://weather.livedoor.com/forecast/webservice/json/v1'
LIVEDOOR_JSON_FILE = File.expand_path '../livedoor_data/primary_area.json', File.dirname(__FILE__)
LIVEDOOR_XML_FILE = File.expand_path '../livedoor_data/primary_area.xml', File.dirname(__FILE__)
MAX_ACTION_NUM_FOR_BUTTON_TEMPLATE = 4 ## ボタンテンプレートは最大4アクションまでというLINE Messaging API制限がある
BUTTON_TEMPLATE_HASH = {
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

def write_user_data_to_s3(user_id, city_id)
  digested_user_id = Digest::SHA256.hexdigest("#{user_id}")
  temp_file = Tempfile.open {|t|
    t.puts('user_id,city_id')
    t.puts("#{user_id},#{city_id}")
    t
  }
  s3_client = Aws::S3::Client.new
  s3_client.put_object({
    body: File.open("#{temp_file.path}"),
    bucket: "#{ENV['USER_INFO_BUCKET']}",
    key: "#{digested_user_id}_info.csv",
  })
  s3_client.get_object(bucket: ENV['USER_INFO_BUCKET'], key: "#{digested_user_id}_info.csv")
rescue => error
  return false
end
  
def get_user_id_and_city_id_from_s3_obj(s3_client = Aws::S3::Client.new, s3_bucket_name = "", s3_object_key = "")
  result = []
  begin
    resp = s3_client.get_object(bucket: s3_bucket_name, key: s3_object_key)
  rescue Aws::S3::Errors::NoSuchKey => e
    puts e.message
    puts "#{s3_object_key} does not exist in #{s3_bucket_name}."
    return false
  end
  s3_object_content = resp.body.read
  CSV.parse(s3_object_content, headers: true) do |row|
    result.push(row['user_id'],row['city_id'])
  end
  result
end

## TODO:ここでreturn返しても意味ないかも...
## Lambdaのhandler関数の中でreturnしないとLambdaが終わらず複数回送信することに...
def reply_server_error_message(line_client, reply_token)
  message = { type: 'text', text: "エラーが発生しました。\n時間をおいて再度試してください。" }
  resp = line_client.reply_message(reply_token, message)
  p resp
end

def city_select_template(citys)
  actions = citys.take(MAX_ACTION_NUM_FOR_BUTTON_TEMPLATE).map do |city|
    action = {
      type: "postback",
      label: "#{city[:name]}",
      data: "#{city[:id]}",
    }
  end
end

def get_weather_info_from_city_id(city_id)
  client = JSONClient.new
  res = client.get("#{LIVEDOOR_WEATHER_INFO_URL}?city=#{city_id}")
  if res.status == 200
    res.body.to_h
  else
    {}
  end
end

def format_weather_info(raw_weather_info)
  forecasts = raw_weather_info['forecasts']
  result = "明日の天気\n\n"
  link = raw_weather_info['link']
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

def get_city_ids_from_livedoor_rss(prefecture)
  citys = []
  xml = Oga.parse_xml(File.read(LIVEDOOR_XML_FILE))
  xml.xpath("/rss/channel/ldWeather:source/pref[contains(@title, '#{prefecture}')]/city").each do |city|
    citys.push({name: city.get('title'), id: city.get('id')})
  end
  citys
end

## 都県府が未入力の場合、都県府を付与する
## TODO: 都道府県名は限られているのでホワイトリストで厳密にチェックした方が良さそう...
def get_prefecture_name(user_input)
  unless user_input.match(/^.+[都県府]$/)
    case user_input
    when '東京'
      prefecture = '東京都'
    when '大阪', '京都'
      prefecture = user_input + '府'
    else
      prefecture = user_input + '県'
    end 
  else
    prefecture = user_input
  end
end

def get_city_name_and_pref_name(city_id)
  result = []
  File.open(LIVEDOOR_JSON_FILE) do |file|
    city_hash = JSON.load(file)["#{city_id}"]
    result << city_hash['city_name'] << city_hash['pref_name'] unless city_hash.nil?
  end
  result
end