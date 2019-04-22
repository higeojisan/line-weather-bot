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
        
        ## LIVEDOORのRSS(http://weather.livedoor.com/forecast/rss/primary_area.xml)に入力されたprefectureがあるか確認する
        rss = getPrimaryAreaRSS(client, event['replyToken'])
        p rss

        #client.reply_message(event['replyToken'], message)
      end
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