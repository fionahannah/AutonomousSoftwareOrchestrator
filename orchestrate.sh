#!/bin/bash
set -euo pipefail

# Required env vars:
# - ADO_PAT
# - ADO_ORG
# - ADO_PROJECT
# - ADO_REPO
# - ASO_PAT
# Optional:
# - GITHUB_ORG (fallback if not present in manifest)

MANIFEST_PATH="/manifest.json"
ENCODED_PATH=$(jq -rn --arg p "$MANIFEST_PATH" '$p|@uri')
MANIFEST_URL="https://dev.azure.com/${ADO_ORG}/${ADO_PROJECT}/_apis/git/repositories/${ADO_REPO}/items?path=${ENCODED_PATH}&api-version=7.0&\$format=octetStream"

echo "🌐 Fetching manifest..."
MANIFEST=$(curl -sS -u ":${ADO_PAT}" "$MANIFEST_URL")

if [ -z "$MANIFEST" ]; then
  echo "❌ Failed to fetch manifest content"
  exit 1
fi

echo "✅ Manifest retrieved. Processing repos…"

# Loop through repos
REPO_COUNT=$(echo "$MANIFEST" | jq '.repos | length')
echo "🔍 Found $REPO_COUNT repos"

for row in $(echo "$MANIFEST" | jq -r '.repos[] | @base64'); do
  _jq() {
    echo "${row}" | base64 --decode | jq -r "${1}"
  }

  name=$(_jq '.name')
  github_path=$(_jq '.github')

  if [[ "$github_path" == "null" || -z "$github_path" ]]; then
    if [[ -z "${GITHUB_ORG:-}" ]]; then
      echo "⚠️ No GitHub repo path or GITHUB_ORG provided. Skipping $name"
      continue
    fi
    github_path="$GITHUB_ORG/$name"
  fi

  echo "🔧 Checking GitHub repo: $github_path"

  repo_check=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $ASO_PAT" \
    "https://api.github.com/repos/$github_path")

  if [[ "$repo_check" == "200" ]]; then
    echo "✅ Repo already exists: $github_path"
  else
    echo "🚀 Creating repo: $github_path"
    repo=$(cut -d/ -f2 <<< "$github_path")
    # org=$(cut -d/ -f1 <<< "$github_path")

json_payload=$(jq -n \
  --arg name "$repo" \
  --arg description "Created by Autonomous Software Orchestrator" \
  '{name: $name, private: true, description: $description}')


create_response=$(curl -sS -X POST -H "Authorization: Bearer $ASO_PAT" \
-H "Accept: application/vnd.github+json" https://api.github.com/user/repos \
-d "$json_payload")


    echo "🔬 Raw response from GitHub:"
    echo "$create_response"

    repo_name=$(echo "$create_response" | jq -r '.full_name // "unknown"')
    echo "📦 Created: $repo_name"
  fi
done

echo "🎉 Orchestration complete."
