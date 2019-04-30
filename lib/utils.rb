load "vendor/bundle/bundler/setup.rb"

require 'logger'
require 'json'
require 'open-uri'
require 'oga'

## TODO: ファイルが正常にアップロードされたかの確認を追加する
## https://docs.aws.amazon.com/ja_jp/sdk-for-ruby/v3/developer-guide/s3-example-create-buckets.html
def write_user_data_to_s3(user_id, city_id)
  digested_user_id = Digest::SHA256.hexdigest("#{user_id}")
  temp_file = Tempfile.open {|t|
    t.puts('user_id,city_id')
    t.puts("#{user_id},#{city_id}")
    t
  }
  s3_client = Aws::S3::Client.new
  resp = s3_client.put_object({
    body: File.open("#{temp_file.path}"),
    bucket: "#{ENV['USER_INFO_BUCKET']}",
    key: "#{digested_user_id}_info.csv",
  })
end
  
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