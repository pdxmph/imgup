## Getting Started (Command-Line)

These steps will get you up & running with the `imgup` CLI in under a minute.

### 1. Install

```bash
# Clone the repo (if you haven’t already)
git clone https://github.com/pdxmph/imgup.git
cd imgup

# Install dependencies
bundle install
```

> If you prefer system Ruby, you may need `sudo bundle install`.
> If you use rbenv/rvm, just `bundle install` in your project directory.

### 2. Configure Your Credentials

Copy the example and fill in your SmugMug keys:

```bash
cp .env.example ~/.imgup.env
```

Open `~/.imgup.env` in your editor and set:

```env
SMUGMUG_TOKEN=your_consumer_key_here
SMUGMUG_SECRET=your_consumer_secret_here
SMUGMUG_ACCESS_TOKEN=your_access_token_here
SMUGMUG_ACCESS_TOKEN_SECRET=your_access_token_secret_here
SMUGMUG_UPLOAD_ALBUM_ID=your_album_id_here
SMUGMUG_UPLOAD_URL=https://upload.smugmug.com/
SMUGMUG_API_URL=https://api.smugmug.com
```

> If you need a `.env.example`, create one in the repo root with these keys commented out.

### 3. (Optional) Per-Project Overrides

If you ever want a different set of credentials for a given project, simply drop a `.env` file beside `bin/imgup`:

```bash
cp .env.example .env
# edit .env with alternate keys
```

The CLI will load `.env` first, then `~/.imgup.env`.

### 4. Usage

```bash
# Basic upload:
imgup path/to/photo.jpg

# With a custom title & caption:
imgup \
  --title="Sunset over the lake" \
  --caption="Taken with my vintage Canon" \
  ~/Pictures/sunset.jpg

# Example output:
![sunset over the lake](https://photos.smugmug.com/photos/i-XXXXX/0/…/XL/i-XXXXX-XL.jpg)
```

And you’re done—`imgup` will pick up your `~/.imgup.env` automatically and produce a Markdown snippet you can pipe, copy, or append however you like.
