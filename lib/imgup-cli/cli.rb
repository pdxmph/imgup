#!/usr/bin/env ruby
require "dotenv"
Dotenv.load('.env', File.expand_path('~/.imgup.env'))
require "optparse"
require "imgup-cli/uploader"

module ImgupCli
  class CLI
    def self.start(args = ARGV)
      options = { format: 'md' }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: imgup [options] <path/to/image>"
        opts.on("-t TITLE", "--title=TITLE", "Image title (default: filename)")   { |v| options[:title]   = v }
        opts.on("-c CAPTION", "--caption=CAPTION", "Image caption (optional)")   { |v| options[:caption] = v }
        opts.on("-f FORMAT", "--format=FORMAT", %w[org md html], "Output format (org, md, html)") { |v| options[:format] = v }
        opts.on("-h", "--help", "Display help") { puts opts; exit }
      end
      parser.parse!(args)

      file = args.first
      unless file && File.file?(file)
        $stderr.puts parser
        exit 1
      end

      result = Uploader.new(file, title: options[:title], caption: options[:caption]).call
      key = case options[:format]
            when 'org'  then :org
            when 'html' then :html
            else             :markdown
            end
      puts result.fetch(key)
    rescue OptionParser::InvalidOption => e
      $stderr.puts e.message
      exit 1
    rescue KeyError => e
      $stderr.puts "No snippet for format #{options[:format].inspect}"
      exit 1
    rescue => e
      $stderr.puts e.message
      exit 1
    end
  end
end
