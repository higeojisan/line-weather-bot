load "vendor/bundle/bundler/setup.rb"

require 'json'
require 'oga'
require 'jsonclient'

class LivedoorWeather
  PRIMARY_AREA_JSON_FILE = File.expand_path '../livedoor_data/primary_area.json', File.dirname(__FILE__)
  PRIMARY_AREA_XML_FILE = File.expand_path '../livedoor_data/primary_area.xml', File.dirname(__FILE__)
  WEATHER_INFO_URL = 'http://weather.livedoor.com/forecast/webservice/json/v1'

  def initialize
  end

  def get_city_name_and_pref_name(city_id)
    result = []
    File.open(PRIMARY_AREA_JSON_FILE) do |file|
      city_hash = JSON.load(file)["#{city_id}"]
      result << city_hash['city_name'] << city_hash['pref_name'] unless city_hash.nil?
    end
    result
  end

  def get_city_ids(prefecture)
    citys = []
    xml = Oga.parse_xml(File.read(PRIMARY_AREA_XML_FILE))
    xml.xpath("/rss/channel/ldWeather:source/pref[contains(@title, '#{prefecture}')]/city").each do |city|
      citys.push({ name: city.get('title'), id: city.get('id') })
    end
    citys
  end

  def format_weather_info_hash(city_id)
    raw_weather_info = get_weather_info_hash(city_id)
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

  private

  def get_weather_info_hash(city_id)
    client = JSONClient.new
    res = client.get("#{WEATHER_INFO_URL}?city=#{city_id}")
    res.status == 200 ? res.body.to_h : {}
  end
end