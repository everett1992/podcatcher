require 'nokogiri'
require 'open-uri'
require 'rubygems'

working = ['/', '-', '\\', '|'].cycle.each

MAX = 100000000
(0..MAX).each do |id|
  feed = Nokogiri::XML(open("http://www.npr.org/templates/rss/podlayer.php?id=#{id}"))

  title = feed.xpath('//channel/title').first.text
  any = feed.xpath('//channel/item/enclosure').any? do |enclosure|
    enclosure[:type].match(/audio/)
  end

  puts "#{id}:		#{title}" if any && title != 'Stories from NPR'
  print "#{working.next}\r"
end
