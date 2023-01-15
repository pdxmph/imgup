#!/usr/bin/env ruby

require 'sinatra'
require 'haml'
require 'puma'
require 'sinatra/config_file'
require 'json'
require 'oauth'
require 'oauth/consumer'

config_file 'settings.yaml'
set :haml, { escape_html: false }
set :sessions, true

api_key = settings.smugmug_key
api_secret = settings.smugmug_secret

base_url = 'https://api.smugmug.com'
request_token_path = '/services/oauth/1.0a/getRequestToken'
access_token_path =  '/services/oauth/1.0a/getAccessToken'
authorize_path =  '/services/oauth/1.0a/authorize'
callback_url = "oob"


before do
  session[:oauth] ||= {}  
  @consumer ||=OAuth::Consumer.new api_key, api_secret, {
    :site => "https://api.smugmug.com",
    :request_token_path => '/services/oauth/1.0a/getRequestToken',
    :access_token_path =>  '/services/oauth/1.0a/getAccessToken',
    :authorize_path =>  '/services/oauth/1.0a/authorize',
    :callback_url => 'http://localhost:4567/callback'
  }
  
  if !session[:oauth][:request_token].nil? && !session[:oauth][:request_token_secret].nil?
    @request_token = OAuth::RequestToken.new(@consumer, session[:oauth][:request_token], session[:oauth][:request_token_secret])
  end
  
  if !session[:oauth][:access_token].nil? && !session[:oauth][:access_token_secret].nil?
    @access_token = OAuth::AccessToken.new(@consumer, session[:oauth][:access_token], session[:oauth][:access_token_secret])
  end
end

get "/" do
  if @access_token
    erb :ready
  else
    erb :start
  end
end

get '/callback', { provides: 'html' } do
  haml :index
end

get "/request" do
  @request_token = @consumer.get_request_token
  session[:oauth][:request_token] = @request_token.token
  session[:oauth][:request_token_secret] = @request_token.secret
  redirect @request_token.authorize_url
end

get "/callback" do
  @access_token = @request_token.get_access_token :oauth_verifier => params[:oauth_verifier]
  session[:oauth][:access_token] = @access_token.token
  session[:oauth][:access_token_secret] = @access_token.secret
  redirect "/"
end

get "/logout" do
  session[:oauth] = {}
  redirect "/"
end

enable :inline_templates


__END__

@@ start
<a href="/request">PWN OAuth</a>

@@ ready
OAuth PWND. <a href="/logout">Retreat!</a>


