# lib/imgup-cli/setup.rb
require 'oauth'
require 'launchy'
require_relative 'config'
require 'uri'
require 'cgi'

module ImgupCli
  class Setup
    REQUEST_TOKEN_URL = 'https://api.smugmug.com/services/oauth/1.0a/getRequestToken'
    AUTHORIZE_URL     = 'https://api.smugmug.com/services/oauth/1.0a/authorize'
    ACCESS_TOKEN_URL  = 'https://api.smugmug.com/services/oauth/1.0a/getAccessToken'

    def self.run(consumer_key:, consumer_secret:)
      consumer = OAuth::Consumer.new(
        consumer_key,
        consumer_secret,
        request_token_url: REQUEST_TOKEN_URL,
        authorize_url:     AUTHORIZE_URL,
        access_token_url:  ACCESS_TOKEN_URL
      )

      # 1) Get a request token in PIN (oob) mode
      request_token = consumer.get_request_token(oauth_callback: 'oob')

      # 2) Open authorize page
      auth_url = "#{AUTHORIZE_URL}?oauth_token=#{request_token.token}&Access=Full&Permissions=Modify"
      puts "\nPlease open this URL and authorize the app:\n\n  #{auth_url}\n\n"
      Launchy.open(auth_url)

      # 3) Browser will redirect to localhost/fail; copy the full URL
      puts "After you click ‘Authorize’, your browser will try to redirect to localhost and fail."
      print "Paste the *entire* redirect URL here: "
      redirect_url = STDIN.gets.strip

      # 4) Extract the oauth_verifier
      uri    = URI.parse(redirect_url)
      params = CGI.parse(uri.query || "")
      verifier = params['oauth_verifier']&.first
      unless verifier
        $stderr.puts "❌  Couldn't find oauth_verifier in the URL."
        exit 1
      end
      puts "→ Got verifier: #{verifier}"

      # 5) Exchange for an access token
      access_token = request_token.get_access_token(oauth_verifier: verifier)

      # 6) Save into config.yml
      cfg = ImgupCli::Config.load
      cfg.merge!(
        'consumer_key'        => consumer_key,
        'consumer_secret'     => consumer_secret,
        'access_token'        => access_token.token,
        'access_token_secret' => access_token.secret
      )
      ImgupCli::Config.save(cfg)

      puts "\n✅  OAuth setup complete!  Credentials saved to:\n    #{ImgupCli::Config::FILE}\n\n"
    rescue OAuth::Unauthorized => e
      $stderr.puts "Authorization failed: #{e.message}"
      exit 1
    end
  end
end
