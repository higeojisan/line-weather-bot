load "vendor/bundle/bundler/setup.rb"

require 'logger'
require 'json'
require 'open-uri'
require 'oga'
require 'jsonclient'

LIVEDOOR_WEATHER_INFO_URL = 'http://weather.livedoor.com/forecast/webservice/json/v1'
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
PREFECTURES_EXCEPT_TOKYO_OOSAKA_KYOTO = %w[
  青森 岩手 宮城 秋田 山形 福島 茨城 栃木 群馬　埼玉 千葉 神奈川 新潟 富山 
  石川 福井県 山梨　長野 岐阜 静岡 愛知 三重 滋賀 兵庫　奈良 和歌山 鳥取 
  島根 岡山 広島 山口 徳島 香川　愛媛 高知 福岡 佐賀 長崎 熊本 大分 宮崎 鹿児島 沖縄
].freeze.map(&:freeze)

def write_user_data_to_s3(user_id, city_id)
  digested_user_id = Digest::SHA256.hexdigest("#{user_id}")
  temp_file = Tempfile.open { |t|
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

def get_user_id_and_city_id_from_s3_obj(user_id: nil, s3_object_key: nil)
  s3_object_key = user_id != nil ? Digest::SHA256.hexdigest(user_id) + "_info.csv" : s3_object_key
  result = []
  begin
    s3_client = Aws::S3::Client.new
    resp = s3_client.get_object(bucket: ENV['USER_INFO_BUCKET'], key: s3_object_key)
  rescue Aws::S3::Errors::NoSuchKey => e
    puts e.message
    puts "#{s3_object_key} does not exist in #{s3_bucket_name}."
    return false
  end
  s3_object_content = resp.body.read
  CSV.parse(s3_object_content, headers: true) do |row|
    result.push(row['user_id'], row['city_id'])
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
      max_temp = forecast['temperature']['max'].nil? ? "取得できませんでした" : forecast['temperature']['max']['celsius']
      min_temp = forecast['temperature']['min'].nil? ? "取得できませんでした" : forecast['temperature']['min']['celsius']
      result += "最高気温: #{max_temp}" + "\n"
      result += "最低気温: #{min_temp}" + "\n"
      result += "\n" + link
    end
  end
  result
end

## 都県府が未入力の場合、都県府を付与する
## 都府県名でない場合はそのまま返す
## TODO: 都道府県名は限られているのでホワイトリストで厳密にチェックした方が良さそう...
def format_prefecture_name(user_input)
  unless user_input.match(/^.+[都県府]$/)
    case user_input
    when '東京'
      prefecture = '東京都'
    when '大阪'
      prefecture = user_input + '府'
    when *PREFECTURES_EXCEPT_TOKYO_OOSAKA_KYOTO
      prefecture = user_input + '県'
    else
      prefecture = user_input
    end
  else
    prefecture = (user_input == '京都府' || user_input == '京都') ? '京都府' : user_input
  end
end

def line_bot_client
  @line_bot_client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV['LINE_CHANNEL_SECRET']
    config.channel_token = ENV['LINE_CHANNEL_TOKEN']
  }
end