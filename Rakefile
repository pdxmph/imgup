# load up our env files for local testing

require 'dotenv'
Dotenv.load('.env', '.env_oauth')

task default: %w[run]

task :run do
  `rackup -D -P .pid -p 4567`
  `open http://localhost:4567`
end

task :kill do 
  `pkill -F .pid`
end