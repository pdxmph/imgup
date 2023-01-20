# Dockerfile

FROM ruby:3.1.3

WORKDIR /imgup_smugmug
COPY . /imgup_smugmug
RUN bundle install

EXPOSE 4567

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "-p", "4567"]