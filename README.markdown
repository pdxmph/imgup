# Up and running

## Setup

1. Visit your[Smugmug app developer page][sm_app_dev] and apply for an API key.
1. Check out the repo. 
2. cd `imgup`
3. Install your gems
  - Using rbenv, etc? `bundle install`
  - Just using your system ruby? `sudo bundle install`
4. `cp dot_env .env`
5. Edit `.env`
  - your API key goes on this line, ex: `SMUGMUG_TOKEN=1234567890ABCDEFGHIJK"
  - your API secret goes on this line, ex: `SMUGMUG_SECRET=9876543210abcdefGHIJKLMNO`
  - the album you want to target for uploads goes on this line, ex: `SMUGMUG_UPLOAD_ALBUM_ID=123ABCD`
    - Get this by making an album or visiting the one you want to use and pulling the trailing id off the album URL under "Gallery Settings"
4. `ruby imgup.rb`
5. Visit <https://localhost:4567/>
6. Step through authentication with Smugmug
7. Start uploading. Unless you do the optional steps below, you'll have to sign in with Smugmug every time you restart the app. 

## Optional: Save your oAuth tokens for reuse

1. Visit <https://localhost:4567/tokens> to get your oAuth access token information. 
2. Edit `.env`
  - Your access token goes on this line, ex: `SMUGMUG_ACCESS_TOKEN=xyztuvabcDFGH98765`
  - Your access token secret goes on this line, ex: `SMUGMUG_ACCESS_TOKEN_SECRET=12345ABCDElkjhqwer890`
3. Edit `imgup.rb`. 

Look for these lines:

```ruby
# comment out this line if you don't have your access token
#  session[:oauth][:access_token] = sm_access_token
# comment out this line if you don't have your access token
# session[:oauth][:access_token_secret] = sm_access_token_secret
```

... and uncomment the two `session[:oauth]` lines: 

```ruby
# comment out this line if you don't have your access token
session[:oauth][:access_token] = sm_access_token
# comment out this line if you don't have your access token
session[:oauth][:access_token_secret] = sm_access_token_secret
```
You can restart the app (`ruby imgup.rb`) and your oAuth authentication should persist between restarts. 


# Idea

1. Provide a way to quickly upload images to Smugmug and get back copy/pastable Markdown or HTML for sharing in a blog post, etc. (Done)
2. Provide a way to review recent uploads and get copy/pastable Markdown or HTML for sharing in a blog post, etc. (In progress)
3. Provide a way to change filenames for uploads to reflect camera and lens metadata. (Someday)

## Personal goals

- Learn how OAUTH works in Ruby. (Done, with caveats)

# Docs

- [Smugmug API](https://www.smugmughelp.com/en/articles/472-smugmug-api)

# TODO

- slugify all the uploads
- make uploads transient in memory instead of saving them


[sm_app_dev]: https://api.smugmug.com/api/developer