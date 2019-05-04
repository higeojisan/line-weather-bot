$:.unshift File.expand_path '../lib', File.dirname(__FILE__)

require 'minitest/autorun'
require 'minitest/reporters'
require 'utils'

Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

class UtilsTest < Minitest::Test

  ## 正しいcity_idの場合
  def test_get_city_name_and_pref_name_for_correct_city_id
    assert_equal ["土浦", "茨城県"], get_city_name_and_pref_name("080020")
  end

  ## 存在しないcity_idの場合
  def test_get_city_name_and_pref_name_for_nonexist_city_id
    assert_empty get_city_name_and_pref_name("9999999999")
  end

end