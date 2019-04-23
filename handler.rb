load "vendor/bundle/bundler/setup.rb"

require 'json'
require 'line/bot'
require 'logger'
require 'open-uri'
require 'oga'

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
        prefecture = event.message['text']
        
        ## LIVEDOORのRSSを取得
        rss = getPrimaryAreaRSS(client, event['replyToken'])
        
        ## LIVEDOORのRSSから都道府県名(<pref title="沖縄">)を取得する
        prefectures = []
        xml = Oga.parse_xml(rss)
        xml.xpath('/rss/channel/ldWeather:source/pref').each do |pref|
          prefectures.push(pref.get('title'))
        end
        
        ## 入力(prefecture)がRSSから取得したものと一致するか比較する
        ## 一致しない：やり直し
        ## 一致する：地域をサジェストする
        ## ["道北", "道東", "道南", "道央", "道南", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"]
        ## 北海道は特別扱い
        if prefecture === '北海道'
          message = {
            type: 'text',
            text: '北海道の方は"道北", "道東", "道南", "道央", "道南"のいずれかを入力してください'
          }
        elsif prefectures.grep(/^#{prefecture}/).empty?
          message = {
            type: 'text',
            text: "一致する地域が見つかりませんでした。\n都道府県名を入力してください。"
          }
        else
          ## ボタンテンプレートのアクションの最大数は4
          ## https://developers.line.biz/ja/reference/messaging-api/#buttons
          ## TODO: カルーセルテンプレートで複数カラムにしたら回避可能
          ## とりあえずは4つ以上の地域でも4つまでにしてボタンテンプレートを使う
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
          p message
        end

        ## TODO: 例外処理を追加する
        ## https://easyramble.com/fix-ruby-net-http-bad-code.html
        ## https://docs.ruby-lang.org/ja/latest/class/Net=3a=3aHTTPResponse.html
        response = client.reply_message(event['replyToken'], message)
        p response
      end
    when Line::Bot::Event::Postback
      postback_data = event['postback']['data']
      message = {
        type: 'text',
        text: "city_id: #{postback_data}"
      }
      response = client.reply_message(event['replyToken'], message)
      p response
    end
  }
end

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