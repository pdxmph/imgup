# lib/imgup/uploader.rb

require 'fileutils'
require 'net/http'
require 'uri'
require 'json'
require 'oauth'
require 'oauth/client/net_http'   # for OAuth signing
require 'dotenv/load'
require 'net/http/post/multipart'

module ImgUp
  class Uploader
    def initialize(filepath, title: nil, caption: nil)
      @filepath = filepath
      @title    = title   || File.basename(filepath, '.*')
      @caption  = caption || ''
      load_env
      setup_oauth_client
    end

    # Complete flow: copy → upload → cleanup → fetch sizes → result
    def call
      tmp      = copy_to_tmp
      image    = upload_file(tmp)
      cleanup_tmp(tmp)
      full_url = fetch_full_url(image)
      build_result(full_url)
    end

    private

    def load_env
      @consumer_key        = ENV.fetch('SMUGMUG_TOKEN')
      @consumer_secret     = ENV.fetch('SMUGMUG_SECRET')
      @access_token        = ENV.fetch('SMUGMUG_ACCESS_TOKEN')
      @access_token_secret = ENV.fetch('SMUGMUG_ACCESS_TOKEN_SECRET')
      @album_id            = ENV.fetch('SMUGMUG_UPLOAD_ALBUM_ID')
      @upload_url          = ENV.fetch('SMUGMUG_UPLOAD_URL', 'https://upload.smugmug.com/')
      @api_base            = ENV.fetch('SMUGMUG_API_URL',  'https://api.smugmug.com')
    end

    def setup_oauth_client
      @consumer = OAuth::Consumer.new(
        @consumer_key,
        @consumer_secret,
        site: @api_base
      )
      @access = OAuth::AccessToken.new(
        @consumer,
        @access_token,
        @access_token_secret
      )
    end

    def copy_to_tmp
      FileUtils.mkdir_p('tmp')
      tmp = File.join('tmp', File.basename(@filepath))
      FileUtils.cp(@filepath, tmp)
      tmp
    end

    def upload_file(tmp_path)
      uri = URI.parse(@upload_url)

      file_io = UploadIO.new(
        File.open(tmp_path),
        'application/octet-stream',
        File.basename(tmp_path)
      )
      req = Net::HTTP::Post::Multipart.new(
        uri.request_uri,
        'file' => file_io
      )

      # SmugMug-specific headers
      {
        'X-Smug-AlbumUri'     => "/api/v2/album/#{@album_id}",
        'X-Smug-ResponseType' => 'JSON',
        'X-Smug-Version'      => 'v2',
        'X-Smug-Filename'     => File.basename(tmp_path),
        'X-Smug-Title'        => @title,
        'X-Smug-Caption'      => @caption
      }.each { |k, v| req[k] = v }

      upload_consumer = OAuth::Consumer.new(
        @consumer_key,
        @consumer_secret,
        site: "#{uri.scheme}://#{uri.host}"
      )
      upload_access = OAuth::AccessToken.new(
        upload_consumer,
        @access_token,
        @access_token_secret
      )
      upload_access.sign! req

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        raise "Upload failed: HTTP #{resp.code} (#{resp.message})\n" \
              "Response body: #{resp.body}"
      end

      JSON.parse(resp.body)['Image']
    end

    def fetch_full_url(image)
      image_uri = image['ImageUri'] || image['Uri']
      raise "No ImageUri found in upload response: #{image.inspect}" unless image_uri

      uri = URI.join(@api_base, "#{image_uri}!sizes")
      req = Net::HTTP::Get.new(uri.request_uri)
      req['Accept'] = 'application/json'
      @access.sign! req

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        raise "Size-fetch failed: HTTP #{resp.code} (#{resp.message})"
      end

      body = JSON.parse(resp.body)

      # New v2 array format
      sizes = body.dig('Response', 'ImageSizes', 'Size')
      if sizes.is_a?(Array) && sizes.any?
        best = sizes.max_by { |s| s['Width'].to_i }
        return best['Url']
      end

      # Fallback: old hash mapping format under 'Response'->'ImageSizes'
      sizes_hash = body.dig('Response', 'ImageSizes')
      if sizes_hash.is_a?(Hash)
        return sizes_hash['XLargeImageUrl']    if sizes_hash['XLargeImageUrl']
        return sizes_hash['LargestImageUrl']   if sizes_hash['LargestImageUrl']
        return sizes_hash['OriginalImageUrl']  if sizes_hash['OriginalImageUrl']
        candidates = sizes_hash.select { |k,_| k.end_with?('ImageUrl') }
        best_k, best_v = candidates.sort_by { |k,_| k.length }.last
        return best_v if best_v
      end

      raise "No image size URL found in size response: #{body.inspect}"
    end

    def cleanup_tmp(path)
      FileUtils.rm_f(path)
    end

    def build_result(full_url)
      {
        url:      full_url,
        markdown: "![#{@title}](#{full_url})",
        html:     "<img src='#{full_url}' alt='#{@title}' />",
        org:      "[[img:#{full_url}][#{@title}]]"
      }
    end
  end
end
