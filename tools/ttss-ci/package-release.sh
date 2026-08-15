#!/usr/bin/env bash
set -euo pipefail

required=(XMCL_REPO FCL_REPO SEED_DIR EXPORT_ROOT OUTPUT_DIR POLICY_FILE)
for name in "${required[@]}"; do
  [[ -n ${!name:-} ]] || { printf 'missing required environment variable: %s\n' "$name" >&2; exit 64; }
done
xmcl_dir="$XMCL_REPO/xmcl-electron-app/build/output/linux-unpacked"
xmcl_asar="$xmcl_dir/resources/app.asar"
fcl_apk=$(find "$FCL_REPO/FCL/build/outputs/apk/release" -maxdepth 1 -type f -name '*-all.apk' -print -quit)
for path in "$xmcl_asar" "$fcl_apk" "$SEED_DIR/ttss-client-seed.zip" "$EXPORT_ROOT/host/automodpack-content.json" "$EXPORT_ROOT/config/hailwall.json" "$POLICY_FILE"; do
  [[ -f $path ]] || { printf 'required release input is missing: %s\n' "$path" >&2; exit 66; }
done
for command in jq sha256sum tar gzip zipinfo git stat; do
  command -v "$command" >/dev/null || { printf 'required command is missing: %s\n' "$command" >&2; exit 69; }
done

xmcl_version=$(jq -er '.version | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$XMCL_REPO/xmcl-electron-app/package.json")
fcl_version=$(sed -n 's/^[[:space:]]*versionName = "\([^"]*\)"/\1/p' "$FCL_REPO/FCL/build.gradle.kts" | head -n 1)
fcl_code=$(sed -n 's/^[[:space:]]*versionCode = \([0-9][0-9]*\)/\1/p' "$FCL_REPO/FCL/build.gradle.kts" | head -n 1)
[[ $fcl_version =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && $fcl_code =~ ^[0-9]+$ ]] || { printf '%s\n' 'FCL version metadata is invalid' >&2; exit 65; }

seed_release=$(jq -er '.releaseId' "$SEED_DIR/ttss-client-seed.manifest.json")
seed_digest=$(jq -er '.contentDigest | select(test("^[0-9a-f]{64}$"))' "$SEED_DIR/ttss-client-seed.manifest.json")
xmcl_head=$(git -C "$XMCL_REPO" rev-parse HEAD)
fcl_head=$(git -C "$FCL_REPO" rev-parse HEAD)
xmcl_tree=$(cd "$XMCL_REPO" && git ls-files -co --exclude-standard -z | sort -z | while IFS= read -r -d '' path; do [[ -f $path ]] && sha256sum "$path"; done | sha256sum | cut -d' ' -f1)
fcl_tree=$(cd "$FCL_REPO" && git ls-files -co --exclude-standard -z | sort -z | while IFS= read -r -d '' path; do [[ -f $path ]] && sha256sum "$path"; done | sha256sum | cut -d' ' -f1)
host_digest=$(sha256sum "$EXPORT_ROOT/host/automodpack-content.json" | cut -d' ' -f1)
hailwall_digest=$(sha256sum "$EXPORT_ROOT/config/hailwall.json" | cut -d' ' -f1)
policy_digest=$(sha256sum "$POLICY_FILE" | cut -d' ' -f1)
release_fingerprint=$(printf '%s\n' "$seed_digest" "$xmcl_head" "$xmcl_tree" "$fcl_head" "$fcl_tree" "$host_digest" "$hailwall_digest" "$policy_digest" | sha256sum | cut -d' ' -f1)
release_id="ttss-launcher-${release_fingerprint:0:20}"
published_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

staging="$OUTPUT_DIR.staging"
rm -rf "$staging"
mkdir -p "$staging/xmcl" "$staging/fcl" "$staging/seed"
install -m 0644 "$xmcl_asar" "$staging/xmcl/app-$xmcl_version-linux.asar"
gzip -9n -c "$xmcl_asar" > "$staging/xmcl/app-$xmcl_version-linux.asar.gz"
sha256sum "$xmcl_asar" | cut -d' ' -f1 > "$staging/xmcl/app-$xmcl_version-linux.asar.sha256"
tar --sort=name --mtime='@315532800' --owner=0 --group=0 --numeric-owner -C "$xmcl_dir" -cf - . | gzip -1n > "$staging/xmcl/ttss-xmcl-$xmcl_version-linux-x64.tar.gz"

apk_name="FCL-release-$fcl_version-all.apk"
install -m 0644 "$fcl_apk" "$staging/fcl/$apk_name"
for arch in armeabi-v7a arm64-v8a x86 x86_64; do
  ln "$staging/fcl/$apk_name" "$staging/fcl/FCL-release-$fcl_version-$arch.apk"
done
for name in ttss-client-seed.manifest.json ttss-client-seed.manifest.sig ttss-client-seed.public.pem; do
  install -m 0644 "$SEED_DIR/$name" "$staging/seed/$name"
done
(cd "$staging/seed" && sha256sum ttss-client-seed.manifest.json ttss-client-seed.manifest.sig ttss-client-seed.public.pem > SHA256SUMS)

jq -n --arg version "$xmcl_version" --arg published "$published_at" '{tag_name: ("v" + $version), body: "清汤闲水服务器受管启动器正式版", published_at: $published, assets: [{name: ("app-" + $version + "-linux.asar"), browser_download_url: ("https://launcher.ttss4096.com/releases/latest/xmcl/app-" + $version + "-linux.asar")}]}' > "$staging/xmcl/release.json"
jq -n --argjson code "$fcl_code" --arg version "$fcl_version" --arg date "$(date -u +'%Y.%m.%d')" '[{type: "release", versionCode: $code, versionName: $version, date: $date, description: [{lang: "zh_CN", text: "清汤闲水服务器受管启动器正式版"}, {lang: "en", text: "TTSS managed launcher release"}], url: ("https://launcher.ttss4096.com/releases/latest/fcl/FCL-release-" + $version + "-all.apk"), netdiskUrl: "https://launcher.ttss4096.com/"}]' > "$staging/fcl/version_map.json"

jq -n --arg releaseId "$release_id" --arg publishedAt "$published_at" --arg seedReleaseId "$seed_release" --arg seedDigest "$seed_digest" --arg seedPayloadSha256 "$(jq -r '.payload.sha256' "$SEED_DIR/ttss-client-seed.manifest.json")" --arg seedPayloadSource "xmcl/ttss-xmcl-$xmcl_version-linux-x64.tar.gz#./resources/ttss-client-seed/ttss-client-seed.zip" --arg xmclVersion "$xmcl_version" --arg xmclHead "$xmcl_head" --arg xmclTree "$xmcl_tree" --arg fclVersion "$fcl_version" --argjson fclVersionCode "$fcl_code" --arg fclHead "$fcl_head" --arg fclTree "$fcl_tree" --arg hostManifestSha256 "$host_digest" --arg hailwallSha256 "$hailwall_digest" --arg policySha256 "$policy_digest" '{schemaVersion: 1, releaseId: $releaseId, publishedAt: $publishedAt, seed: {releaseId: $seedReleaseId, contentDigest: $seedDigest, payloadSha256: $seedPayloadSha256, payloadSource: $seedPayloadSource}, xmcl: {version: $xmclVersion, gitHead: $xmclHead, sourceTreeSha256: $xmclTree}, fcl: {version: $fclVersion, versionCode: $fclVersionCode, gitHead: $fclHead, sourceTreeSha256: $fclTree}, inputs: {hostManifestSha256: $hostManifestSha256, hailwallSha256: $hailwallSha256, policySha256: $policySha256}}' > "$staging/release-manifest.json"

files_tsv=$(mktemp)
sha_sums=$(mktemp)
trap 'rm -f "$files_tsv" "$sha_sums"' EXIT
find "$staging" -type f ! -name 'SHA256SUMS' ! -name 'sbom.spdx.json' -printf '%P\n' | sort | while IFS= read -r relative; do
  printf '%s\t%s\t%s\n' "$relative" "$(stat -c %s "$staging/$relative")" "$(sha256sum "$staging/$relative" | cut -d' ' -f1)"
done > "$files_tsv"
jq -Rn --arg created "$published_at" --arg namespace "https://launcher.ttss4096.com/releases/$release_id/sbom" '{spdxVersion: "SPDX-2.3", dataLicense: "CC0-1.0", SPDXID: "SPDXRef-DOCUMENT", name: "TTSS managed launcher release", documentNamespace: $namespace, creationInfo: {created: $created, creators: ["Organization: TTSS"]}, files: [inputs | split("\t") | {fileName: .[0], SPDXID: ("SPDXRef-File-" + (input_line_number | tostring)), checksums: [{algorithm: "SHA256", checksumValue: .[2]}]}]}' < "$files_tsv" > "$staging/sbom.spdx.json"
(cd "$staging" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | while IFS= read -r relative; do sha256sum "$relative"; done) > "$sha_sums"
install -m 0644 "$sha_sums" "$staging/SHA256SUMS"
rm -rf "$OUTPUT_DIR"
mv "$staging" "$OUTPUT_DIR"
printf 'release_packaging=PASS release_id=%s xmcl=%s fcl=%s seed=%s bytes=%s\n' "$release_id" "$xmcl_version" "$fcl_version" "$seed_release" "$(du -sb "$OUTPUT_DIR" | cut -f1)"
