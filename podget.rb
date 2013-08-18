require 'nokogiri'
require 'open-uri'
require 'rubygems'

require 'ruby-progressbar'
require 'colorize'
require 'taglib'

# utils
def blank? string
  string.nil? || !string.match(/[^\s]/)
end


# -- Feed Methods --#

# Parse each line into url, category, title
def parse_feed_line line
  # Return [url, category, title]
  line.split(' ', 3).map(&:strip)
end

# Parse the feed file into an array of [url, category, title]
# ignoring lines that start with the comment charecter #
def parse_feed_file feed
  feed.each_line
    .reject { |line| line[0] == '#' }
    .map { |line| parse_feed_line line}
end

#-- Podcast Methods --#

# Checks if the url has been downloaded already
def is_recorded? url
  blank?(url) || File.exists?(DONE_FILE) && File.new(DONE_FILE, "r").each_line.include?(url + "\n")
end

def is_audio? type
  (not blank?(type)) && type.match(/audio/)
end

# Parse a feed xml returning the title, url, and publish_date of each item
def parse_feed feed 
  Nokogiri::XML(feed).xpath("//item").map do |item|
    enclosure = item.xpath("enclosure").first
    { 
      title: item.xpath("title").inner_html.chomp,
      publish_date: Date.parse(item.xpath("pubDate").inner_html.chomp),
      type: enclosure ? enclosure[:type] : nil,
      url: enclosure ? enclosure[:url] : nil
    }
  end
end

# Remove items that have have been downloaded already
def new_podcasts items
  items.reject { |item| (not is_audio?(item[:type])) || is_recorded?(item[:url]) }
end

# TODO: this overwrites the file each time it is called, it needs to append instead.
def record_done url
  File.open(DONE_FILE, "a") { |f| f.puts(url) } unless is_recorded? url
end

def download_feed url, args = {}
  open url
end

def download_podcast url, args = {}
  download url, args.merge(format: '%t %a [%B] %p%%')
end

def download url, args = {}
  pb = ProgressBar.create args.merge progress_mark: '#', smoothing: 0.5
  set_total = lambda { |total| pb.total = total}
  progress = lambda { |size| pb.progress = size }
  file = open url, :content_length_proc => set_total, :progress_proc => progress
  return file
end

def size_to string, length
  if string.length > length
    append = "..."
    return string[0..(length-append.length-1)] + append
  else
    return string.ljust(length)
  end
end

def longest_title_length items
  items.max_by{|item| item[:title].length}[:title].length
end

def podcast_file url, show_title, publish_date, podcast_title, category
  file = []
  file << POD_DIR
  file << category if category
  file << podcast_title if podcast_title
  file << "#{publish_date.strftime(DATE_FORMAT)}_#{show_title}#{File.extname(url)}"

  File.expand_path(File.join(file))
end

def retag_file file, show_title, publish_date, podcast_title
  TagLib::FileRef.open(file) do |fileref|
    tag = fileref.tag

    tag.title = "#{publish_date.strftime DATE_FORMAT} #{show_title}"
    tag.album = "Podcast"
    tag.artist = podcast_title
    fileref.save
  end
end

def download_podcasts items, podcast_title, podcast_category
  max = longest_title_length items
  max = 40 if max > 40
  items.each_with_index.map do |item, n|
    url, show_title, publish_date = item[:url], item[:title], item[:publish_date]

    pb_title = "(#{n+1}/#{items.length}) #{size_to(show_title, max)}"
    file = podcast_file url, show_title, publish_date, podcast_title, podcast_category

    get_podcast url, pb_title, file
    retag_file file, show_title, publish_date, podcast_title
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
  create_dirs File.dirname(podcast_file)
  open(podcast_file, "wb") do |file|
    file.write download_podcast(url, title: title).read
  end
  record_done url
end

def indent(*output)
  puts output.map { |a| ":: ".red + a }
end

DATE_FORMAT = '%Y-%m-%d'

FEED_FILE = './serverlist'
DONE_FILE = './done'

POD_DIR = '~/Dropbox/podcasts/'

feeds = parse_feed_file File.new(FEED_FILE, 'r')
feeds.each do |url, category, title|
  puts "Downloading #{title.green} feed from #{url}"
  feed = download_feed url, title: title
  indent "Parsing feed file"
  items = new_podcasts(parse_feed(feed))
  indent "#{items.length} new #{title} podcasts"
  download_podcasts items, title, category
end
