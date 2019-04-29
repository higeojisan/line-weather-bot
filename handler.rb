load "vendor/bundle/bundler/setup.rb"
$LOAD_PATH.unshift("./lib/")

require 'json'
require 'line/bot'
require 'logger'
require 'open-uri'
require 'oga'
require 'aws-sdk'
require 'digest/sha2'
require 'tempfile'
require 'csv'
require 'utils'

LIVEDOOR_JSON_FILE='livedoor_data/primary_area.json'

def input(event:, context:)
  logger = Logger.new(STDOUT)

  ## クライアントの作成
  client = Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }

  ## 署名の検証
  unless client.validate_signature(event["body"], event["headers"]["X-Line-Signature"])
    logger.fatal("failed to validate signature.") 
    return 0
  end
  
  events = client.parse_events_from(event["body"])
  events.each { |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text

        ## case文で分けた方がわかりやすい気がする...
        ## リッチメニューで設定確認をタップされた時の処理
        if event.message['text'] == '設定地域の確認'
          ## user_idを取得してその人のcity_idを取得する
          digested_user_id = Digest::SHA256.hexdigest("#{event['source']['userId']}")
          s3_client = Aws::S3::Client.new
          user_id, city_id = get_user_id_and_city_id_from_s3_obj(s3_client, ENV["USER_INFO_BUCKET"], "#{digested_user_id}_info.csv")
          if user_id == event['source']['userId']
            File.open(LIVEDOOR_JSON_FILE) do |file|
              city_hash = JSON.load(file)["#{city_id}"]
              message = {
                type: 'text',
                text: "あなたの設定地域は\n#{city_hash['city_name']}(#{city_hash['pref_name']})だよ"
              }
              response = client.reply_message(event['replyToken'], message)
              p response
            end
          end
          return
        end

        ## 地域登録時の処理
        user_input = event.message['text']

        rss = get_xml_from_livedoor_rss()
        reply_error_message(client, event['replyToken']) if rss.nil?          
        
        prefectures = get_prefectures_from_livedoor_rss(rss)
        reply_error_message(client, event['replyToken']) if prefectures.empty?
        xml = Oga.parse_xml(rss)
          
        ## 入力(prefecture)がRSSから取得したものと一致するか比較する
        ## 一致しない：やり直し
        ## 一致する：地域をサジェストする
        ## TODO: 北海道は未対応(https://github.com/higeojisan/line-weather-bot/issues/2)
        if user_input === '北海道'
          message = {
            type: 'text',
            text: "北海道の方は使えません。\nごめんなさい。"
          }
          response = client.reply_message(event['replyToken'], message)
          p response
        end

        ## ユーザーの入力の整形
        unless user_input.match(/^.+[都県府]$/)
          case user_input
          when '東京'
            prefecture = '東京都'
          when '大阪', '京都'
            prefecture = user_input + '府'
          when '道北', '道東', '道南', '道央'
            prefecture = user_input
          else
            prefecture = user_input + '県'
          end 
        else
          prefecture = user_input
        end

        if prefectures.include?(prefecture)
          ## 一致する都道府県名が見つかった場合
          citys = []
          xml.xpath("/rss/channel/ldWeather:source/pref[contains(@title, '#{prefecture}')]/city").each do |city|
            temp = {}
            temp[:name] = (city.get('title'))
            temp[:id] = (city.get('id'))
            citys.push(temp)
          end
          actions = []
          count = 0
          citys.each do |city|
            break if count > 3
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
          response = client.reply_message(event['replyToken'], message)
          p response
          return
        else
          ## 一致する都道府県名が見つからなかった場合
          message = {
            type: 'text',
            text: "一致する地域が見つかりませんでした。\n都道府県名を入力してください。"
          }
          response = client.reply_message(event['replyToken'], message)
          p response
          return
        end

      end
    when Line::Bot::Event::Postback
      ## user_idとcity_idの取得
      city_id = event['postback']['data']
      user_id = event['source']['userId']

      ## 取得したuser_idとcity_idをS3に保存
      ## user_id, city_idのCSV形式で保存する※user_idをハッシュ化するとpushの際に戻せないのでハッシュ化しない
      ## その代わりS3のSSE-KSMで暗号化して保存する※バケットレベルで設定する
      ## https://qiita.com/k5trismegistus/items/00bb6bb579b6f5e040c6
      ## pushの時にS3 Selectを使う前提ならユーザーごとのファイルに分けないで1つのファイルに追記する方がいい
      digested_user_id = Digest::SHA256.hexdigest("#{user_id}")
      temp_file = Tempfile.open {|t|
        t.puts('user_id,city_id')
        t.puts("#{user_id},#{city_id}")
        t
      }
      temp_file_path = temp_file.path
      s3_client = Aws::S3::Client.new
      resp = s3_client.put_object({
        body: File.open("#{temp_file_path}"),
        bucket: "#{ENV['USER_INFO_BUCKET']}",
        key: "#{digested_user_id}_info.csv",
      })
      ## TODO: ファイルが正常にアップロードされたか確認する
      ## https://docs.aws.amazon.com/ja_jp/sdk-for-ruby/v3/developer-guide/s3-example-create-buckets.html
      p resp

      message = {
        type: 'text',
        text: "city_id: #{city_id}\nuser_id: #{user_id}"
      }

      response = client.reply_message(event['replyToken'], message)
      p response
    end
  }
end