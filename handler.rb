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
          else
            prefecture = user_input + '県'
          end 
        else
          prefecture = user_input
        end

        if prefectures.include?(prefecture)
          ## 一致する都道府県名が見つかった場合
          citys = get_city_ids_from_livedoor_rss(rss, prefecture)
          message = city_select_template(citys)
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

      ## s3にuser_idとcity_idを書き込む
      write_user_data_to_s3(user_id, city_id)

      ## ユーザーに完了メッセージを送る
      message = {
        type: 'text',
        text: "地域の設定が完了しました。\n毎日22:00に天気予報をお届けします。"
      }
      response = client.reply_message(event['replyToken'], message)
      p response
      return
    end
  }
end