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
        ## リッチメニューで設定確認をタップされた時の処理
        if event.message['text'] == '設定地域の確認'
          ## user_idを取得してその人のcity_idを取得する
          ## TODO: 毎回LIVEDOORにアクセスしたくないからcity_idを一覧を永続化したい
          ## →jsonファイル化した(livedoor_data/primary_area.json)
          user_id = event['source']['userId']
          digested_user_id = Digest::SHA256.hexdigest("#{user_id}")
          s3_object = Aws::S3::Object.new(ENV['USER_INFO_BUCKET'], "#{digested_user_id}_info.csv")
          if s3_object.exists?
            s3_object_data = s3_object.get
            ## TODO: S3のパースはpush.rbにもあるので関数化する
            CSV.parse(s3_object_data.body.read, headers: true) do |row|
              ## 念のためuser_idが一致するか確認...一致しないケースあるの？って感じだけど
              if user_id == row['user_id']
                city_id = row['city_id']
                File.open(LIVEDOOR_JSON_FILE) do |file|
                  city_hash = JSON.load(file)["#{city_id}"]
                  message = {
                    type: 'text',
                    text: "あなたの設定地域は\n#{city_hash['city_name']}(#{city_hash['pref_name']})だよ"
                  }
                  response = client.reply_message(event['replyToken'], message)
                  p response
                end
                return
              else
                message = {
                  type: 'text',
                  text: "設定地域を取得出来ませんでした"
                }
                response = client.reply_message(event['replyToken'], message)
                p response
                return
              end
            end
          else
            message = {
              type: 'text',
              text: "設定地域を取得出来ませんでした"
            }
            response = client.reply_message(event['replyToken'], message)
            p response
          end
          return
        end

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
        elsif prefectures.grep(/^#{prefecture}/).empty? ## TODO: grepだと福だけ入力したら福島もしくは福井が引っかかってしまう...ので修正
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