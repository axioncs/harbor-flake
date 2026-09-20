#!/usr/bin/env bash
# Updates version.json for both Harbor Linux channels.
#
#   beta   -> newest release whose tag starts with "beta-v" (a GitHub
#             pre-release, so /releases/latest never returns it)
#   stable -> /releases/latest
#
# Source repo: harborstremio-linux/harbor-linux-builds (Harbor's main repo
# ships no Linux binaries).
#
# Notes learned from inspecting the real assets:
#   * The stable tag "v0.9.21" ships a .deb that self-reports version 0.9.87,
#     so the tag and the package version are NOT the same number. We key
#     change-detection on the download URL, not on a parsed version.
#   * We resolve the asset URL from the release JSON instead of building it,
#     because filenames differ ("Harbor_0.9.126-1_amd64.deb" vs
#     "Harbor_0.9.21_amd64.deb").
#
# A channel with no .deb uploaded yet is skipped (transient). Both channels are
# always attempted; the script exits 1 at the end if either hard-failed
# (network/parse error), so the workflow goes red instead of committing garbage.

set -euo pipefail

REPO="harborstremio-linux/harbor-linux-builds"
FILE="version.json"
API="https://api.github.com/repos/${REPO}"

auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

gh_api() {
  curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" "$1"
}

# Prints the amd64 .deb URL of a release JSON on stdin, or nothing.
deb_url() {
  jq -r '[.assets[] | select(.name | test("_amd64\\.deb$")) | .browser_download_url] | first // empty'
}

# Prints the newest non-draft beta release JSON. Sorted on created_at so we
# don't depend on API ordering.
latest_beta_json() {
  local list
  list=$(gh_api "${API}/releases?per_page=30") || { echo "failed to list releases" >&2; return 1; }
  jq -c '[.[] | select(.tag_name | test("^beta-v")) | select(.draft | not)]
         | sort_by(.created_at) | last // empty' <<<"$list"
}

update_channel() {
  local channel="$1" release_json="$2"

  if [ -z "$release_json" ]; then
    echo "[$channel] no release found" >&2
    return 1
  fi

  local tag url current_url
  tag=$(jq -r '.tag_name' <<<"$release_json")
  url=$(deb_url <<<"$release_json")
  if [ -z "$url" ]; then
    # Usually the release exists but CI is still uploading assets. Skip this
    # channel for now rather than failing the whole run; the next scheduled
    # run picks it up.
    echo "[$channel] release $tag has no amd64 .deb yet, skipping" >&2
    return 0
  fi

  current_url=$(jq -r --arg c "$channel" '.[$c].url' "$FILE")
  if [ "$url" = "$current_url" ]; then
    echo "[$channel] already up to date ($tag)"
    return 0
  fi

  echo "[$channel] update: $current_url -> $url"

  # NOTE: this function is called on the left of `||`, and bash ignores
  # `set -e` inside such functions. Every fallible step below therefore
  # checks its own exit status; otherwise a failed download would silently
  # write a bogus hash/version into version.json.
  local tmp
  tmp=$(mktemp --suffix=.deb)
  if ! curl -fsSL -o "$tmp" "$url"; then
    echo "[$channel] failed to download $url" >&2
    rm -f "$tmp"
    return 1
  fi

  # A truncated or error-page download must never be hashed and committed.
  if [ ! -s "$tmp" ] || [ "$(stat -c %s "$tmp")" -lt 1000000 ]; then
    echo "[$channel] downloaded file is empty or implausibly small" >&2
    rm -f "$tmp"
    return 1
  fi

  # The real package version is inside the .deb's control file (the stable tag
  # v0.9.21 ships a package reporting 0.9.87). dpkg-deb exists on Ubuntu
  # runners; fall back to the tag only if it is missing.
  local version hash
  if command -v dpkg-deb >/dev/null 2>&1; then
    version=$(dpkg-deb -f "$tmp" Version) || version=""
  else
    version="${tag#beta-v}"
    version="${version#[vV]}"
  fi
  if [ -z "$version" ]; then
    echo "[$channel] could not determine package version" >&2
    rm -f "$tmp"
    return 1
  fi

  if ! hash=$(nix hash file --sri "$tmp") || [ -z "$hash" ]; then
    echo "[$channel] failed to hash download" >&2
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"

  local out
  out=$(mktemp)
  if ! jq --arg c "$channel" --arg v "$version" --arg u "$url" --arg h "$hash" \
       '.[$c] = {version: $v, url: $u, hash: $h}' "$FILE" > "$out"; then
    echo "[$channel] failed to update $FILE" >&2
    rm -f "$out"
    return 1
  fi
  mv "$out" "$FILE"
  echo "[$channel] now at $version"
}

rc=0

beta_json=$(latest_beta_json) || { echo "[beta] could not fetch release list" >&2; rc=1; beta_json=""; }
if [ -n "$beta_json" ]; then
  update_channel beta "$beta_json" || rc=1
elif [ "$rc" -eq 0 ]; then
  echo "[beta] no beta release found" >&2
fi

stable_json=$(gh_api "${API}/releases/latest") || { echo "[stable] could not fetch latest release" >&2; rc=1; stable_json=""; }
if [ -n "$stable_json" ]; then
  update_channel stable "$stable_json" || rc=1
fi

exit "$rc"
