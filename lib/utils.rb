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

## TODO: RSSの取得とメッセージの送信の分離
def getPrimaryAreaRSS(line_bot_client, replyToken)
  logger = Logger.new(STDOUT)

  charset = nil
  url = ENV['LIVEDOOR_PRIMARY_AREA_RSS']

  begin
    xml = open(url) do |f|
      charset = f.charset
      f.read
    end
  rescue => e
    logger.fatal("failed to connect #{url}: #{e.message}")
    message = {
      type: 'text',
      text: 'やり直してください'
    }
    line_bot_client.reply_message(replyToken, message)
  end

  xml
end