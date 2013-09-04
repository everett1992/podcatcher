require 'nokogiri'
require 'open-uri'
require 'rubygems'

require 'rubygems'
require 'active_support/inflector'
require 'ruby-progressbar'
require 'colorize'
require 'taglib'

class Object
  # test.length if test
  # - vs -
  # test.try(:length)
  def try method
    send method if respond_to? method
  end
end

class Podcast
  attr_reader :title, :publish_date, :type, :url, :feed
  def initialize title, publish_date, type, url, feed
    @title, @publish_date, @type, @url, @feed = title, publish_date, type, url, feed
  end

  def is_audio?
    (not blank?(@type)) && @type.match(/audio/)
  end

  def is_downloaded?
    File.exists?(self.filename)
  end

  def filename
    file = []
    file << POD_DIR
    file << @feed.category if @feed.category
    file << @feed.title if @feed.title
    file << "#{@publish_date.strftime(DATE_FORMAT)}_#{@title}#{self.file_extension}"

    File.expand_path(File.join(file))
  end

  def file_extension
    File.extname(@url).split('?').first
  end

  def download args
    self.write(self.get(args))
  end

  def tag
    TagLib::FileRef.open(self.filename) do |fileref|
      tag = fileref.tag

      tag.title = "#{@publish_date.strftime DATE_FORMAT} #{@title}"
      tag.album = "Podcast"
      tag.artist = @feed.title
      fileref.save
    end
  end

  def get args
    open @url, args
  end

  def write podcast
    create_dirs File.dirname(self.filename)
    open(self.filename, "wb") do |file|
      file.write podcast.read
    end
  end
end

class Feed
  attr_accessor :url, :category, :title

  def initialize url, category, title
    @url, @category, @title = url, category, title
  end

  # Remove items that have have been downloaded already
  def new_podcasts
    feed = self.download_feed
    self.parse_feed(feed).reject { |podcast| !podcast.is_audio? || podcast.is_downloaded? }
  end

  protected

  # Parse a feed xml returning the title, url, and publish_date of each item
  def parse_feed feed 
    Nokogiri::XML(feed).xpath("//item").map do |item|
      enclosure = item.xpath("enclosure").first
      title = item.xpath("title").inner_html.chomp
      publish_date = Date.parse(item.xpath("pubDate").inner_html.chomp)
      type = enclosure ? enclosure[:type] : nil
      url = enclosure ? enclosure[:url] : nil
      Podcast.new title, publish_date, type, url, self
    end
  end

  def download_feed
    puts "Downloading #{@title.green} feed from #{@url}"
    open @url
  end
end

# utils
def blank? string
  string.nil? || !string.match(/[^\s]/)
end

def indent(*output) puts output.map { |a| ":: ".red + a }
end

#-- Feed Methods --#

# Parse each line into url, category, title
def parse_feed_line line
  # Return [url, category, title]
  Feed.new(*line.split(' ', 3).map(&:strip))
end

# Parse the feed file into an array of [url, category, title]
# ignoring lines that start with the comment charecter #
def parse_feed_file feed
  feed.each_line
    .reject { |line| blank?(line) || line[0] == '#' }
    .map { |line| parse_feed_line line}
end

#-- Podcast Methods --#


def size_to string, length
  if string.length > length
    append = "..."
    return string[0..(length - append.length - 1)] + append
  else
    return string.ljust(length)
  end
end

def download_podcasts podcasts
  max = podcasts.map(&:title).max.try(:length) || 0
  max = 40 if max > 70
  podcasts.each_with_index.map do |podcast, n|
    pb_title = "(#{n+1}/#{podcasts.length}) #{size_to(podcast.title, max)}"

    pb = ProgressBar.create title: pb_title, progress_mark: '#', smoothing: 0.5, format: '%t %a [%B] %p%%'
    set_total = lambda { |total| pb.total = total}
    progress = lambda { |size| pb.progress = size }

    podcast.download :content_length_proc => set_total, :progress_proc => progress
    podcast.tag

    podcast
  end
end

def create_dirs file
  unless Dir.exists? file
    create_dirs File.dirname(file)
    Dir.mkdir file
  end
end

# Download 
def get_podcast url, title, podcast_file
end

DATE_FORMAT = '%Y-%m-%d'

CONF_DIR = File.join(Dir.home, '.podcatcher')
FEED_FILE = File.join(CONF_DIR, 'serverlist')

POD_DIR = '~/Music/Podcasts/'

feeds = parse_feed_file File.new(FEED_FILE, 'r')
results = feeds.map do |feed|
  podcasts = feed.new_podcasts
  indent "#{podcasts.count} new #{feed.title} podcasts"
  downloaded = download_podcasts podcasts
  { title: feed.title, downloaded: downloaded }
end

results.each do |feed|
  length = feed[:downloaded].length
  if length > 0
    puts "#{feed[:title]}:"
    if length < 10
      feed[:downloaded].each { |e| indent e.title }
    else
      indent "#{length} new"
    end
  end
end
