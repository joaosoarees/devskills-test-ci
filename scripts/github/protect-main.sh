#!/usr/bin/env bash
# Creates or updates the ruleset "protect-main" from ruleset-main.json, then prints
# the rules the default branch now has.
# usage: scripts/github/protect-main.sh <owner/repo>      (needs gh, signed in as a repository admin)
set -euo pipefail
repo="${1:?usage: protect-main.sh <owner/repo>}"
body="$(dirname "$0")/ruleset-main.json"
name=protect-main # the "name" in ruleset-main.json

id=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
if [ -n "$id" ]; then
  gh api --method PUT "repos/$repo/rulesets/$id" --input "$body" --jq '"updated ruleset \(.id)"'
else
  gh api --method POST "repos/$repo/rulesets" --input "$body" --jq '"created ruleset \(.id)"'
fi

branch=$(gh api "repos/$repo" --jq .default_branch)
echo "rules on $branch:"
gh api "repos/$repo/rules/branches/$branch" --jq '.[].type'
