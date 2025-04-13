FROM ruby:3.2-slim

# Install dependencies
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs

# Set working directory
WORKDIR /app

# Copy Gemfiles and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy rest of app
COPY . .

# Expose Sinatra default port
EXPOSE 4568

# Run the app
CMD ["ruby", "imgup.rb"]
