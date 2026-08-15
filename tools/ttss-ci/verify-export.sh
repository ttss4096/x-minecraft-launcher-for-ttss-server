#!/usr/bin/env bash
set -euo pipefail

root=${1:-}
if [[ -z $root || ! -d $root ]]; then
  printf 'usage: %s EXPORT_ROOT\n' "$0" >&2
  exit 64
fi

manifest="$root/host/automodpack-content.json"
host="$root/host/main"
hailwall="$root/config/hailwall.json"
for path in "$manifest" "$hailwall"; do
  if [[ ! -f $path || -L $path ]]; then
    printf 'required export file is absent or unsafe: %s\n' "$path" >&2
    exit 66
  fi
done
if [[ ! -d $host || -L $host ]]; then
  printf 'host root is absent or unsafe: %s\n' "$host" >&2
  exit 66
fi
for command in jq sha1sum stat diff find sort; do
  command -v "$command" >/dev/null || {
    printf 'required command is missing: %s\n' "$command" >&2
    exit 69
  }
done

if find "$root" -type l -print -quit | grep -q .; then
  printf '%s\n' 'export contains a symbolic link' >&2
  exit 65
fi

jq -e '
  .automodpackVersion == "4.0.6" and
  .mcVersion == "1.21.1" and
  .loader == "neoforge" and
  .loaderVersion == "21.1.236" and
  (.modpackName | type == "string" and length > 0) and
  (.list | type == "array" and length > 0) and
  (.nonModpackFilesToDelete | type == "array") and
  all(.list[];
    (.file | type == "string" and test("^/[^\\\\[:cntrl:]]*$") and (contains("/../") | not) and (endswith("/..") | not)) and
    (.size | type == "string" and test("^[0-9]+$")) and
    (.sha1 | type == "string" and test("^[0-9a-f]{40}$")) and
    (.murmur == null or (.murmur | type == "string" and test("^[0-9]+$"))) and
    (.type | type == "string" and length > 0) and
    (.editable | type == "boolean") and
    (.forceCopy | type == "boolean")
  ) and
  all(.nonModpackFilesToDelete[];
    (.file | type == "string" and test("^/[^\\\\[:cntrl:]]*$") and (contains("/../") | not) and (endswith("/..") | not)) and
    (.sha1 | type == "string" and test("^[0-9a-f]{40}$")) and
    (.timestamp | type == "string" and test("^[0-9]+$"))
  ) and
  (([.list[].file] | unique | length) == (.list | length)) and
  (([.nonModpackFilesToDelete[].file] | unique | length) == (.nonModpackFilesToDelete | length))
' "$manifest" >/dev/null || {
  printf '%s\n' 'AutoModpack manifest schema or path policy failed' >&2
  exit 65
}

jq -e '
  .enforce == true and
  .mode == "whitelist" and
  .operatorsBypass == false and
  .requireCompanionMod == true and
  .verifySignature == true and
  (["automodpack_mod", "hailwall", "sablecollisiondamage", "ttss_exclusive_client"] - .requiredMods | length == 0) and
  (["automodpack_mod", "sablecollisiondamage", "ttss_exclusive_client"] - .whitelist | length == 0) and
  .requiredVersions.automodpack_mod == "4.0.6" and
  .requiredVersions.hailwall == "1.0.3-versionlock.1"
' "$hailwall" >/dev/null || {
  printf '%s\n' 'HailWall enforcement policy failed' >&2
  exit 65
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export LC_ALL=C
jq -r '.list[] | [(.file | ltrimstr("/")), .size, .sha1] | @tsv' "$manifest" | sort > "$work/manifest.tsv"
cut -f1 "$work/manifest.tsv" > "$work/manifest-paths.txt"
find "$host" -type f -printf '%P\n' | sort > "$work/host-paths.txt"
if ! diff -u "$work/manifest-paths.txt" "$work/host-paths.txt" > "$work/path-diff.txt"; then
  cat "$work/path-diff.txt" >&2
  printf '%s\n' 'host file set differs from AutoModpack manifest' >&2
  exit 65
fi

if grep -Ei '(^|/)worldedit[^/]*\.jar$' "$work/manifest-paths.txt"; then
  printf '%s\n' 'server-only WorldEdit was found in the client export' >&2
  exit 65
fi

count=0
bytes=0
while IFS=$'\t' read -r relative expected_size expected_sha1; do
  file="$host/$relative"
  actual_size=$(stat -c %s "$file")
  actual_sha1=$(sha1sum "$file" | cut -d' ' -f1)
  if [[ $actual_size != "$expected_size" || $actual_sha1 != "$expected_sha1" ]]; then
    printf 'host file mismatch: %s\n' "$relative" >&2
    exit 65
  fi
  count=$((count + 1))
  bytes=$((bytes + actual_size))
done < "$work/manifest.tsv"

manifest_sha256=$(sha256sum "$manifest" | cut -d' ' -f1)
hailwall_sha256=$(sha256sum "$hailwall" | cut -d' ' -f1)
printf 'export_verification=PASS files=%s bytes=%s manifest_sha256=%s hailwall_sha256=%s\n' \
  "$count" "$bytes" "$manifest_sha256" "$hailwall_sha256"
