#!/usr/bin/env ruby
require 'sinatra'
require 'puma'
require 'haml'
require 'json'
require 'typhoeus'
require 'oauth'
require 'oauth/consumer'
require 'uri'
require "oauth/request_proxy/typhoeus_request"
include FileUtils::Verbose
require_relative 'lib/imgup/uploader'
require 'dotenv/load'
Dotenv.load('.env', File.expand_path('~/.imgup.env'))

p ENV.slice(
  'SMUGMUG_TOKEN',
  'SMUGMUG_SECRET',
  'SMUGMUG_ACCESS_TOKEN',
  'SMUGMUG_ACCESS_TOKEN_SECRET',
  'SMUGMUG_UPLOAD_ALBUM_ID'
)

#— your SmugMug config pulled from ENV —
API_BASE        = ENV.fetch('SMUGMUG_API_URL',      'https://api.smugmug.com')
UPLOAD_URL      = ENV.fetch('SMUGMUG_UPLOAD_URL',    'https://upload.smugmug.com/')
ALBUM_ID        = ENV.fetch('SMUGMUG_UPLOAD_ALBUM_ID')
CONSUMER_KEY    = ENV.fetch('SMUGMUG_TOKEN')
CONSUMER_SECRET = ENV.fetch('SMUGMUG_SECRET')
ACCESS_TOKEN    = ENV.fetch('SMUGMUG_ACCESS_TOKEN')
ACCESS_SECRET   = ENV.fetch('SMUGMUG_ACCESS_TOKEN_SECRET')

#— build your OAuth client once —
CONSUMER = OAuth::Consumer.new(CONSUMER_KEY, CONSUMER_SECRET, site: API_BASE)
ACCESS   = OAuth::AccessToken.new(CONSUMER, ACCESS_TOKEN, ACCESS_SECRET)


set :environment, :production
set :bind, '0.0.0.0'
run_dir = File.dirname(__FILE__)
run_dir = Dir.pwd if (run_dir == '.')

Dir.mkdir("tmp") unless Dir.exist?("tmp")

set :haml, { escape_html: false }
set :sessions, true

smugmug_upload_url = "https://upload.smugmug.com/"
smugmug_base_url = "https://api.smugmug.com"

# get our variables out of .env
smugmug_token = ENV['SMUGMUG_TOKEN']
smugmug_secret = ENV['SMUGMUG_SECRET']
smugmug_upload_album_id = ENV['SMUGMUG_UPLOAD_ALBUM_ID']
smugmug_upload_album_endpoint = "/api/v2/album/#{ENV['SMUGMUG_UPLOAD_ALBUM_ID']}"

# If you know your access token info, put it in `.env` 
# Once you do that, you can use these two variables below in the session[:oauth] instantiation
# Once you sign in, you can grab these variables from `/tokens`
sm_access_token = ENV['SMUGMUG_ACCESS_TOKEN']
sm_access_token_secret = ENV['SMUGMUG_ACCESS_TOKEN_SECRET']

# oauth session
before do
  session[:oauth] ||= {}  
  if sm_access_token != nil && sm_access_token_secret != nil
   session[:oauth][:access_token] = sm_access_token
   session[:oauth][:access_token_secret] = sm_access_token_secret
 end
  @consumer ||=OAuth::Consumer.new smugmug_token,smugmug_secret, {
    :site => "https://api.smugmug.com",
    :request_token_path => '/services/oauth/1.0a/getRequestToken',
    :access_token_path =>  '/services/oauth/1.0a/getAccessToken',
    :authorize_path =>  "/services/oauth/1.0a/authorize",
    :oauth_callback => 'http://localhost:4567/callback'
      }  

  if !session[:oauth][:request_token].nil? && !session[:oauth][:request_token_secret].nil?
    @request_token = OAuth::RequestToken.new(@consumer, session[:oauth][:request_token], session[:oauth][:request_token_secret])
  end
  
  if !session[:oauth][:access_token].nil? && !session[:oauth][:access_token_secret].nil?
    @access_token = OAuth::AccessToken.new(@consumer, session[:oauth][:access_token], session[:oauth][:access_token_secret])
  end
end

# Offers a Smugmug auth if you don't have access tokens
get "/" do
    haml :index
end

#  this is where we go to get a request token
get "/request" do
  @request_token = @consumer.get_request_token
  session[:oauth][:request_token] = @request_token.token
  session[:oauth][:request_token_secret] = @request_token.secret
  redirect @request_token.authorize_url
end

# this is where we go to get our access token
get "/auth" do
  @access_token = @request_token.get_access_token :oauth_verifier => params[:oauth_verifier]
  session[:oauth][:access_token] = @access_token.token
  session[:oauth][:access_token_secret] = @access_token.secret
  redirect '/tokens'
end

# we go here to z out our oauth state
get "/logout" do
  session[:oauth] = {}
  redirect '/'
end

# use this to get your access token and secret once you've authentiated
# store those in .env and you can avoid re-authing every time you restart
get '/tokens' do 
  @access = @access_token.token
  @secret = @access_token.secret
  haml :tokens
end

# the heavy lifter
# this is a little cargo-culty -- rather than teeing up a big Typhoeus thing, 
# you can use the access token's `get` method. 
# TODO: Check out the headers syntax for that
# Yup. Looks like this:
# @response = @token.post('/people', @person.to_xml, { 'Accept'=>'application/xml', 'Content-Type' => 'application/xml' })

post '/upload_smugmug' do
  file    = params[:file][:tempfile].path
  title   = params[:title]
  caption = params[:caption]

  # use the same Uploader class the CLI uses
  result = ImgUp::Uploader.new(
    file,
    title:   title,
    caption: caption
  ).call

  # pull the fully‐qualified URL & snippets from its hash
  @img_url  = result[:url]       # e.g. https://photos.smugmug.com/…/i-XXX-XL.jpg
  @markdown = result[:markdown]  # ![…](https://…)
  @html     = result[:html]      # <img src='…' alt='…' />
  @org      = result[:org]       # uses custom org img link format
  haml :post_image
end


# This is just to help see what comes back for elsewhere
get '/post_image', { provides: 'html' } do 
  @image = session[:image]
  image_uri = @image['ImageUri']
  
  image_path = "https://api.smugmug.com" + image_uri 
  
  @image_data = @access_token.get(image_path, { 'Accept'=>'application/json' }).body
  @image_sizes = @access_token.get(image_path + "!sizedetails", { 'Accept'=>'application/json' }).body
  @image_metadata = @access_token.get(image_path + "!metadata", { 'Accept'=>'application/json' }).body

  @thumbnail = JSON.parse(@image_data)['Response']['Image']['ThumbnailUrl']
  @alt = JSON.parse(@image_data)['Response']['Image']['Caption']
  @image_url = JSON.parse(@image_sizes)['Response']['ImageSizeDetails']['ImageSizeXLarge']['Url']
   

  haml :post_image
end

# imgup.rb

# in imgup.rb, replace your get '/recent' block with this:

# imgup.rb
get '/recent', provides: 'html' do
  # 1) Determine how many to fetch (default 10)
  count = params[:count] || 10

  # 2) Fetch the album’s image list via the !images expansion
  album_path = "#{API_BASE}/api/v2/album/#{ALBUM_ID}!images?count=#{count}"
  image_list = ACCESS.get(album_path, { 'Accept' => 'application/json' }).body
  @album_images = JSON.parse(image_list).dig('Response','AlbumImage') || []

  # 3) Build @recents just like your old code did
  @recents = @album_images.map do |i|
    image_uri    = i.dig('Uris','Image','Uri')
    title        = i['Title']
    thumb        = i['ThumbnailUrl']
    caption      = i['Caption']
    link         = i['WebUri']

    # 4) Fetch the sizedetails for XLarge
    sizes_path  = "#{API_BASE}#{image_uri}!sizedetails"
    sizes_body  = ACCESS.get(sizes_path, { 'Accept' => 'application/json' }).body
    image_url   = JSON.parse(sizes_body)
                  .dig('Response','ImageSizeDetails','ImageSizeXLarge','Url')

    {
      thumb:      thumb,
      caption:    caption,
      image_url:  image_url,
      title:      title,
      image_link: link
    }
  end

  haml :recent
end

get '/potw', {provides: 'html'} do
  
  if(params.has_key?(:count))
    count = params[:count]
  else
    count = 5
  end
  
  if(params.has_key?(:json)) 
    json = true
    count = 1
  end

  album_path = smugmug_base_url + "/api/v2/album/hpBgzt!images?count=#{count}"
  image_list = @access_token.get(album_path, { 'Accept' => 'application/json' }).body
  @album_images = JSON.parse(image_list)['Response']['AlbumImage']
  @recents = []
  
  @album_images.each do |i|
    image_key = i['ImageKey']
    image_uri = i['Uris']['Image']['Uri']
    title = "Picture of the Week: " + i['Title']
    thumb = i['ThumbnailUrl']
    potw_alt = i['Caption']
    potw_gallery_link = i['WebUri']
    image_path = smugmug_base_url + image_uri
    image_sizes = @access_token.get(image_path + "!sizedetails", { 'Accept'=>'application/json' }).body
    potw_img_url = JSON.parse(image_sizes)['Response']['ImageSizeDetails']['ImageSizeXLarge']['Url']
    @recents << {:thumb => thumb, 
      :potw_alt => potw_alt, 
      :potw_img_url => potw_img_url, 
      :title => title, 
      :potw_gallery_link => potw_gallery_link}
  end

unless json == true
  haml :potw
else 
  content_type  :json
  @recents.first.to_json
end

end



