load "vendor/bundle/bundler/setup.rb"

require 'json'
require 'oga'

class LivedoorWeather
  PRIMARY_AREA_JSON_FILE = File.expand_path '../livedoor_data/primary_area.json', File.dirname(__FILE__)
  PRIMARY_AREA_XML_FILE = File.expand_path '../livedoor_data/primary_area.xml', File.dirname(__FILE__)


  def self.get_city_name_and_pref_name(city_id)
    result = []
    File.open(PRIMARY_AREA_JSON_FILE) do |file|
      city_hash = JSON.load(file)["#{city_id}"]
      result << city_hash['city_name'] << city_hash['pref_name'] unless city_hash.nil?
    end
    result
  end

  def self.get_city_ids(prefecture)
    citys = []
    xml = Oga.parse_xml(File.read(PRIMARY_AREA_XML_FILE))
    xml.xpath("/rss/channel/ldWeather:source/pref[contains(@title, '#{prefecture}')]/city").each do |city|
      citys.push({ name: city.get('title'), id: city.get('id') })
    end
    citys
  end
end