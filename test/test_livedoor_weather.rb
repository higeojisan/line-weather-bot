$:.unshift File.expand_path '../lib', File.dirname(__FILE__)

require 'minitest/autorun'
require 'minitest/reporters'
require 'livedoor_weather'

Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

class LivedoorWeatherTest < Minitest::Test
  ## 存在するcity_idの場合
  def test_get_city_name_and_pref_name_for_exist_city_id
    assert_equal ["土浦", "茨城県"], LivedoorWeather.get_city_name_and_pref_name("080020")
  end

  ## 存在しないcity_idの場合
  def test_get_city_name_and_pref_name_for_nonexist_city_id
    assert_empty LivedoorWeather.get_city_name_and_pref_name("9999999999")
  end

  ## 存在する都道府県名の場合
  def test_get_city_ids_from_livedoor_rss_for_exist_prefecture_name
    assert_equal [{ name: "東京", id: "130010" }, { name: "大島", id: "130020" }, { name: "八丈島", id: "130030" }, { name: "父島", id: "130040" }], LivedoorWeather.get_city_ids("東京都")
  end

  ## 存在しない都道府県名の場合
  def test_get_city_ids_from_livedoor_rss_for_nonexist_prefecture_name
    assert_empty LivedoorWeather.get_city_ids("存在しない都道府県名")
  end
end
