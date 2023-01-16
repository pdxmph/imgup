# Idea

Make a little Sinatra environment where you can upload images to the Cloudflare image service and get back snippets for sharing, etc. 

Why: Mostly because weblog.lol doesn't have image uploads yet and this seemed like a fun way to make quick image links in the absence of that functionality. 

Longer-term: I don't like the way any services handle image sharing at the top so I'd like to make a one-stop "get things into Smugmug and make an Atom feed" tool. 

## Personal goals

Do OAUTH correctly. 

# Docs

- [Smugmug API](https://www.smugmughelp.com/en/articles/472-smugmug-api)

# TODO

- Get the Smugmug part done. Right now this only puts things in Cloudflare
- More secure config
- slugify all the uploads
- make uploads transient in memory instead of saving them


