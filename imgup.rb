#!/usr/bin/env ruby

require 'sinatra'
require 'haml'
require 'puma'
require 'sinatra/config_file'
require 'json'
require 'rest-client'
require 'typhoeus'
include FileUtils::Verbose

config_file 'settings.yaml'

set :haml, { escape_html: false }
set :sessions, true

cloudflare_account = settings.cloudflare_account
cloudflare_token = settings.cloudflare_token
base_url = "https://api.cloudflare.com/client/v4/accounts/#{cloudflare_account}/images/v1"

get "/", { provides: 'html' } do
  haml :index
end

get '/upload', { provides: 'html' } do
    haml :upload
end

post '/upload' do
    tempfile = params[:file][:tempfile] 
    filename = params[:file][:filename] 
    cp(tempfile.path, "public/uploads/#{filename}")
    redirect "/image/#{filename}"
end

get '/image/:image', { provides: 'html' } do
    @image = params[:image].to_s
    haml :image
end

post '/cloudflare_upload/:image' do 

  filename = params[:image]
  
  post = Typhoeus.post(base_url,
    headers: {:authorization => "Bearer #{cloudflare_token}"},
    body: {
      id: "#{filename}#{Time.now}",
      file: File.open("public/uploads/#{filename}","r")
    }
  )
  session[:resp] = JSON.parse(post.body)

  redirect "/image/#{filename}"

end

