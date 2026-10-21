#!/usr/bin/env bash
# Builds the front end and publishes it to the stack's bucket and distribution.
# usage: scripts/deploy.sh <stage>        (run from the repository root; stage: dev or prod)
#   the build reads .env.<stage> (vite build --mode <stage>): put each stage's VITE_* values there
#   INVALIDATION_PATHS="/index.html /"    paths to invalidate instead of the default "/*"
#   AWS_REGION                            region of the stack (default us-east-1)
set -euo pipefail
export AWS_PAGER="" # never wait on a pager in CI

stage="${1:?usage: scripts/deploy.sh <stage>}"
stack="devskills-test-$stage"
region="${AWS_REGION:-us-east-1}"
build_dir=dist
hashed_dir=assets # Vite's folder of content-hashed files
step=start
trap 'echo "deploy: FAILED at step: $step (exit $?)" >&2' ERR

# Checked before anything is built or uploaded: the CLI would refuse a bad path only at the end.
# Paths are separated by spaces; a space inside a path is written %20.
read -r -a paths <<< "${INVALIDATION_PATHS:-/*}" # read -a never expands /* into local folders
if [[ "${INVALIDATION_PATHS:-}" == *$'\n'* ]] || [ "${#paths[@]}" -eq 0 ]; then
  echo "deploy: INVALIDATION_PATHS is blank or spans lines; list paths on one line, or unset it for /*" >&2
  exit 1
fi
for path in "${paths[@]}"; do
  if [[ "$path" != /* ]] || [[ "$path" == *"~"* ]]; then
    echo "deploy: invalidation path '$path' refused: each path starts with / (a space inside one is %20); ~ is not supported" >&2
    exit 1
  fi
done

output() {
  local value
  if ! value=$(aws cloudformation describe-stacks --stack-name "$stack" --region "$region" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text); then
    echo "deploy: cannot read stack $stack in $region (does it exist?)" >&2
    return 1
  fi
  if [ -z "$value" ] || [ "$value" = "None" ]; then
    echo "deploy: stack $stack has no output $1" >&2
    return 1
  fi
  echo "$value"
}

step="read the stack's outputs"
BUCKET=$(output BucketName)
DISTRIBUTION_ID=$(output DistributionId)

step="build"
pnpm build --mode "$stage"
# Refuse a build without its entry page or its hashed files: step 2 would delete the live site's files.
if [ ! -f "$build_dir/index.html" ] || [ ! -d "$build_dir/$hashed_dir" ]; then
  echo "deploy: $build_dir/index.html or $build_dir/$hashed_dir/ missing, nothing published" >&2
  exit 1
fi

# 1. Hashed files first, so the new index.html never points at a file that is not there yet.
#    A new content gets a new name, so each name can be cached for a year and never revalidated.
#    No --delete: a tab still running the previous build loads its chunks from here.
step="upload hashed files"
aws s3 sync "$build_dir/$hashed_dir" "s3://$BUCKET/$hashed_dir" --region "$region" \
  --cache-control "public,max-age=31536000,immutable" --no-progress

# 2. The other fixed-name files (favicon, robots.txt): revalidated on every use.
#    --delete removes those that left the build, and any other root object not in it;
#    excluded keys are never deleted.
step="upload fixed-name files"
aws s3 sync "$build_dir" "s3://$BUCKET" --region "$region" \
  --exclude "$hashed_dir/*" --exclude "index.html" \
  --cache-control "no-cache" --delete --no-progress

# 3. index.html last, always uploaded (cp does not compare sizes or dates as sync does).
step="upload index.html"
aws s3 cp "$build_dir/index.html" "s3://$BUCKET/index.html" --region "$region" \
  --cache-control "no-cache" --content-type "text/html; charset=utf-8" --no-progress

# 4. Drop the copies the edge locations hold of the fixed-name files, and wait until they are gone.
step="invalidate"
invalidation_id=$(aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths "${paths[@]}" --query Invalidation.Id --output text)
echo "deploy: invalidation $invalidation_id of ${paths[*]} created on $DISTRIBUTION_ID"

step="wait for the invalidation"
# Polls every 20 seconds and gives up after 30 checks (exit 255): the files are published by then.
aws cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$invalidation_id"
echo "deploy: $stack published"
