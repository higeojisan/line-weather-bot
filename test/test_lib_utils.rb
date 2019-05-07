$:.unshift File.expand_path '../lib', File.dirname(__FILE__)

require 'minitest/autorun'
require 'minitest/reporters'
require 'utils'

Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

class UtilsTest < Minitest::Test
  ## 存在するcity_idの場合
  def test_get_city_name_and_pref_name_for_exist_city_id
    assert_equal ["土浦", "茨城県"], get_city_name_and_pref_name("080020")
  end

  ## 存在しないcity_idの場合
  def test_get_city_name_and_pref_name_for_nonexist_city_id
    assert_empty get_city_name_and_pref_name("9999999999")
  end

  ## 存在する都道府県名の場合
  def test_get_city_ids_from_livedoor_rss_for_exist_prefecture_name
    assert_equal [{ name: "東京", id: "130010" }, { name: "大島", id: "130020" }, { name: "八丈島", id: "130030" }, { name: "父島", id: "130040" }], get_city_ids_from_livedoor_rss("東京都")
  end

  ## 存在しない都道府県名の場合
  def test_get_city_ids_from_livedoor_rss_for_nonexist_prefecture_name
    assert_empty get_city_ids_from_livedoor_rss("存在しない都道府県名")
  end

  def test_city_select_template
    ## 正常系(4つより多い場合)
    assert_equal [{ type: "postback", label: "那覇", data: "471010", }, { type: "postback", label: "名護", data: "471020", }, { type: "postback", label: "久米島", data: "471030", }, { type: "postback", label: "南大東", data: "472000",  },], city_select_template([{ name: "那覇", id: "471010" }, { name: "名護", id: "471020" }, { name: "久米島", id: "471030" }, { name: "南大東", id: "472000" }, { name: "宮古島", id: "473000" }, { name: "石垣島", id: "474010" }, { name: "与那国島", id: "474020" }])

    ## 正常系(1つ以上4つ以下の場合)
    assert_equal [{ type: "postback", label: "鹿児島", data: "460010", }, { type: "postback", label: "鹿屋", data: "460020", }, { type: "postback", label: "種子島", data: "460030", }, { type: "postback", label: "名瀬", data: "460040",  }],  city_select_template([{ name: "鹿児島", id: "460010" }, { name: "鹿屋", id: "460020" }, { name: "種子島", id: "460030" }, { name: "名瀬", id: "460040" }])

    ## 異常系(引数が空の配列の場合)
    assert_empty city_select_template([])
  end

  def test_get_weather_info_from_city_id
    ## 正常系(200が返ってきた場合)
    refute_empty get_weather_info_from_city_id("011000")

    ## 異常系(200以外が返ってきた場合)
    assert_empty get_weather_info_from_city_id("9999999999")
  end
end
