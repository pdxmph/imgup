# imgup-cli.gemspec
require_relative "lib/imgup-cli/version"

Gem::Specification.new do |spec|
  spec.name          = "imgup-cli"
  spec.version       = ImgupCli::VERSION
  spec.authors       = ["Mike Hall"]
  spec.email         = ["mike@puddingtime.org"]
  spec.summary       = "Command-line tool for uploading images to SmugMug"
  spec.description   = "CLI component extracted from imgup Sinatra app"
  spec.homepage      = "https://github.com/pdxmph/imgup-cli"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*.rb"] + ["bin/imgup", "README.md", "imgup-cli.gemspec"]
  spec.executables   = ["imgup"]
  spec.require_paths = ["lib"]

  spec.add_dependency "dotenv",    "~> 2.7"
  spec.add_dependency "oauth",     "~> 0.5"
  spec.add_dependency "multipart-post", "~> 2.1"

  spec.add_development_dependency "rspec",   "~> 3.10"
  spec.add_development_dependency "webmock", "~> 3.15"
end
