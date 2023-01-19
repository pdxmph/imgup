#!/usr/bin/env ruby
require 'sinatra'
require 'dotenv/load'
require 'puma'
require 'haml'
require 'json'
require 'typhoeus'
require 'oauth'
require 'oauth/consumer'
require "oauth/request_proxy/typhoeus_request"
require 'pry'

include FileUtils::Verbose

# won't run in production unless you get rid of this or set environment variables for secrets, etc. 
unless ENV['APP_ENV'] == 'production'
  require 'dotenv/load'
end

set :haml, { escape_html: false }
set :sessions, true

# get our variables out of .env
smugmug_token = ENV['SMUGMUG_TOKEN']
smugmug_secret = ENV['SMUGMUG_SECRET']
smugmug_upload_url = ENV['SMUGMUG_UPLOAD_URL']
smugmug_upload_album_id = ENV['SMUGMUG_UPLOAD_ALBUM_ID']
smugmug_upload_album_endpoint = ENV['SMUGMUG_UPLOAD_ALBUM_ENDPOINT']
base_upload_url = ENV['SMUGMUG_BASE_URL']
smugmug_base_url = "https://api.smugmug.com"

# If you know your access token info, put it in `.env` 
# Once you do that, you can use these two variables below in the session[:oauth] instantiation
# Once you sign in, you can grab these vatiables from `/tokens`
sm_access_token = ENV['SMUGMUG_ACCESS_TOKEN']
sm_access_token_secret = ENV['SMUGMUG_ACCESS_TOKEN_SECRET']

# oauth session
before do
  session[:oauth] ||= {}  
  # comment out this line if you don't have your access token
  # session[:oauth][:access_token] = sm_access_token
  # comment out this line if you don't have your access token
  # session[:oauth][:access_token_secret] = sm_access_token_secret
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
  tempfile = params[:file][:tempfile] 
  filename = params[:file][:filename]
  caption = params[:caption]
  title = params[:title]

  cp(tempfile.path, "#{filename}")
  
  # Set up the call to the API, but don't fire it off just yet
  hydra = Typhoeus::Hydra.new
  req = Typhoeus::Request.new(smugmug_upload_url, 
    :method => "post",
    :body => 
      {file: File.open("#{filename}","r")},
    :headers => {
      "X-Smug-AlbumUri" => smugmug_upload_album_endpoint,
      "X-Smug-ResponseType" => "JSON",
      "X-Smug-Version" => "v2",
      "X-Smug-Filename" => filename,
      "X-Smug-Title" => title,
      "X-Smug-Caption" => caption
    }
    )
  # set up the auth header
  oauth_params = { consumer: @consumer, token: @access_token }
  oauth_helper = OAuth::Client::Helper.new(req, oauth_params.merge(request_uri: smugmug_upload_url))
  req.options[:headers]["Authorization"] = oauth_helper.header # Signs the request
  
  # run the upload call 
  hydra.queue(req)
  hydra.run

  # This keeps the response URLs tidy and send JSON over
  image = JSON.parse(req.response.response_body)['Image']
  session[:image] = image


  redirect "/post_image"
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
  @image_url = JSON.parse(@image_sizes)['Response']['ImageSizeDetails']['ImageSizeX2Large']['Url']

  haml :post_image
end

# This is just to help see what comes back for elsewhere
get '/response', { provides: 'html' } do 
  @image = session[:image]
  image_uri = @image['ImageUri']
  
  image_path = "https://api.smugmug.com" + image_uri 
  
  @image_data = @access_token.get(image_path, { 'Accept'=>'application/json' }).body
  @image_sizes = @access_token.get(image_path + "!sizedetails", { 'Accept'=>'application/json' }).body
  @image_metadata = @access_token.get(image_path + "!metadata", { 'Accept'=>'application/json' }).body

  haml :response
end

# Eventually a list of recent images with a way to quickly get sharing links to your clipboard
get '/recent', {provides: 'html'} do 
  album_path = smugmug_base_url + '/api/v2/album/8m9hF8!images'
  @album_images = @access_token.get(album_path, { 'Accept'=>'application/json' }).body

  # much more to come

  haml :recent
end

