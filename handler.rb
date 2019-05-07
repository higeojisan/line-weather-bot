load 'vendor/bundle/bundler/setup.rb'
$LOAD_PATH.unshift('./lib/')

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

PREFECTURES = %w[
  青森 岩手県 宮城県 秋田県 山形県 福島県 茨城県 栃木県 群馬県
  埼玉県 千葉県 東京都 神奈川県 新潟県 富山県 石川県 福井県 山梨県
  長野県 岐阜県 静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県
  奈良県 和歌山県 鳥取県 島根県 岡山県 広島県 山口県 徳島県 香川県
  愛媛県 高知県 福岡県 佐賀県 長崎県 熊本県 大分県 宮崎県 鹿児島県 沖縄県
].freeze.map(&:freeze)

def input(event:, context:)
  logger = Logger.new(STDOUT)

  ## クライアントの作成
  line_bot_client = Line::Bot::Client.new { |config|
    config.channel_secret = ENV['LINE_CHANNEL_SECRET']
    config.channel_token = ENV['LINE_CHANNEL_TOKEN']
  }

  ## 署名の検証
  unless line_bot_client.validate_signature(event['body'], event['headers']['X-Line-Signature'])
    logger.fatal('failed to validate signature.')
    return 0
  end

  events = line_bot_client.parse_events_from(event['body'])
  events.each { |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        case event.message['text']
        when '設定地域の確認'
          ## ユーザー情報の取得
          user_id, city_id = get_user_id_and_city_id_from_s3_obj(event['source']['userId'])
          ## ユーザー情報が見つからなかった場合にエラーメッセージを送る
          unless user_id
            message = { type: 'text', text: "設定地域の登録が済んでないようです。\n天気予報を受け取りたい地域の設定を行ってください。" }
            response = line_bot_client.reply_message(event['replyToken'], message)
            p response
            return
          end
          if user_id == event['source']['userId']
            city_name, pref_name = get_city_name_and_pref_name(city_id)
            message = {
              type: 'text',
              text: "あなたの設定地域は\n#{city_name}(#{pref_name})だよ"
            }
            response = line_bot_client.reply_message(event['replyToken'], message)
            p response
            return
          end
          return
        else
          ## TODO: 北海道は未対応(https://github.com/higeojisan/line-weather-bot/issues/2)
          if event.message['text'] == '北海道'
            message = {
              type: 'text',
              text: "北海道の方は使えません。\nごめんなさい。"
            }
            response = line_bot_client.reply_message(event['replyToken'], message)
            p response
            return
          end

          prefecture = get_prefecture_name(event.message['text'])
          if PREFECTURES.include?(prefecture)
            citys = get_city_ids_from_livedoor_rss(prefecture)
            message = BUTTON_TEMPLATE_HASH
            message[:template][:actions] = city_select_template(citys)
            response = line_bot_client.reply_message(event['replyToken'], message)
            p response
            return
          else
            message = {
              type: 'text',
              text: "一致する地域が見つかりませんでした。\n都道府県名を入力してください。"
            }
            response = line_bot_client.reply_message(event['replyToken'], message)
            p response
            return
          end
        end
      end
    when Line::Bot::Event::Postback

      ## s3にuser_idとcity_idを書き込む
      city_id = event['postback']['data']
      user_id = event['source']['userId']
      unless write_user_data_to_s3(user_id, city_id)
        reply_server_error_message(line_bot_client, event['replyToken'])
        return
      end

      ## ユーザーに完了メッセージを送る
      message = {
        type: 'text',
        text: "地域の設定が完了しました。\n毎日22:00に天気予報をお届けします。"
      }
      response = line_bot_client.reply_message(event['replyToken'], message)
      p response
      return
    end
  }
end
