# Blog Deployment Scripts and Theme

## Deployment

I could have used docker-compose but I was lazy to learn a new tool.

I'm finally using docker to manage my blog, so there are now some scripts to help with that.

The docker instance ghost_blog_prod is the one that is running the blog. It uses a docker volume called ghost_content to store the blog content. It runs on port 3711.

### Scripts

- `backup-volume.sh` - Backup the ghost_content volume
- `restore-volume.sh` - Restore the ghost_content volume
- `run-prod.sh` - Run the ghost blog in production mode

## Theme

Structure of the theme is based off the [ghostium](https://github.com/oswaldoacauan/ghostium) theme.

### Features

- [Twenty Twenty](https://zurb.com/playground/twentytwenty) for displaying comparison images

## Branches

### Main

> Ported to ghost v3

Custom blog theme created for Jia Xun's personal blog

## Maptian Design

> Not yet ported to ghost v2

Custom blog theme created for Jia Jin's personal blog (not used anymore)

## Copyright & License

Copyright (c) 2024 Pixel Rife - Released under the [MIT license](LICENSE).
