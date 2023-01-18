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
# todo get rid of this as soon as we fix those auth 
enable :inline_templates

# get our variables out of .env
smugmug_token = ENV['SMUGMUG_TOKEN']
smugmug_secret = ENV['SMUGMUG_SECRET']
smugmug_upload_url = ENV['SMUGMUG_UPLOAD_URL']
smugmug_upload_album_id = ENV['SMUGMUG_UPLOAD_ALBUM_ID']
smugmug_upload_album_endpoint = ENV['SMUGMUG_UPLOAD_ALBUM_ENDPOINT']
base_upload_url = ENV['SMUGMUG_BASE_URL']

# oauth session
before do
  session[:oauth] ||= {}  
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

# our routes

# We need to check for this stuff everywhere we need to be logged in
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
  redirect '/'
end

# we go here to z out our oauth state
get "/logout" do
  session[:oauth] = {}
  redirect '/'
end


get "/response", { provides: 'html' } do 
  @resp = JSON.parse(params['resp'])
  @img_uri = "https://api.smugmug.com#{@resp['Image']['ImageUri']}"

  hydra = Typhoeus::Hydra.new
  req = Typhoeus::Request.new(@img_uri, 
    :method => "get",
    :followlocation => "true",
      :headers => {:Accept => "application/json",
      }
    )
  # set up the auth header
  oauth_params = { consumer: @consumer, token: @access_token }
  oauth_helper = OAuth::Client::Helper.new(req, oauth_params.merge(request_uri: @img_uri))
  req.options[:headers]["Authorization"] = oauth_helper.header # Signs the request
  
  # run the upload call 
  hydra.queue(req)
  hydra.run

  @image=JSON.parse(req.response.response_body)

  haml :response
end

# the heavy lifter
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

  response=req.response.response_body
  redirect "/response?resp=#{response}"
end


# optional -- just a user page to test stuff dynamically 
# could pull in some Smugmug user info for the fun of it or not 
# get "/user", { provides: 'html' } do 
#   @resp = params['resp']
#   haml :user
# end

# __END__

# @@ start
# <a href="/request">PWN OAuth</a>

# @@ ready
# OAuth PWND. <a href="/logout">Retreat!</a>
