#!/usr/bin/env bash
set -euo pipefail

required=(BASE_SEED EXPORT_ROOT AUTOMODPACK_JAR OUTPUT_DIR SIGNING_KEY PUBLIC_KEY)
for name in "${required[@]}"; do
  if [[ -z ${!name:-} ]]; then
    printf 'missing required environment variable: %s\n' "$name" >&2
    exit 64
  fi
done
for path in "$BASE_SEED" "$AUTOMODPACK_JAR" "$SIGNING_KEY" "$PUBLIC_KEY"; do
  [[ -f $path ]] || { printf 'required file is missing: %s\n' "$path" >&2; exit 66; }
done
[[ -d "$EXPORT_ROOT/host/main" ]] || { printf 'export host is missing\n' >&2; exit 66; }
for command in unzip rsync zip jq sha256sum openssl sha1sum stat; do
  command -v "$command" >/dev/null || { printf 'required command is missing: %s\n' "$command" >&2; exit 69; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
staging="$work/staging"
mkdir -p "$staging" "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

unzip -Z1 "$BASE_SEED" > "$work/base-paths.txt"
if awk '/^\// || /\\/ || /(^|\/)\.\.($|\/)|[\t\r\n]/ { bad=1 } END { exit bad ? 0 : 1 }' "$work/base-paths.txt"; then
  printf '%s\n' 'base seed contains an unsafe path' >&2
  exit 65
fi
unzip -q "$BASE_SEED" -d "$staging"
if find "$staging" -type l -print -quit | grep -q .; then
  printf '%s\n' 'base seed contains a symbolic link' >&2
  exit 65
fi

jq -r '.nonModpackFilesToDelete[].file | ltrimstr("/")' "$EXPORT_ROOT/host/automodpack-content.json" | while IFS= read -r relative; do
  [[ -n $relative ]] && rm -f -- "$staging/$relative"
done
rsync -a --checksum --safe-links "$EXPORT_ROOT/host/main/" "$staging/"
mkdir -p "$staging/mods"
find "$staging/mods" -maxdepth 1 -type f -iname 'automodpack*.jar' -delete
install -m 0644 "$AUTOMODPACK_JAR" "$staging/mods/automodpack-mc1.21.1-neoforge-4.0.6-ttss-managed.2.jar"

jq -n '{
  name: "清汤闲水服务器",
  author: "TTSS",
  description: "清汤闲水服务器官方受管整合包",
  version: "",
  edition: "java",
  runtime: {minecraft: "1.21.1", forge: "", fabricLoader: "", optifine: "", quiltLoader: "", neoForged: "21.1.236", labyMod: ""},
  lastAccessDate: 0,
  lastPlayedDate: 0,
  playtime: 0,
  creationDate: 0
}' > "$staging/instance.json"

for required_path in \
  mods/automodpack-mc1.21.1-neoforge-4.0.6-ttss-managed.2.jar \
  mods/hailwall_1.0.3-versionlock.1_neoforge_1.21.1.jar \
  mods/sablecollisiondamage-1.0.8.jar; do
  [[ -f $staging/$required_path ]] || { printf 'required managed client file is missing: %s\n' "$required_path" >&2; exit 65; }
done
mapfile -t exclusive_clients < <(find "$staging/mods" -maxdepth 1 -type f -name 'ttss-exclusive-client-neoforge-1.21.1-*.jar' -printf '%f\n' | sort)
if (( ${#exclusive_clients[@]} != 1 )); then
  printf 'expected exactly one managed exclusive client mod, found %s\n' "${#exclusive_clients[@]}" >&2
  exit 65
fi
if find "$staging" -type f -iname 'worldedit*.jar' -print -quit | grep -q .; then
  printf '%s\n' 'server-only WorldEdit was found in the client seed' >&2
  exit 65
fi

export LC_ALL=C
find "$staging" -type f -printf '%P\n' | sort > "$work/file-list.txt"
: > "$work/files.tsv"
while IFS= read -r relative; do
  file="$staging/$relative"
  printf '%s\t%s\t%s\n' "$relative" "$(stat -c %s "$file")" "$(sha256sum "$file" | cut -d' ' -f1)" >> "$work/files.tsv"
done < "$work/file-list.txt"
content_digest=$(sha256sum "$work/files.tsv" | cut -d' ' -f1)
release_id="ttss-${content_digest:0:16}"
find "$staging" -exec touch -h -d '@315532800' {} +
payload="$OUTPUT_DIR/ttss-client-seed.zip"
rm -f "$payload"
(cd "$staging" && zip -q -0 -X "$payload" -@ < "$work/file-list.txt")
payload_digest=$(sha256sum "$payload" | cut -d' ' -f1)
jq -Rn '[inputs | split("\t") | {path: .[0], size: (.[1] | tonumber), sha256: .[2], mutable: (.[0] | startswith("resourcepacks/") or startswith("shaderpacks/"))}]' < "$work/files.tsv" > "$work/files.json"
jq -n --arg packId 'ttss-ciap-1.21.1' --arg releaseId "$release_id" --arg contentDigest "$content_digest" --arg payloadSha256 "$payload_digest" --arg automodpackVersion '4.0.6-ttss-managed.2' --arg minecraftVersion '1.21.1' --arg neoForgeVersion '21.1.236' --slurpfile files "$work/files.json" '{schemaVersion: 1, packId: $packId, releaseId: $releaseId, contentDigest: $contentDigest, payload: {file: "ttss-client-seed.zip", sha256: $payloadSha256}, versions: {minecraft: $minecraftVersion, neoforge: $neoForgeVersion, automodpack: $automodpackVersion}, mutableRoots: ["resourcepacks", "shaderpacks", "screenshots", "logs"], files: $files[0]}' > "$OUTPUT_DIR/ttss-client-seed.manifest.json"
openssl dgst -sha256 -sign "$SIGNING_KEY" -out "$OUTPUT_DIR/ttss-client-seed.manifest.sig" "$OUTPUT_DIR/ttss-client-seed.manifest.json"
install -m 0644 "$PUBLIC_KEY" "$OUTPUT_DIR/ttss-client-seed.public.pem"
openssl dgst -sha256 -verify "$OUTPUT_DIR/ttss-client-seed.public.pem" -signature "$OUTPUT_DIR/ttss-client-seed.manifest.sig" "$OUTPUT_DIR/ttss-client-seed.manifest.json" >/dev/null
(cd "$OUTPUT_DIR" && sha256sum ttss-client-seed.zip ttss-client-seed.manifest.json ttss-client-seed.manifest.sig ttss-client-seed.public.pem > SHA256SUMS)
printf 'seed_build=PASS release_id=%s files=%s bytes=%s sha256=%s\n' "$release_id" "$(wc -l < "$work/file-list.txt")" "$(stat -c %s "$payload")" "$payload_digest"
