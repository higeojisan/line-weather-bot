require 'rexml/document'
require 'json'

results = {}

rexml_doc = REXML::Document.new(File.open("primary_area.xml").read)
rexml_doc.elements.each("//ldWeather:source/*") do |elem|
  elem.elements.each("//pref[@title='#{elem.attribute("title").value}')]/city") do |city|
    results[:"#{city.attribute('id').value}"] = { city_name: city.attribute("title").value, pref_name: elem.attribute("title").value }
  end
end

File.open("primary_area.json", "w") do |f|
  f.write JSON.pretty_generate(results)
end
