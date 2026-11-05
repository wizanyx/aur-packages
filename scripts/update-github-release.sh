#!/usr/bin/env bash
# Bump a single-source package's PKGBUILD to the latest GitHub release of its upstream.
# Usage: scripts/update-github-release.sh <pkgdir> <owner/repo> <asset-name-template>
#   The asset template may contain {version}, e.g. "foo_{version}_amd64.deb".
set -euo pipefail

pkgdir=$1
repo=$2
asset_template=$3

cd "$pkgdir"

# Report results to GitHub Actions when running there
output() {
	if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
		echo "$1" >> "$GITHUB_OUTPUT"
	fi
}

auth=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
	auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

current=$(sed -n 's/^pkgver=//p' PKGBUILD)
release_json=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/${repo}/releases/latest")

read -r latest asset_url sha < <(ASSET_TEMPLATE="$asset_template" python3 -I -c '
import json, os, sys
r = json.load(sys.stdin)
ver = r["tag_name"].lstrip("v")
name = os.environ["ASSET_TEMPLATE"].replace("{version}", ver)
asset = next((a for a in r["assets"] if a["name"] == name), None)
if asset is None:
    sys.exit(f"asset {name} not found in release {r['"'"'tag_name'"'"']}")
print(ver, asset["browser_download_url"], (asset.get("digest") or "").removeprefix("sha256:"))
' <<<"$release_json")

output "version=${latest}"

if [[ "$latest" == "$current" ]]; then
	echo "Already up to date ($current)"
	output "updated=false"
	exit 0
fi

echo "Updating $current -> $latest"

if [[ -z "$sha" ]]; then
	# No digest from GitHub; hash the download ourselves
	sha=$(curl -fsSL "$asset_url" | sha256sum | cut -d' ' -f1)
fi

sed -i \
	-e "s/^pkgver=.*/pkgver=${latest}/" \
	-e "s/^pkgrel=.*/pkgrel=1/" \
	-e "s/^sha256sums=.*/sha256sums=('${sha}')/" \
	PKGBUILD

# Locally, verify the source and refresh .SRCINFO (CI does this in the AUR deploy step)
if command -v makepkg >/dev/null; then
	makepkg --verifysource -f >/dev/null
	makepkg --printsrcinfo > .SRCINFO
fi

output "updated=true"
