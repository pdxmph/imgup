#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'json'
require 'date'
require 'slugify'
require 'yaml'
require 'optparse'

# set default tags for each entry. The "tags" option allows you to add more
tags = ['photography', 'potw']

options = {}

OptionParser.new do |parser|
  parser.on("-t", "--test", "Changes the endpoint to localhost:4567") do |o|
    options[:test] = true
  end

  parser.on("-o", "--overwrite", "Danger: Overwrite the existing potw if there's a conflict.") do |o|
    options[:overwrite] = true
  end

  parser.on("-T", "--tags TAGS", "Comma-delimited tags for the post, e.g. 'banana,apple,pear'") do |o|
    options[:tags] = o.split(',')
    options[:tags].each do |t|
      tags << t
    end
  end

  parser.on("-h", "--help", "Get help.") do |o|
    puts parser
    exit(0)
  end

end.parse!

if options[:test] == true
  endpoint = 'http://localhost:4567/potw?json=1'
else
  endpoint = 'https://imgup.puddingtime.org/potw?json=1'
end

site_posts_dir = "~/src/simple/content/posts/"

date = Date.today.strftime("%Y-%m-%d")
long_date = Time.now.strftime("%Y-%m-%dT%H:%M:%S%z")
title = date + '-potw'

slug = title.slugify
filename =  slug + '.md'
file_path = File.expand_path(site_posts_dir + filename)

if File.exists?(file_path) && options[:overwrite] != true
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
yaml = YAML.dump(json)

potw_post = <<-POTW
#{yaml}

date: #{long_date}
tags: #{tags}
categories: ['photography']
draft: true
---

{{< potw >}}

POTW

File.write(file_path, potw_post)

`open #{file_path}`
