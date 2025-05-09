#!/usr/bin/env ruby
require 'dotenv'
Dotenv.load('.env', File.expand_path('~/.imgup.env'))
require 'optparse'
require_relative 'config'
require_relative 'setup'
require_relative 'uploader'

module ImgupCli
  class CLI
    def self.start(args = ARGV)
      # Setup subcommand: guide through OAuth onboarding
      if args.first == 'setup'
        args.shift
        cfg = ImgupCli::Config.load

        consumer_key    = ENV['SMUGMUG_TOKEN']  || cfg['consumer_key']
        consumer_secret = ENV['SMUGMUG_SECRET'] || cfg['consumer_secret']

        unless consumer_key && consumer_secret
          print 'SmugMug Consumer Key: '
          consumer_key = STDIN.gets.strip
          print 'SmugMug Consumer Secret: '
          consumer_secret = STDIN.gets.strip
        end

        ImgupCli::Setup.run(
          consumer_key:    consumer_key,
          consumer_secret: consumer_secret
        )
        exit
      end

      # Normal upload flow: load saved credentials
      cfg = ImgupCli::Config.load
      ENV['SMUGMUG_TOKEN']               ||= cfg['consumer_key']
      ENV['SMUGMUG_SECRET']              ||= cfg['consumer_secret']
      ENV['SMUGMUG_ACCESS_TOKEN']        ||= cfg['access_token']
      ENV['SMUGMUG_ACCESS_TOKEN_SECRET'] ||= cfg['access_token_secret']
      ENV['SMUGMUG_UPLOAD_ALBUM_ID']     ||= cfg['album_id']

      options = { format: 'md' }
      parser  = OptionParser.new do |opts|
        opts.banner = 'Usage: imgup [setup] | [options] <path/to/image>'
        opts.on('-t TITLE', '--title=TITLE', 'Image title (default: filename)')      { |v| options[:title]   = v }
        opts.on('-c CAPTION', '--caption=CAPTION', 'Image caption (optional)')      { |v| options[:caption] = v }
        opts.on('-f FORMAT', '--format=FORMAT', %w[org md html], 'Output format')   { |v| options[:format]  = v }
        opts.on('-h', '--help', 'Display help') { puts opts; exit }
      end

      begin
        parser.parse!(args)
      rescue OptionParser::InvalidOption => e
        $stderr.puts e.message
        exit 1
      end

      image_path = args.first
      unless image_path && File.file?(image_path)
        $stderr.puts parser
        exit 1
      end

      begin
        result = ImgupCli::Uploader.new(
          image_path,
          title:   options[:title],
          caption: options[:caption]
        ).call

        snippet_key = (%w[org html].include?(options[:format]) ? options[:format] : 'markdown').to_sym
        puts result.fetch(snippet_key)
      rescue KeyError
        $stderr.puts "No snippet available for format #{options[:format].inspect}"
        exit 1
      rescue StandardError => e
        $stderr.puts e.message
        exit 1
      end
    end
  end
end
