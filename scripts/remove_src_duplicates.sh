#!/bin/bash

# Define the files to check for duplicates
files=(
    "/etc/apt/sources.list.d/azure-cli.list"
    "/etc/apt/sources.list.d/azure-cli.sources"
)

# Function to remove duplicate lines from a file
remove_duplicates() {
    local file=$1
    if [ -f "$file" ]; then
        # Remove duplicate lines and save to a temporary file
        awk '!seen[$0]++' "$file" > "${file}.tmp"
        # Replace the original file with the temporary file
        mv "${file}.tmp" "$file"
        echo "Removed duplicates from $file"
    else
        echo "File $file not found"
    fi
}

# Iterate over the files and remove duplicates
for file in "${files[@]}"; do
    remove_duplicates "$file"
    echo "removing duplicates from $file"
done

# Update the package list
sudo apt-get update