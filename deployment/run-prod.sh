#!/bin/bash

# This needs a docker volume to exist for the content

# Check if the volume exists
if ! docker volume inspect ghost_content > /dev/null 2>&1; then
  echo "Volume 'ghost_content' does not exist. Please create it first."
  exit 1
fi

docker run -d \
  -e url=http://chaijiaxun.com \
  -e NODE_ENV=production \
  -v ghost_content:/var/lib/ghost/content \
  -p 3711:3711 \
  --name ghost-blog-prod \
  ghost:latest
