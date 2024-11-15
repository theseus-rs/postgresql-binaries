#!/usr/bin/env bash

set -e

release="0"
all_versions=( \
  "17.1" "17.0" \
  "16.5" "16.4" "16.3" "16.2" "16.1" "16.0" \
  "15.9" "15.8" "15.7" "15.6" "15.5" "15.4" "15.3" "15.2" "15.1" "15.0" \
  "14.14" "14.13" "14.12" "14.11" "14.10" "14.9" "14.8" "14.7" "14.6" "14.5" "14.4" "14.3" "14.2" "14.1" "14.0" \
  "13.17" "13.16" "13.15" "13.14" "13.13" "13.12" "13.11" "13.10" "13.9" "13.8" "13.7" "13.6" "13.5" "13.4" "13.3" "13.2" "13.1" "13.0" \
)
release_notes="release_notes.md"

# Add the release suffix to each version
for ((i=0; i < ${#all_versions[@]}; i++)); do
  all_versions[$i]="${all_versions[$i]}.$release"
done
# Sort the versions
IFS=$'\n' versions=($(sort -n <<< "${all_versions[*]}"))

# Check if the current branch is main
if [[ $(git branch --show-current) != "main" ]]; then
  echo "You must be on the main branch to release."
  exit 1
fi

# Check if the working directory is clean
if [[ $(git status --porcelain) ]]; then
  echo "You have uncommitted changes. Please commit or stash them before releasing."
  exit 1
fi

# Check if the current branch is up to date with origin
if [[ $(git rev-parse HEAD) != $(git rev-parse origin/main) ]]; then
  echo "Your branch is not up to date with origin/main. Please pull the latest changes."
  exit 1
fi

# Verify that version does not already exist
for version in "${versions[@]}"; do
  if git tag --list | grep -q "$version"; then
    echo "Version ${version} has already been released."
    exit 1
  fi
done

if [[ ! -e "${release_notes}" ]]; then
  echo "The release notes file ${release_notes} does not exist. Please create it before continuing."
  exit 1
fi

# Verify that the user wants to release
echo "You are about to release the following versions:"
echo "${versions[@]}" | tr ' ' ',' | sed 's/,/, /g'

read -r -p "Do you want to proceed? (y/N): " userInput
userInput=${userInput:-N}
userInputUpper=$(echo "${userInput}" | tr '[:lower:]' '[:upper:]')

if [[ "$userInputUpper" != "Y" ]]; then
    exit 1
fi

for version in "${versions[@]}"; do
  echo "Creating version ${version}"
  git tag "$version" --file="${release_notes}" --cleanup=strip
  git push origin "$version"
done

echo "Done"
