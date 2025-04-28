# lib/imgup/uploader.rb

require 'fileutils'
require 'net/http'
require 'uri'
require 'json'
require 'oauth'
require 'oauth/client/net_http'   # Net::HTTP signing support
require 'dotenv/load'
require 'net/http/post/multipart'  # from multipart-post gem

module ImgUp
  class Uploader
    def initialize(filepath, title: nil, caption: nil)
      @filepath = filepath
      @title    = title   || File.basename(filepath, '.*')
      @caption  = caption || ''
      load_env
    end

    # Copy → upload → cleanup → result
    def call
      tmp_path = copy_to_tmp
      image    = upload_file(tmp_path)
      cleanup_tmp(tmp_path)
      build_result(image)
    end

    private

    # Load ENV vars; dotenv auto-loads your .env
    def load_env
      @consumer_key        = ENV.fetch('SMUGMUG_TOKEN')
      @consumer_secret     = ENV.fetch('SMUGMUG_SECRET')
      @access_token        = ENV.fetch('SMUGMUG_ACCESS_TOKEN')
      @access_token_secret = ENV.fetch('SMUGMUG_ACCESS_TOKEN_SECRET')
      @album_id            = ENV.fetch('SMUGMUG_UPLOAD_ALBUM_ID')
      @upload_url          = ENV.fetch('SMUGMUG_UPLOAD_URL', 'https://upload.smugmug.com/')
    end

    # Make a tmp copy so originals stay untouched
    def copy_to_tmp
      FileUtils.mkdir_p('tmp')
      tmp = File.join('tmp', File.basename(@filepath))
      FileUtils.cp(@filepath, tmp)
      tmp
    end

    # Perform the multipart POST with OAuth1 signing
    def upload_file(tmp_path)
      uri = URI.parse(@upload_url)

      # Build the multipart request
      file_io = UploadIO.new(
        File.open(tmp_path),
        'application/octet-stream',
        File.basename(tmp_path)
      )
      req = Net::HTTP::Post::Multipart.new(
        uri.request_uri,
        'file' => file_io
      )

      # Add SmugMug headers
      {
        'X-Smug-AlbumUri'     => "/api/v2/album/#{@album_id}",
        'X-Smug-ResponseType' => 'JSON',
        'X-Smug-Version'      => 'v2',
        'X-Smug-Filename'     => File.basename(tmp_path),
        'X-Smug-Title'        => @title,
        'X-Smug-Caption'      => @caption
      }.each { |k, v| req[k] = v }

      # Sign with OAuth1: set site to the upload host so scheme & host are known
      consumer = OAuth::Consumer.new(
        @consumer_key,
        @consumer_secret,
        site: "#{uri.scheme}://#{uri.host}"
      )
      access = OAuth::AccessToken.new(
        consumer,
        @access_token,
        @access_token_secret
      )
      access.sign! req

      # Fire the request
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      resp = http.request(req)

      # On error, raise with a clear message
      unless resp.is_a?(Net::HTTPSuccess)
        raise "Upload failed: HTTP #{resp.code} (#{resp.message})\n" \
              "Response body: #{resp.body}"
      end

      # The JSON comes back as:
      # { "stat":"ok", "method":"smugmug.images.upload",
      #   "Image": { ..., "URL":"http://example.smugmug.com/..." }
      # }
      JSON.parse(resp.body)['Image']
    end

    # Clean up tmp file
    def cleanup_tmp(path)
      FileUtils.rm_f(path)
    end

    # Build the return hash, using the 'URL' field
    def build_result(image)
      image_url = image['URL']
      {
        url:      image_url,
        markdown: "![#{@title}](#{image_url})",
        html:     "<img src='#{image_url}' alt='#{@title}' />"
      }
    end
  end
end
