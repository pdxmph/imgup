# lib/imgup-cli/config.rb
require 'yaml'
require 'fileutils'

module ImgupCli
  class Config
    # XDG or fallback to ~/.config
    DIR  = ENV['XDG_CONFIG_HOME'] || File.join(Dir.home, '.config')
    FILE = File.join(DIR, 'imgup-cli', 'config.yml')

    def self.load
      return {} unless File.exist?(FILE)
      YAML.load_file(FILE) || {}
    end

    def self.save(hash)
      FileUtils.mkdir_p(File.dirname(FILE))
      File.write(FILE, YAML.dump(hash))
    end
  end
end
