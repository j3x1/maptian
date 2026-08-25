#!/bin/bash

# Check if volume exists
if docker volume ls | grep -q "ghost_content"; then
    echo "Warning: ghost_content volume already exists"
    read -p "Do you want to backup the existing volume before restoring? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Backup existing volume with timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        docker run --rm \
            -v ghost_content:/volume \
            -v $(pwd):/backup \
            alpine sh -c "cd /volume && tar cvf /backup/ghost_content_backup_${timestamp}.tar ."
        echo "Existing volume backed up to ghost_content_backup_${timestamp}.tar"
    fi
    
    read -p "Proceed with restore? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled"
        exit 1
    fi
fi

# If volume exists, remove it
if docker volume ls | grep -q "ghost_content"; then
    echo "Removing existing ghost_content volume"
    docker volume rm ghost_content
fi

# Create new volume
echo "Creating new ghost_content volume"
docker volume create ghost_content

# Proceed with restore
docker run --rm \
    -v ghost_content:/volume \
    -v $(pwd):/backup \
    alpine sh -c "cd /volume && tar xvf /backup/ghost_content_backup.tar --strip 1"

echo "Restore completed"
