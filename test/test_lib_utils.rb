$:.unshift File.expand_path '../lib', File.dirname(__FILE__)

require 'minitest/autorun'
require 'minitest/reporters'
require 'utils'

Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

class UtilsTest < Minitest::Test
  def test_city_select_template
    ## 正常系(4つより多い場合)
    assert_equal [{ type: "postback", label: "那覇", data: "471010", }, { type: "postback", label: "名護", data: "471020", }, { type: "postback", label: "久米島", data: "471030", }, { type: "postback", label: "南大東", data: "472000",  },], city_select_template([{ name: "那覇", id: "471010" }, { name: "名護", id: "471020" }, { name: "久米島", id: "471030" }, { name: "南大東", id: "472000" }, { name: "宮古島", id: "473000" }, { name: "石垣島", id: "474010" }, { name: "与那国島", id: "474020" }])

    ## 正常系(1つ以上4つ以下の場合)
    assert_equal [{ type: "postback", label: "鹿児島", data: "460010", }, { type: "postback", label: "鹿屋", data: "460020", }, { type: "postback", label: "種子島", data: "460030", }, { type: "postback", label: "名瀬", data: "460040",  }],  city_select_template([{ name: "鹿児島", id: "460010" }, { name: "鹿屋", id: "460020" }, { name: "種子島", id: "460030" }, { name: "名瀬", id: "460040" }])

    ## 異常系(引数が空の配列の場合)
    assert_empty city_select_template([])
  end

  def test_format_prefecture_name
    assert_equal '東京都', format_prefecture_name('東京')
    assert_equal '大阪府', format_prefecture_name('大阪')
    assert_equal '京都府', format_prefecture_name('京都')
    assert_equal '茨城県', format_prefecture_name('茨城')
    assert_equal '東京都', format_prefecture_name('東京都')
    assert_equal '大阪府', format_prefecture_name('大阪府')
    assert_equal '京都府', format_prefecture_name('京都府')
    assert_equal '茨城県', format_prefecture_name('茨城県')
    assert_equal 'あああ', format_prefecture_name('あああ')
  end
end
