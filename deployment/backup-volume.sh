docker run --rm \
  -v ghost_content:/volume \
  -v $(pwd):/backup \
  alpine tar cvf /backup/ghost_content_backup.tar /volume
