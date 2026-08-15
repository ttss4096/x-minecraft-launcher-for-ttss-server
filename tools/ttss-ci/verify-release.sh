#!/usr/bin/env bash
set -euo pipefail

release=${1:-}
[[ -n $release && -d $release ]] || { printf 'usage: %s RELEASE_DIR\n' "$0" >&2; exit 64; }
release=$(cd "$release" && pwd)
for command in jq sha256sum openssl unzip gzip tar stat diff; do
  command -v "$command" >/dev/null || { printf 'required command is missing: %s\n' "$command" >&2; exit 69; }
done
(cd "$release" && sha256sum -c SHA256SUMS >/dev/null)
jq -e '.schemaVersion == 1 and (.releaseId | test("^ttss-launcher-[0-9a-f]{20}$")) and (.seed.contentDigest | test("^[0-9a-f]{64}$")) and (.seed.payloadSha256 | test("^[0-9a-f]{64}$")) and (.seed.payloadSource | test("^xmcl/ttss-xmcl-[0-9.]+-windows-x64\\.zip#resources/ttss-client-seed/ttss-client-seed\\.zip$")) and (.inputs.hostManifestSha256 | test("^[0-9a-f]{64}$")) and (.inputs.hailwallSha256 | test("^[0-9a-f]{64}$")) and (.inputs.policySha256 | test("^[0-9a-f]{64}$"))' "$release/release-manifest.json" >/dev/null
jq -e 'length == 1 and .[0].type == "release" and (.[] | .url | startswith("https://launcher.ttss4096.com/releases/latest/fcl/")) and (.[] | .netdiskUrl == "https://launcher.ttss4096.com/")' "$release/fcl/version_map.json" >/dev/null
jq -e '.assets | length == 1 and all(.[]; (.browser_download_url | startswith("https://launcher.ttss4096.com/releases/latest/xmcl/")))' "$release/xmcl/release.json" >/dev/null
xmcl_version=$(jq -r '.xmcl.version' "$release/release-manifest.json")
fcl_version=$(jq -r '.fcl.version' "$release/release-manifest.json")
asar="$release/xmcl/app-$xmcl_version-win32.asar"
expected_asar=$(tr -d '\r\n' < "$asar.sha256")
[[ $expected_asar =~ ^[0-9a-f]{64}$ && $(sha256sum "$asar" | cut -d' ' -f1) == "$expected_asar" ]] || { printf '%s\n' 'XMCL asar checksum failed' >&2; exit 65; }
gzip -t "$asar.gz"
cmp <(gzip -dc "$asar.gz") "$asar"
archive="$release/xmcl/ttss-xmcl-$xmcl_version-windows-x64.zip"
unzip -tq "$archive" >/dev/null
if unzip -Z1 "$archive" | awk '/^\// || /(^|\/)\.\.($|\/)/ { bad=1 } END { exit bad ? 0 : 1 }'; then
  printf '%s\n' 'XMCL archive contains an unsafe path' >&2
  exit 65
fi

apk="$release/fcl/FCL-release-$fcl_version-all.apk"
unzip -tq "$apk" >/dev/null
apk_inode=$(stat -c %i "$apk")
for arch in armeabi-v7a arm64-v8a x86 x86_64; do
  alias="$release/fcl/FCL-release-$fcl_version-$arch.apk"
  [[ -f $alias && $(stat -c %i "$alias") == "$apk_inode" ]] || { printf 'FCL architecture alias failed: %s\n' "$arch" >&2; exit 65; }
done

seed="$release/seed"
(cd "$seed" && sha256sum -c SHA256SUMS >/dev/null)
openssl dgst -sha256 -verify "$seed/ttss-client-seed.public.pem" -signature "$seed/ttss-client-seed.manifest.sig" "$seed/ttss-client-seed.manifest.json" >/dev/null
[[ $(jq -r '.seed.releaseId' "$release/release-manifest.json") == "$(jq -r '.releaseId' "$seed/ttss-client-seed.manifest.json")" ]] || { printf '%s\n' 'seed release mismatch' >&2; exit 65; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -p "$archive" 'resources/ttss-client-seed/ttss-client-seed.zip' > "$work/ttss-client-seed.zip"
for name in ttss-client-seed.manifest.json ttss-client-seed.manifest.sig ttss-client-seed.public.pem; do
  unzip -p "$archive" "resources/ttss-client-seed/$name" | cmp - "$seed/$name"
done
[[ $(sha256sum "$work/ttss-client-seed.zip" | cut -d' ' -f1) == "$(jq -r '.seed.payloadSha256' "$release/release-manifest.json")" ]] || { printf '%s\n' 'embedded seed payload checksum failed' >&2; exit 65; }
unzip -tq "$work/ttss-client-seed.zip" >/dev/null
if unzip -Z1 "$work/ttss-client-seed.zip" | grep -Ei '(^|/)worldedit[^/]*\.jar$'; then
  printf '%s\n' 'server-only WorldEdit was found in release seed' >&2
  exit 65
fi
if find "$release/xmcl" -maxdepth 1 -type f | grep -Ei 'linux|ia32|appx'; then
  printf '%s\n' 'unexpected non-Windows-x64 XMCL artifact found' >&2
  exit 65
fi

printf 'release_verification=PASS release_id=%s files=%s bytes=%s\n' "$(jq -r '.releaseId' "$release/release-manifest.json")" "$(find "$release" -type f | wc -l)" "$(du -sb "$release" | cut -f1)"
