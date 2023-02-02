#!/usr/bin/env ruby 

require 'net/http'
require 'uri'
require 'json'
require 'date'
require 'slugify'

endpoint = 'http://localhost:4567/potw?json=1'
site_posts_dir = "~/src/simple/content/posts/"

date = Date.today.strftime("%Y-%m-%d") 
long_date = Time.now.strftime("%Y-%m-%dT%H:%M:%S%z")
title = date + '-potw'

slug = title.slugify
filename =  slug + '.md'
file_path = File.expand_path(site_posts_dir + filename)

if File.exists?(file_path)
  abort("*** Error: #{file_path} already exists. Exiting.")
end


uri = URI.parse(endpoint)
request = Net::HTTP::Get.new(uri)
request.basic_auth(ENV['IMGUP_USER'], ENV['IMGUP_PASS'])

req_options = {
  use_ssl: uri.scheme == "https",
}

response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
  http.request(request)
end

json = JSON.parse(response.body)

potw_post = <<-POTW
---
title: "Picture of the Week: #{json['title']}"
potw_gallery_link: #{json['image_link']}
potw_img_url: #{json['image_url']}
potw_alt: #{json['caption']}

date: #{long_date}
tags: ['potw','photography']
draft: true
---

{{< potw >}}

POTW

File.write(file_path, potw_post)

`open #{file_path}`
