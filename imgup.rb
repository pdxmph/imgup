#!/usr/bin/env ruby
require 'sinatra'
require 'haml'
require 'puma'
require 'sinatra/config_file'
require 'json'
require 'rest-client'
require 'typhoeus'
require 'exif'
include FileUtils::Verbose

# you'll need to edit and rename the example_settings.yaml to make this file
config_file 'settings.yaml'

set :haml, { escape_html: false }
set :sessions, true

# get our secrets out of the YAML file we promise we won't ever commit
cloudflare_account = settings.cloudflare_account
cloudflare_token = settings.cloudflare_token
cloudflare_account_hash = settings.cloudflare_account_hash

# the base API URL
base_url = "https://api.cloudflare.com/client/v4/accounts/#{cloudflare_account}/images/v1"

# the base url for images -- this one varies from the API docs because it is using a custom domain
# Cloudflare will use any domain it proxies for you
base_img_url = "https://www.puddingtime.org/cdn-cgi/imagedelivery/#{cloudflare_account_hash}"

# TODO put the normal base url in here

get "/", { provides: 'html' } do
  haml :index
end

get '/upload', { provides: 'html' } do
    haml :upload
end

post '/upload_cloudflare' do
    tempfile = params[:file][:tempfile] 
    filename = params[:file][:filename] 
    cp(tempfile.path, "public/uploads/#{filename}")
    
  begin
    exif_data = Exif::Data.new(File.open("public/uploads/#{filename}"))
    exif_model = exif_data.model
    exif_make = exif_data.make
    exif_camera = "#{exif_make}-#{exif_model}".downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
  rescue 
    exif_camera = "nocamera"
  end
  
  date_path = Date.today.strftime("%Y%m%d")
  post = Typhoeus.post(base_url,
    headers: {:authorization => "Bearer #{cloudflare_token}"},
    body: {
      id: "#{date_path}/#{exif_camera}-#{filename}",
      file: File.open("public/uploads/#{filename}","r")
    }
  )
  @resp = JSON.parse(post.body)
  res = @resp['result']
  img_id = @resp['result']['id']
  img_url = "#{base_img_url}/#{img_id}"
  redirect "/post_image/#{filename}?img_url=#{img_url}"
end

get '/image/:image', { provides: 'html' } do
    @image = params[:image].to_s
    haml :image
end

get '/post_image/:image', { provides: 'html' } do
    @image = params[:image].to_s
    haml :post_image
end
