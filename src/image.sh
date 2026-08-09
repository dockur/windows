#!/usr/bin/env bash
set -Eeuo pipefail

getVersions() {

  local xml="$1"

  local image_index image edition_id
  local install_type candidate_base 
  local candidate candidate_id flags
  local evaluation key name structured
  local platform records display product
  local separator=$'\x1f'
  local -A indexes=()

  platform=$(getPlatform "$xml") || return 1

  if ! records=$(xmlstarlet sel \
    -T -t \
    -m '/WIM/IMAGE' \
      -v 'normalize-space(@INDEX)' -o "$separator" \
      -v 'normalize-space(DISPLAYNAME)' -o "$separator" \
      -v 'normalize-space(WINDOWS/PRODUCTNAME)' -o "$separator" \
      -v 'normalize-space(NAME)' -o "$separator" \
      -v 'normalize-space(WINDOWS/EDITIONID)' -o "$separator" \
      -v 'normalize-space(WINDOWS/INSTALLATIONTYPE)' -o "$separator" \
      -v 'normalize-space(FLAGS)' -n \
    - 2>/dev/null <<< "$xml"); then
    error "Failed to read image records from WIM metadata!"
    return 1
  fi

  while IFS="$separator" read -r image_index display product image edition_id install_type flags; do

    [ -n "$image_index" ] || continue

    if [[ ! "$image_index" =~ ^[1-9][0-9]*$ ]]; then
      warn "Invalid image index in WIM metadata: '$image_index'"
      continue
    fi

    candidate_id=""
    candidate_base=""

    for candidate in "$image" "$display" "$product"; do

      [[ "$candidate" == *"Operating System"* ]] && continue
      [ -n "$candidate" ] || continue

      candidate_id=$(getVersion "$candidate" "$platform")
      candidate_base="${candidate_id%%-*}"

      [ -n "$candidate_id" ] && break

    done

    # NAME sometimes contains only the Windows family while DISPLAYNAME
    # contains the actual edition. Use the more specific DISPLAYNAME then.
    if [ -n "$candidate_base" ] && [ -n "$candidate_id" ] && [ -n "$display" ]; then

      name=$(normalizeEdition "$(printVersion "$candidate_base" "")") || return 1
      candidate=$(normalizeEdition "$candidate") || return 1

      if [ "$candidate" = "$name" ]; then
        structured=$(getVersion "$display" "$platform")

        if [ -n "$structured" ] && [ "${structured%%-*}" = "$candidate_base" ] &&
          [[ "${structured%-eval}" != "$candidate_base" ]] &&
          [ "$(getEditionRank "$structured")" -lt 99 ]; then
          candidate_id="$structured"
        fi
      fi

    fi

    if [ -z "$candidate_base" ] || [ -z "$candidate_id" ]; then
      name="${display:-${image:-$product}}"
      [ -n "$name" ] && warn "Unknown image name: '$name'"
      continue
    fi

    evaluation=""

    if [[ "${image,,}" == *"evaluation"* || "${display,,}" == *"evaluation"* ||
      "${product,,}" == *"evaluation"* || "${edition_id,,}" == *"eval"* || "${flags,,}" == *"eval"* ]]; then
      evaluation="-eval"
    fi

    if [ -n "$evaluation" ] && [[ "${candidate_id,,}" != *"-eval" ]]; then
      candidate_id+="$evaluation"
    fi

    key="${candidate_id,,}"

    # Friendly names can collapse two different images to the same ID.
    # Structured metadata is only needed to disambiguate that collision.
    if [[ -v "indexes[$key]" ]]; then

      structured=""

      case "${candidate_base,,}" in

        "win20"* ) structured=$(normalizeServerEditionID "${flags:-$edition_id}") || return 1

          if [[ "${install_type,,}" == *"core"* && "$structured" != *"-core" ]]; then
            structured+="-core"
          fi ;;

        * ) structured=$(normalizeEditionID "${edition_id:-${flags:-}}" "$candidate_base") || return 1 ;;

      esac

      if [ -n "$structured" ]; then
        candidate_id="$candidate_base-$structured$evaluation"
        key="${candidate_id,,}"
      fi

    fi

    if [[ -v "indexes[$key]" ]]; then
      warn "Duplicate image identity '$candidate_id' at indexes ${indexes[$key]} and $image_index"
      continue
    fi

    indexes["$key"]="$image_index"
    printf '%s\t%s\n' "$candidate_id" "$image_index"

  done <<< "$records"

  return 0
}

selectVersion() {

  local wanted="$1"
  shift

  local -a candidates=("$wanted")
  local candidate record id index

  # Normal and Evaluation variants of the same edition are compatible.
  if [[ "${wanted,,}" == *"-eval" ]]; then
    candidates+=("${wanted%-eval}")
  else
    candidates+=("$wanted-eval")
  fi

  for candidate in "${candidates[@]}"; do
    for record in "$@"; do

      IFS=$'\t' read -r id index <<< "$record"
      [[ "${id,,}" == "${candidate,,}" ]] || continue
 
      hasAnswerFile "$id" || continue

      printf '%s\n%s\n' "$id" "$index"
      return 0

    done
  done

  return 1
}

detectVersion() {

  local xml="$1"

  local -a images=() bases=() order=() preferences=()
  local normalize output policy record id index base edition suffix

  output=$(getVersions "$xml") || return
  [ -n "$output" ] && mapfile -t images <<< "$output"

  if [ "${#images[@]}" -eq 0 ]; then
    printf '\n\n'
    return 0
  fi

  for record in "${images[@]}"; do
    IFS=$'\t' read -r id _ <<< "$record"
    bases+=("${id%%-*}")
  done

  policy=$(getEditionPolicy "${bases[0]}") || return 1
  mapfile -t preferences <<< "$policy"

  normalize="${preferences[0]}"
  order=("${preferences[@]:1}")

  # An explicit EDITION always gets first choice.
  if [ -n "$EDITION" ]; then

    for base in "${bases[@]}"; do

      edition=$("$normalize" "$EDITION" "$base") || return 1

      if output=$(selectVersion "$base${edition:+-$edition}" "${images[@]}"); then
        printf '%s\n' "$output"
        return 0
      fi

    done

    warn "edition '$EDITION' is not supported by this image, using automatic selection instead."
  fi

  # Prefer the normal editions in their established order.
  for suffix in "${order[@]}"; do
    for base in "${bases[@]}"; do

      if output=$(selectVersion "$base$suffix" "${images[@]}"); then
        printf '%s\n' "$output"
        return 0
      fi

    done
  done

  # Otherwise keep the established family preference for noncanonical
  # editions, while preserving WIM order within the same family.
  local rank best_rank=99 result="" result_index=""

  for record in "${images[@]}"; do

    IFS=$'\t' read -r id index <<< "$record"

    hasAnswerFile "$id" || continue

    rank=$(getEditionRank "$id")
    (( rank < best_rank )) || continue

    best_rank="$rank"
    result="$id"
    result_index="$index"

  done

  if [ -n "$result" ]; then
    printf '%s\n%s\n' "$result" "$result_index"
    return 0
  fi

  # Keep the first detected identity when only manual/generic fallback remains.
  IFS=$'\t' read -r id index <<< "${images[0]}"

  printf '%s\n%s\n' "$id" "$index"
  return 0
}

detectLanguage() {

  local xml="$1"
  local index="${2:-}"

  local -a paths=()
  local lang culture path
  local image='/WIM/IMAGE'

  if [[ "$index" =~ ^[1-9][0-9]*$ ]]; then
    image="/WIM/IMAGE[@INDEX='$index']"
  fi

  # Prefer the selected image's default language, then its fallback default,
  # and finally the first listed language.
  paths=(
    "$image/WINDOWS/LANGUAGES/DEFAULT[1]"
    "$image/WINDOWS/LANGUAGES/FALLBACK/DEFAULT[1]"
    "$image/WINDOWS/LANGUAGES/LANGUAGE[1]"
  )

  lang=""

  for path in "${paths[@]}"; do

    if ! lang=$(xmlstarlet sel -T -t -v "normalize-space(string(($path)[1]))" - 2>/dev/null <<< "$xml"); then
      warn "failed to read language metadata from Windows image!"
      return 0
    fi

    [ -n "$lang" ] && break

  done

  if [ -z "$lang" ]; then
    warn "language could not be detected from ISO!"
    return 0
  fi

  culture=$(getLanguage "$lang" "culture") || return 1

  if [ -n "$culture" ]; then
    LANGUAGE="$lang"
    return 0
  fi

  warn "invalid language detected: \"$lang\""
  return 0
}

getImageSize() {

  local stage="$1"
  local folder="${2:-}"

  local size bytes path output
  local required large_file
  local mib=$((1024 * 1024))
  local minimum=$((64 * mib))
  local payload=0 paths=("$stage")

  if [ ! -d "$stage" ]; then
    error "Failed to find setup directory: $stage"
    return 1
  fi

  [ -n "$folder" ] && paths+=("$folder")

  # The setup image uses FAT32, so reject files that cannot be represented even
  # when the image itself has enough free space.
  large_file=$(find -L "${paths[@]}" -type f -size +4294967295c -print -quit) || return 1

  if [ -n "$large_file" ]; then
    error "Setup file exceeds the FAT32 limit: $large_file"
    return 1
  fi

  for path in "${paths[@]}"; do

    if ! output=$(du -Llsb --apparent-size -- "$path"); then
      error "Failed to calculate setup size!"
      return 1
    fi

    if ! read -r bytes _ <<< "$output" || [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
      error "Failed to calculate setup size!"
      return 1
    fi

    payload=$((payload + bytes))

  done

  # Reserve generous filesystem and directory overhead, then round up to a
  # power-of-two image size with a 64 MiB minimum.
  size="$minimum"
  required=$((payload + ((payload + 3) / 4) + (32 * mib)))

  while ((size < required)); do
    size=$((size * 2))
  done

  printf '%s\n' "$size"
}

getArchiveSize() {

  local file="$1"
  local result_name="$2"
  local -n result="$result_name"

  local found=0 listing line value rc

  result=0

  listing=$(7z l -slt "$file" 2>/dev/null) || {
    rc=$?
    error "Failed to read archive information: $file"
    return "$rc"
  }

  while IFS= read -r line; do

    [[ "$line" == "Size = "* ]] || continue

    value="${line#Size = }"
    [[ "$value" =~ ^[0-9]+$ ]] || continue

    result=$(( result + value ))
    found=1

  done <<< "$listing"

  if (( ! found )); then
    error "Failed to determine archive contents size: $file"
    return 1
  fi

  return 0
}

extractImage() {

  local iso="$1"
  local dir="$2"
  local version="$3"

  local target="$dir"
  local desc="local ISO"
  local archive="${dir}.archive"
  local file size required archiveSize rc

  if [ -z "$CUSTOM" ]; then
    desc="downloaded ISO"
    if [[ "$version" != "http"* ]]; then
      desc=$(printVariant "$version" "$desc")
    fi
  fi

  if [[ "${iso,,}" == *".esd" ]]; then
    extractESD "$iso" "$dir" "$version" "$desc" || return
    return 0
  fi

  local msg="Extracting $desc image"
  info "$msg..." && html "$msg..."

  enabled "${UNPACK:-}" && target="$archive"

  if ! rm -rf -- "$dir" "$archive"; then
    error "Failed to remove extraction directories!"
    return 1
  fi

  if ! makeDir "$target"; then
    error "Failed to create directory \"$target\" !"
    return 1
  fi

  if ! size=$(stat -c%s "$iso"); then
    error "Failed to determine ISO file size: $iso"
    return 1
  fi

  if (( size < 10000000 )); then
    error "Invalid ISO file: Size of \"$iso\" is smaller than 10 MB"
    return 1
  fi

  required="$size"

  if enabled "${UNPACK:-}"; then
    getArchiveSize "$iso" archiveSize || return
    required="$archiveSize"
  fi

  checkFreeSpace "$target" "$required" || return 1

  if ! rm -rf -- "$target"; then
    error "Failed to remove directory \"$target\" !"
    return 1
  fi

  /run/progress.sh "$target" "$size" "$msg ([P])..." &

  7z x "$iso" -o"$target" > /dev/null || {
    rc=$?
    fKill "progress.sh"
    error "Failed to extract ISO file: $iso"
    return "$rc"
  }

  fKill "progress.sh"

  if ! enabled "${UNPACK:-}"; then

    LABEL=$(isoinfo -d -i "$iso" | sed -n 's/Volume id: //p') || LABEL=""

  else

    # Locate the first root-level ISO in the downloaded archive
    if ! file=$(find "$archive" -maxdepth 1 -type f -iname "*.iso" -print -quit); then
      error "Failed to search for a nested ISO in the extracted archive!"
      return 1
    fi

    if [ -z "$file" ]; then
      error "Failed to find any nested ISO files in the archive!"
      return 1
    fi

    if ! mv -f -- "$file" "$iso"; then
      error "Failed to preserve extracted ISO file: $file"
      return 1
    fi

    if ! rm -rf -- "$archive"; then
      error "Failed to remove directory \"$archive\" !"
      return 1
    fi

    if ! makeDir "$dir"; then
      error "Failed to create directory \"$dir\" !"
      return 1
    fi

    if ! size=$(stat -c%s "$iso"); then
      error "Failed to determine nested ISO file size: $iso"
      return 1
    fi

    checkFreeSpace "$dir" "$size" || return 1

    7z x "$iso" -o"$dir" > /dev/null || {
      rc=$?
      error "Failed to extract nested ISO file: $iso"
      return "$rc"
    }

    LABEL=$(isoinfo -d -i "$iso" | sed -n 's/Volume id: //p') || LABEL=""

    UNPACK=""

  fi

  return 0
}

checkPlatform() {

  local xml="$1"
  local platform

  IMAGE_PLATFORM=""
  platform=$(getPlatform "$xml") || return 1

  case "${platform,,}" in
    "mixed" )
      error "Windows images with mixed architectures are not supported!"
      return 1  ;;
    "x86" | "x64" | "arm64" ) ;;
    * )
      error "Unsupported Windows image architecture: ${platform:-unknown}"
      return 1 ;;
  esac

  case "${PLATFORM,,}" in
    "x64" )
      if [[ "${platform,,}" != "x64" && "${platform,,}" != "x86" ]]; then
        error "You cannot boot ${platform^^} images on a $PLATFORM CPU!"
        return 1
      fi ;;
    "arm64" )
      if [[ "${platform,,}" != "arm64" ]]; then
        error "You cannot boot ${platform^^} images on a $PLATFORM CPU!"
        return 1
      fi ;;
    * )
      error "Unsupported container platform: $PLATFORM"
      return 1 ;;
  esac

  IMAGE_PLATFORM="${platform,,}"
  return 0
}

getPlatform() {

  local xml="$1"

  local arch current platform=""
  local image_count output records
  local separator=$'\x1f'

  if ! output=$(xmlstarlet sel \
    -T -t \
    -v 'count(/WIM/IMAGE)' -n \
    -m '/WIM/IMAGE' \
      -v 'count(WINDOWS/ARCH)' -o "$separator" \
      -v 'normalize-space(WINDOWS/ARCH)' -n \
    - 2>/dev/null <<< "$xml"); then
    error "Failed to read architecture metadata from WIM image!"
    return 1
  fi

  image_count="${output%%$'\n'*}"

  if [ "$image_count" = "0" ]; then
    error "No images were found in WIM metadata!"
    return 1
  fi

  records="${output#*$'\n'}"

  while IFS="$separator" read -r count arch; do

    if [ "$count" != "1" ]; then
      error "Missing or duplicate architecture metadata in WIM image!"
      return 1
    fi

    case "$arch" in
      "0" ) current="x86" ;;
      "9" ) current="x64" ;;
      "12" ) current="arm64" ;;
      * )
        error "Unsupported architecture value in WIM metadata!"
        return 1 ;;
    esac

    if [ -z "$platform" ]; then
      platform="$current"
    elif [ "$platform" != "$current" ]; then
      platform="mixed"
    fi

  done <<< "$records"

  echo "$platform"
  return 0
}

createImageDirectory() {

  local image="$1"
  local directory="$2"

  if mdir -i "$image" "$directory" >/dev/null 2>&1; then
    return 0
  fi

  mmd -i "$image" "$directory" >/dev/null
}

createSetupImage() {

  local stage="$1"
  local image="$2"

  local tmp="${image}.tmp"
  local target="::/\$OEM\$/\$1/OEM"
  local install="$stage/.overlay-install.bat"
  local folder size sectors entry find_pid
  local entries=()

  folder=$(getOemFolder) || return 1

  if ! size=$(getImageSize "$stage" "$folder"); then
    return 1
  fi

  sectors=$((size / 512))

  local msg="Writing overlay image..."
  info "$msg" && html "$msg"

  # Build and verify a temporary FAT32 image before publishing it as setup
  # media, so a partial write never becomes boot media.

  rm -f -- "$tmp" || return 1

  checkFreeSpace "$(dirname "$image")" "$size" || return 1

  if ! mformat -i "$tmp" -C -F -T "$sectors" -v "SETUP" ::; then
    rm -f -- "$tmp"
    error "Failed to format setup image!"
    return 1
  fi

  mapfile -d '' entries < <(
    find "$stage" -mindepth 1 -maxdepth 1 ! -name '.overlay-install.bat' -print0
  )

  # Process substitution hides the find status, so wait for it explicitly.
  find_pid=$!

  if ! wait "$find_pid"; then
    rm -f -- "$tmp"
    error "Failed to enumerate image files!"
    return 1
  fi

  for entry in "${entries[@]}"; do

    if ! mcopy -Q -s -i "$tmp" "$entry" ::; then
      rm -f -- "$tmp"
      error "Failed to copy image file: $entry"
      return 1
    fi

  done

  if [ -n "$folder" ] || [ -f "$install" ]; then

    if ! createImageDirectory "$tmp" "::/\$OEM\$" || ! createImageDirectory "$tmp" "::/\$OEM\$/\$1" ||
      ! createImageDirectory "$tmp" "$target"; then

      rm -f -- "$tmp"
      error "Failed to create OEM directory in setup image!"
      return 1
    fi

  fi

  if [ -n "$folder" ]; then

    mapfile -d '' entries < <(
      find "$folder" -mindepth 1 -maxdepth 1 -print0
    )

    # Preserve errors from the second process-substitution find as well.
    find_pid=$!

    if ! wait "$find_pid"; then
      rm -f -- "$tmp"
      error "Failed to enumerate OEM files!"
      return 1
    fi

    for entry in "${entries[@]}"; do

      if ! mcopy -Q -s -o -i "$tmp" "$entry" "$target"; then
        rm -f -- "$tmp"
        error "Failed to copy OEM file: $entry"
        return 1
      fi

    done

  fi

  # Copy the generated overlay script last so it replaces an install.bat from
  # the mounted OEM folder when both are present.
  if [ -f "$install" ]; then

    if ! mcopy -Q -o -i "$tmp" "$install" "$target/install.bat"; then
      rm -f -- "$tmp"
      error "Failed to replace install.bat in setup image!"
      return 1
    fi

  fi

  # Verify that mtools can read the completed filesystem before publishing it.
  if ! mdir -i "$tmp" :: >/dev/null; then
    rm -f -- "$tmp"
    error "Failed to verify image!"
    return 1
  fi

  if ! enabled "$MANUAL"; then

    local answer="$stage/Autounattend.xml"

    if [ ! -f "$answer" ] || [ ! -s "$answer" ]; then
      rm -f -- "$tmp"
      error "Failed to find staged answer file: $answer"
      return 1
    fi

    # Ensure the answer file survived the FAT32 copy byte-for-byte.
    if ! mtype -i "$tmp" ::/Autounattend.xml | cmp -s - "$answer"; then
      rm -f -- "$tmp"
      error "Failed to verify staged answer file!"
      return 1
    fi

  fi

  if ! mv -f -- "$tmp" "$image"; then
    rm -f -- "$tmp"
    error "Failed to save setup image: $image"
    return 1
  fi

  if ! setOwner "$image"; then
    warn "Failed to set the owner for \"$image\" !"
  fi

  return 0
}

findIsoImage() {

  local iso="$1"
  local path

  # Direct UDF inspection is unavailable for valid ISO9660-only media, so
  # fall back to extraction when the image can still be read as ISO9660.
  if ! udfread stat --ignore-case "$iso" / >/dev/null 2>&1; then

    if isoinfo -d -i "$iso" >/dev/null 2>&1; then
      return 1
    fi

    enabled "$DEBUG" && echo "Neither UDF nor ISO9660 inspection could read the ISO image: $iso" >&2
    error "Failed to read ISO image: $iso"

    return 2
  fi

  if ! udfread stat --ignore-case "$iso" /sources >/dev/null 2>&1; then
    enabled "$DEBUG" && echo "The UDF filesystem is readable, but the /sources directory is unavailable." >&2
    return 1
  fi

  # Prefer install.wim when both payload forms are present.
  for path in /sources/install.wim /sources/install.esd; do

    if udfread stat --ignore-case "$iso" "$path" >/dev/null 2>&1; then

      printf '%s' "$path"
      return 0
    fi

  done

  enabled "$DEBUG" && echo "No install.wim or install.esd payload was found in /sources." >&2
  return 1
}

readWimHeader() {

  local iso="$1"
  local image="$2"

  local size signature
  local header="$TMP/wim-header.bin"

  if ! rm -f -- "$header"; then
    enabled "$DEBUG" && echo "Failed to remove the previous temporary WIM header: $header" >&2
    return 1
  fi

  # Read only the fixed WIM header so metadata can be located without
  # extracting install.wim or install.esd from the ISO.
  if ! udfread range --ignore-case -o "$header" "$iso" "$image" 0 208 >/dev/null 2>&1; then
    enabled "$DEBUG" && echo "udfread failed to read the first 208 bytes of $image from $iso." >&2
    rm -f -- "$header"
    return 1
  fi

  if ! size=$(stat -c%s -- "$header"); then
    enabled "$DEBUG" && echo "Failed to determine the size of the temporary WIM header: $header" >&2
    rm -f -- "$header"
    return 1
  fi

  if (( size != 208 )); then
    enabled "$DEBUG" && echo "The WIM header is $size bytes instead of the expected 208 bytes." >&2
    rm -f -- "$header"
    return 1
  fi

  if ! signature=$(od -An -N8 -tx1 "$header" | tr -d ' \n'); then
    enabled "$DEBUG" && echo "Failed to read the WIM header signature from $header." >&2
    rm -f -- "$header"
    return 1
  fi

  if [[ "$signature" != "4d5357494d000000" ]]; then
    enabled "$DEBUG" && echo "The WIM header has an invalid signature: ${signature:-empty}." >&2
    rm -f -- "$header"
    return 1
  fi

  echo "$header"
  return 0
}

readIsoImageInfo() {

  local iso="$1"
  local image="$2"
  local header="$3"

  local raw result xml_count rc
  local root header_size version
  local part_number total_parts image_count
  local xml_offset xml_size xml_original xml_flags
  local -a bytes=() values=()

  if [ ! -f "$header" ]; then
    enabled "$DEBUG" && echo "The temporary WIM header does not exist: $header" >&2
    return 1
  fi

  raw=$(od -An -v -N208 -tu1 -- "$header") || {
    enabled "$DEBUG" && echo "Failed to read the 208-byte WIM header from $header." >&2
    return 1
  }

  read -r -a bytes <<< "${raw//$'\n'/ }"

  if (( ${#bytes[@]} != 208 )); then
    enabled "$DEBUG" && echo "The WIM header decoded to ${#bytes[@]} bytes instead of 208." >&2
    return 1
  fi

  # Validate the MSWIM\0\0\0 signature.
  if ! (( bytes[0] == 77 &&
         bytes[1] == 83 &&
         bytes[2] == 87 &&
         bytes[3] == 73 &&
         bytes[4] == 77 &&
         bytes[5] == 0 &&
         bytes[6] == 0 &&
         bytes[7] == 0 )); then
    enabled "$DEBUG" && echo "The decoded WIM header does not contain the expected MSWIM signature." >&2
    return 1
  fi

  # Header size at offset 0x08.
  header_size=$(( \
    bytes[8] |
    bytes[9] << 8 |
    bytes[10] << 16 |
    bytes[11] << 24
  ))

  if (( header_size != 208 )); then
    enabled "$DEBUG" && echo "The WIM header declares an unexpected header size: $header_size bytes." >&2
    return 1
  fi

  # WIM version at offset 0x0c.
  version=$(( \
    bytes[12] |
    bytes[13] << 8 |
    bytes[14] << 16 |
    bytes[15] << 24
  ))

  if ! (( version == 0x10d00 || version == 0x0e00 )); then
    enabled "$DEBUG" && echo "The WIM header contains an unsupported version value: $version." >&2
    return 1
  fi

  # Split-WIM information at offsets 0x28 and 0x2a.
  part_number=$((bytes[40] | bytes[41] << 8))
  total_parts=$((bytes[42] | bytes[43] << 8))

  if ! (( part_number > 0 &&
         total_parts > 0 &&
         part_number <= total_parts )); then
    enabled "$DEBUG" && echo "The WIM split-image fields are invalid: part $part_number of $total_parts." >&2
    return 1
  fi

  # Image count at offset 0x2c.
  image_count=$(( \
    bytes[44] |
    bytes[45] << 8 |
    bytes[46] << 16 |
    bytes[47] << 24
  ))

  if ! (( image_count > 0 && image_count <= 65535 )); then
    enabled "$DEBUG" && echo "The WIM header contains an invalid image count: $image_count." >&2
    return 1
  fi

  result=$(parseWimHeader "$iso" "$image" "$header") || {
    enabled "$DEBUG" && echo "Failed to parse the WIM XML resource descriptor." >&2
    return 1
  }

  mapfile -t values <<< "$result"

  if (( ${#values[@]} != 4 )); then
    enabled "$DEBUG" && echo "The WIM XML resource descriptor returned ${#values[@]} values instead of 4." >&2
    return 1
  fi

  xml_offset="${values[0]}"
  xml_size="${values[1]}"
  xml_original="${values[2]}"
  xml_flags="${values[3]}"

  if ! [[ "$xml_offset" =~ ^[0-9]+$ &&
          "$xml_size" =~ ^[0-9]+$ &&
          "$xml_original" =~ ^[0-9]+$ &&
          "$xml_flags" =~ ^[0-9]+$ ]]; then
    enabled "$DEBUG" && echo "The WIM XML resource descriptor contains non-numeric values: offset=$xml_offset size=$xml_size original=$xml_original flags=$xml_flags." >&2
    return 1
  fi

  if ! (( xml_size > 0 &&
         xml_original > 0 &&
         xml_size == xml_original &&
         xml_size % 2 == 0 )); then
    enabled "$DEBUG" && echo "The WIM XML resource sizes are invalid: size=$xml_size original=$xml_original." >&2
    return 1
  fi

  # These resource forms cannot be decoded as a direct UTF-16LE byte range:
  #
  # 0x04: compressed
  # 0x08: spanned
  # 0x10: solid
  #
  # The metadata flag 0x02 is expected and deliberately allowed.
  if (( xml_flags & 0x1c )); then
    enabled "$DEBUG" && echo "The WIM XML resource uses unsupported flags: $xml_flags." >&2
    return 1
  fi

  result=$(udfread range --ignore-case "$iso" "$image" "$xml_offset" "$xml_size" \
           2>/dev/null | iconv -f UTF-16LE -t UTF-8 2>/dev/null
  ) || {
    rc=$?
    enabled "$DEBUG" && echo "Failed to read or decode the WIM XML metadata range at offset $xml_offset with size $xml_size (status $rc)." >&2
    return "$rc"
  }

  if [ -z "$result" ]; then
    enabled "$DEBUG" && echo "The WIM XML metadata range was empty." >&2
    return 1
  fi

  local metadata separator=$'\x1f'

  metadata=$(xmlstarlet sel \
    -T -t \
    -v 'local-name(/*)' -o "$separator" \
    -v 'count(/*[local-name()="WIM"]/*[local-name()="IMAGE"])' \
    - 2>/dev/null <<< "$result") || {
    enabled "$DEBUG" && echo "Failed to parse the WIM XML metadata document." >&2
    return 1
  }

  IFS="$separator" read -r root xml_count <<< "$metadata"

  if [ "$root" != "WIM" ]; then
    enabled "$DEBUG" && echo "The WIM XML metadata has an unexpected root element: ${root:-empty}." >&2
    return 1
  fi

  if [[ ! "$xml_count" =~ ^[0-9]+$ ]]; then
    enabled "$DEBUG" && echo "The WIM XML metadata returned an invalid image count: ${xml_count:-empty}." >&2
    return 1
  fi

  if (( xml_count != image_count )); then
    enabled "$DEBUG" && echo "The WIM header image count ($image_count) does not match the XML metadata image count ($xml_count)." >&2
    return 1
  fi

  printf '%s' "$result"
  return 0
}

parseWimHeader() {

  local iso="$1"
  local image="$2"
  local header="$3"

  local -a bytes=()
  local header_size=0
  local parsed_size=0
  local parsed_flags=0
  local parsed_offset=0
  local parsed_original=0
  local details image_size raw

  if [ ! -f "$header" ] || [ ! -s "$header" ]; then
    enabled "$DEBUG" && echo "The WIM header file is missing or empty: $header" >&2
    return 1
  fi

  if ! raw=$(od -An -v -j8 -N88 -tu1 -- "$header"); then
    enabled "$DEBUG" && echo "Failed to read the WIM header fields from offset 0x08." >&2
    return 1
  fi

  read -r -a bytes <<< "${raw//$'\n'/ }"

  if (( ${#bytes[@]} != 88 )); then
    enabled "$DEBUG" && echo "The WIM resource-header section decoded to ${#bytes[@]} bytes instead of 88." >&2
    return 1
  fi

  local i

  # The WIM header size is a 32-bit little-endian value at offset 0x08.
  for ((i=3; i>=0; i--)); do
    header_size=$((header_size * 256 + bytes[i]))
  done

  if (( header_size != 208 )); then
    enabled "$DEBUG" && echo "The WIM resource parser found an unexpected header size: $header_size bytes." >&2
    return 1
  fi

  # The XML resource descriptor starts at offset 0x48. Its first seven bytes
  # contain the stored size and its eighth byte contains the resource flags.
  for ((i=70; i>=64; i--)); do
    parsed_size=$((parsed_size * 256 + bytes[i]))
  done

  parsed_flags="${bytes[71]}"

  # The XML resource offset is an unsigned 64-bit little-endian value at 0x50.
  if (( bytes[79] >= 128 )); then
    enabled "$DEBUG" && echo "The WIM XML resource offset cannot be represented safely as a signed shell integer." >&2
    return 1
  fi

  for ((i=79; i>=72; i--)); do
    parsed_offset=$((parsed_offset * 256 + bytes[i]))
  done

  # The uncompressed XML size is an unsigned 64-bit value at offset 0x58.
  if (( bytes[87] >= 128 )); then
    enabled "$DEBUG" && echo "The WIM XML resource size cannot be represented safely as a signed shell integer." >&2
    return 1
  fi

  for ((i=87; i>=80; i--)); do
    parsed_original=$((parsed_original * 256 + bytes[i]))
  done

  if (( parsed_size <= 0 || parsed_offset < header_size || parsed_original <= 0 )); then
    enabled "$DEBUG" && echo "The WIM XML resource descriptor is invalid: offset=$parsed_offset size=$parsed_size original=$parsed_original header=$header_size." >&2
    return 1
  fi

  if ! details=$(udfread stat --ignore-case "$iso" "$image" 2>/dev/null); then
    enabled "$DEBUG" && echo "udfread failed to determine the size of $image in $iso." >&2
    return 1
  fi

  image_size=$(sed -n 's/^Size: \([0-9][0-9]*\) bytes$/\1/p' <<< "$details")

  if [[ ! "$image_size" =~ ^[0-9]+$ ]]; then
    enabled "$DEBUG" && echo "udfread returned no usable size for $image." >&2
    return 1
  fi

  if (( parsed_offset > image_size || parsed_size > image_size - parsed_offset )); then
    enabled "$DEBUG" && echo "The WIM XML resource lies outside the image bounds: offset=$parsed_offset size=$parsed_size image=$image_size." >&2
    return 1
  fi

  printf '%s\n' "$parsed_offset" "$parsed_size" "$parsed_original" "$parsed_flags"

  return 0
}

findImage() {

  local dir="$1"
  local name sources result

  sources=$(find "$dir" -maxdepth 1 -type d -iname sources -print -quit) || return 2

  if [ ! -d "$sources" ]; then
    warn "failed to locate 'sources' folder in ISO image, $FB"
    return 1
  fi

  for name in install.wim install.esd; do

    result=$(find "$sources" -maxdepth 1 -type f -iname "$name" -print -quit) || return 2
    [ -n "$result" ] && break

  done

  if [ ! -f "$result" ]; then
    warn "failed to locate 'install.wim' or 'install.esd' in ISO image, $FB"
    return 1
  fi

  echo "$result"
  return 0
}

readImageInfo() {

  local wim="$1"
  local result=""
  local msg="Failed to read Windows image information!"

  if ! result=$(wimlib-imagex info --xml "$wim" | iconv -f UTF-16LE -t UTF-8); then
    error "$msg"
    return 2
  fi

  if [ -z "$result" ]; then
    error "$msg"
    return 2
  fi

  printf '%s' "$result"
  return 0
}

validateEdition() {

  [ -n "$EDITION" ] || return 0
  [[ "${DETECTED,,}" == "win20"* ]] || return 0

  local edition
  edition=$(normalizeServerEditionID "$EDITION") || return 1

  [ -n "$edition" ] || return 0

  if [[ "${DETECTED,,}" == *"-${edition,,}" || "${DETECTED,,}" == *"-${edition,,}-eval" ]]; then
    return 0
  fi

  # Discard a stale server-edition override when it conflicts with the image
  # that was actually detected.
  EDITION=""

  return 0
}

unknownImage() {

  local rc=0
  local msg="Failed to determine Windows version from image"

  setXML "" || rc=$?

  if (( rc == 0 )) || enabled "$MANUAL"; then
    info "${msg}!"
    return 0
  fi

  # Only absence of a usable answer file is a supported manual fallback.
  (( rc == 1 )) || return "$rc"

  MANUAL="Y"
  warn "${msg}, $FB."

  return 0
}

describeImage() {

  local result
  result=$(printEdition "$DETECTED" "$DETECTED" "Y") || return 1

  if [[ "${LANGUAGE,,}" != "en" && "${LANGUAGE,,}" != "en-"* ]]; then

    local language
    language=$(getLanguage "$LANGUAGE" "desc") || return 1

    result+=" ($language)"

  fi

  printf '%s' "$result"
  return 0
}

configureImage() {

  local index="$1"
  local desc="$2"

  local rc=0

  # Prefer the exact answer file, then a family-level fallback. Manual mode is
  # the final supported path only when no usable template exists.
  setXML "" "$index" || rc=$?

  if (( rc == 0 )); then
    return 0
  fi

  enabled "$MANUAL" && return 0

  # Generation or preparation errors must not be hidden by another fallback.
  (( rc == 1 )) || return "$rc"

  if [[ "$DETECTED" == "win81x86"* || "$DETECTED" == "win10x86"* ]]; then
    error "The 32-bit version of $desc is not supported!"
    return 2
  fi

  local msg="the answer file for $desc was not found ($DETECTED.xml)"
  local fallback="/run/assets/${DETECTED%%-*}.xml"

  rc=0
  setXML "$fallback" "$index" || rc=$?

  if (( rc == 0 )); then
    warn "${msg}."
    return 0
  fi

  enabled "$MANUAL" && return 0

  # The family-level template was present but could not be generated/prepared.
  (( rc == 1 )) || return "$rc"

  MANUAL="Y"
  warn "${msg}, $FB."

  return 0
}

detectImageInfo() {

  local image_info="$1"
  local desc index rc

  checkPlatform "$image_info" || return 2

  local output
  output=$(detectVersion "$image_info") || {
    enabled "$DEBUG" && echo "Version detection failed while parsing the Windows image metadata." >&2
    error "Failed to detect the Windows version from image metadata!"
    return 1
  }

  local -a detected=()
  mapfile -t detected <<< "$output"

  DETECTED="${detected[0]:-}"
  index="${detected[1]:-}"

  validateEdition || {
    enabled "$DEBUG" && echo "Edition validation failed for detected image: ${DETECTED:-empty}, index: ${index:-empty}." >&2
    error "Failed to validate the Windows edition from image metadata!"
    return 1
  }

  if [ -z "$DETECTED" ]; then

    unknownImage || {
      rc=$?
      enabled "$DEBUG" && echo "Unknown-image handling failed after no Windows version could be detected (status $rc)." >&2
      return "$rc"
    }

    return 0
  fi

  detectLanguage "$image_info" "$index" || {
    rc=$?
    enabled "$DEBUG" && echo "Failed to detect the language for image $DETECTED at index ${index:-empty} (status $rc)." >&2
    return "$rc"
  }

  desc=$(describeImage) || {
    rc=$?
    enabled "$DEBUG" && echo "Failed to describe the detected Windows image $DETECTED (status $rc)." >&2
    return "$rc"
  }

  info "Detected: $desc"

  configureImage "$index" "$desc" || {
    rc=$?
    enabled "$DEBUG" && echo "Failed to configure the detected Windows image $DETECTED at index ${index:-empty} (status $rc)." >&2
    return "$rc"
  }

  return 0
}

detectIsoImage() {

  local iso="$1"
  local image header image_info rc

  # Return 1 only when no directly inspectable WIM/ESD payload is available so
  # the caller may extract the media. Metadata parsing/configuration errors use 2.
  image=$(findIsoImage "$iso") || {
    rc=$?
    enabled "$DEBUG" && echo "ISO image lookup failed (status $rc)." >&2
    return "$rc"
  }

  header=$(readWimHeader "$iso" "$image") || {
    error "Failed to read the Windows image header!"
    return 2
  }

  image_info=$(readIsoImageInfo "$iso" "$image" "$header") || {
    error "Failed to read the Windows image metadata!"
    return 2
  }

  info "Detecting version from ISO image..."

  detectImageInfo "$image_info" || {
    error "Failed to process the Windows image metadata!"
    return 2
  }

  return 0
}

detectESDImage() {

  local iso="$1"

  local image_info install_info output index rc
  local -a detected=()

  image_info=$(wimlib-imagex info "$iso" --xml 2>/dev/null |
    iconv -f UTF-16LE -t UTF-8 2>/dev/null) || {
    rc=$?
    error "Cannot read ESD file information (status $rc)."
    return 2
  }

  # Microsoft download ESDs use images 1-3 for setup media, WinPE, and Windows
  # Setup; images 4 and higher contain installable editions.
  if ! install_info=$(xmlstarlet ed \
      -d '/WIM/IMAGE[number(@INDEX) < 4]' \
      <<< "$image_info" 2>/dev/null); then
    error "Cannot read installable images from ESD file!"
    return 2
  fi

  checkPlatform "$install_info" || return 2

  local output
  output=$(detectVersion "$install_info") || {
    error "Failed to detect Windows version from the ESD metadata!"
    return 2
  }

  mapfile -t detected <<< "$output"
  index="${detected[1]:-}"

  if [ -z "$index" ]; then
    error "Failed to select an installation image based on the ESD metadata!"
    return 2
  fi

  # extractESD removes every other image, leaving the selected edition at
  # index 1. Detect against that final layout so the generated answer file
  # already references the index that will exist after extraction.
  if ! image_info=$(xmlstarlet ed \
      -d "/WIM/IMAGE[number(@INDEX) != $index]" \
      -u "/WIM/IMAGE[@INDEX='$index']/@INDEX" -v '1' \
      <<< "$install_info" 2>/dev/null); then
    error "Cannot prepare ESD image information!"
    return 2
  fi

  info "Detecting version from ESD image..."

  detectImageInfo "$image_info" || {
    error "Failed to process the ESD image metadata!"
    return 2
  }

  return 0
}

checkFreeSpace() {

  local dir="$1"
  local size="$2"

  local base space size_gb space_gb
  base=$(baseDir "$dir")

  if ! space=$(df --output=avail -B 1 "$dir" | tail -n 1); then
    error "Failed to check free space in $dir."
    return 1
  fi

  if [[ ! "$space" =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]]; then
    error "Failed to determine available disk space for $dir."
    return 1
  fi

  space="${space//[[:space:]]/}"

  if (( size > space )); then

    size_gb=$(formatBytes "$size")
    space_gb=$(formatBytes "$space")

    error "Not enough free space in $base, have $space_gb available but need at least $size_gb."
    return 1

  fi

  return 0
}

extractESD() {

  local iso="$1"
  local dir="$2"
  local version="$3"
  local desc="$4"

  local installSize size edition imgEdition
  local bootTotal bootLinks wimTotal wimLinks
  local bootWim installWim bootSize wimSize
  local image index line ret metadata count
  local resultCount resultIndex resultEdition
  local xml installXml output result
  local -a detected fields

  local minSize=100000000
  local bootPad=60000000
  local installPad=3000000
  local spacePad=1073741824

  local msg="Extracting bootdisk from ESD file"
  info "$msg..." && html "$msg..."

  if ! size=$(stat -c%s -- "$iso"); then
    error "Failed to determine size of ISO file \"$iso\" !"
    return 1
  fi

  if (( size < minSize )); then
    error "The downloaded ESD file is too small!"
    return 1
  fi

  if ! rm -rf -- "$dir"; then
    error "Failed to remove directory \"$dir\" !"
    return 1
  fi

  if ! makeDir "$dir"; then
    error "Failed to create directory \"$dir\" !"
    return 1
  fi

  xml=$(wimlib-imagex info "$iso" --xml 2>/dev/null |
    iconv -f UTF-16LE -t UTF-8 2>/dev/null) || {
    ret=$?
    error "Cannot read ESD file information!"
    return "$ret"
  }

  # Microsoft download ESDs use images 1-3 for setup media, WinPE, and Windows
  # Setup; images 4 and higher contain installable editions. Read all metadata
  # once because repeatedly inspecting a solid-compressed ESD is expensive.
  if ! metadata=$(xmlstarlet sel -t \
      -v 'count(/WIM/IMAGE)' -n \
      -v 'normalize-space(/WIM/IMAGE[@INDEX="1"]/TOTALBYTES)' -n \
      -v 'normalize-space(/WIM/IMAGE[@INDEX="1"]/HARDLINKBYTES)' -n \
      -v 'normalize-space(/WIM/IMAGE[@INDEX="3"]/TOTALBYTES)' -n \
      -v 'normalize-space(/WIM/IMAGE[@INDEX="3"]/HARDLINKBYTES)' -n \
      -m '/WIM/IMAGE[number(@INDEX) >= 4]' -v '@INDEX' -o $'\t' -v 'DESCRIPTION' -n \
      <<< "$xml" 2>/dev/null); then
    error "Cannot read ESD file information!"
    return 1
  fi

  mapfile -t fields <<< "$metadata"

  count="${fields[0]:-}"
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    error "Cannot read the image count in ESD file!"
    return 1
  fi

  if (( count < 4 )); then
    error "Invalid ESD file: expected at least 4 images, found $count."
    return 1
  fi

  bootTotal="${fields[1]:-}"
  bootLinks="${fields[2]:-}"

  if [[ ! "$bootTotal" =~ ^[0-9]+$ ]] || [[ ! "$bootLinks" =~ ^[0-9]+$ ]]; then
    error "Cannot read bootdisk size from ESD file!"
    return 1
  fi

  bootSize=$(( bootTotal - bootLinks ))

  wimTotal="${fields[3]:-}"
  wimLinks="${fields[4]:-}"

  if [[ ! "$wimTotal" =~ ^[0-9]+$ ]] ||
      [[ ! "$wimLinks" =~ ^[0-9]+$ ]]; then
    error "Cannot read boot.wim size from ESD file!"
    return 1
  fi

  wimSize=$(( wimTotal - wimLinks + bootPad ))

  # The downloaded ESD already occupies disk space and is moved into the
  # installation media. Peak additional usage consists of the extracted setup
  # files and boot.wim, plus the final ISO containing those files and the ESD.
  local freeSpace=$(( size + 2 * (bootSize + wimSize) + spacePad ))

  checkFreeSpace "$dir" "$freeSpace" || return

  /run/progress.sh "$dir" "$bootSize" "$msg ([P])..." &

  index="1"
  wimlib-imagex apply "$iso" "$index" "$dir" --quiet 2>/dev/null || {
    ret=$?
    fKill "progress.sh"
    error "Extracting $desc bootdisk failed ($ret)"
    return "$ret"
  }

  fKill "progress.sh"

  bootWim="$dir/sources/boot.wim"
  installWim="$dir/sources/install.esd"

  msg="Extracting environment from ESD file"
  info "$msg..." && html "$msg..."

  index="2"
  /run/progress.sh "$bootWim" "$wimSize" "$msg ([P])..." &

  wimlib-imagex export "$iso" "$index" "$bootWim" \
    --compress=none --quiet || {
    ret=$?
    fKill "progress.sh"
    error "Adding WinPE failed ($ret)"
    return "$ret"
  }

  fKill "progress.sh"

  msg="Extracting setup from ESD file"
  info "$msg..."

  index="3"
  /run/progress.sh "$bootWim" "$wimSize" "$msg ([P])..." &

  wimlib-imagex export "$iso" "$index" "$bootWim" \
    --compress=none --boot --quiet || {
    ret=$?
    fKill "progress.sh"
    error "Adding Windows Setup failed ($ret)"
    return "$ret"
  }

  fKill "progress.sh"
  html "$msg..."

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    LABEL="CCCOMA_X64FRE_EN-US_DV9"
  else
    LABEL="CPBA_A64FRE_EN-US_DV9"
  fi

  index=""

  if [[ "${version,,}" == "http"* ]]; then

    # Direct ESD URLs have no catalog identity. Restrict automatic detection
    # to installable images because indexes 1-3 contain setup components.
    if ! installXml=$(xmlstarlet ed \
        -d '/WIM/IMAGE[number(@INDEX) < 4]' \
        <<< "$xml" 2>/dev/null); then
      error "Cannot read installable images from ESD file!"
      return 1
    fi

    checkPlatform "$installXml" || return

    output=$(detectVersion "$installXml") || return
    mapfile -t detected <<< "$output"

    index="${detected[1]:-}"

    if [ -z "$index" ]; then
      error "Failed to select an installation image from install.esd!"
      return 1
    fi

  else

    edition=$(getCatalog "$version" "name")

    if [ -z "$edition" ]; then
      error "Invalid VERSION specified, value \"$version\" is not recognized!"
      return 1
    fi

    for line in "${fields[@]:5}"; do

      IFS=$'\t' read -r image imgEdition <<< "$line"

      [[ ! "$image" =~ ^[0-9]+$ ]] && continue
      [[ "${imgEdition,,}" != "${edition,,}" ]] && continue

      index="$image"
      break

    done

    if [ -z "$index" ]; then
      error "Failed to find product '$edition' in install.esd!"
      return 1
    fi

  fi

  installSize=$(( size + installPad ))

  if ! rm -f -- "$dir/sources/install.wim" "$installWim"; then
    error "Failed to remove previous Windows installation image!"
    return 1
  fi

  # Reuse the downloaded solid ESD instead of exporting the selected image.
  # Both paths are below $TMP, so this is a same-filesystem rename.
  if ! mv -f -- "$iso" "$installWim"; then
    error "Failed to move downloaded ESD file into the installation media!"
    return 1
  fi

  # Remove all other images without rebuilding the solid-compressed resources.
  # Deleting in descending order leaves the selected edition at index 1.
  for (( image=count; image >= 1; image-- )); do

    (( image == index )) && continue

    wimlib-imagex delete "$installWim" "$image" --soft --quiet || {
      ret=$?
      error "Failed to remove image $image from install.esd!"
      return "$ret"
    }

  done

  result=$(wimlib-imagex info "$installWim" --xml 2>/dev/null |
    iconv -f UTF-16LE -t UTF-8 2>/dev/null) || {
    ret=$?
    error "Cannot verify the prepared install.esd file!"
    return "$ret"
  }

  if ! metadata=$(xmlstarlet sel -t \
      -v 'count(/WIM/IMAGE)' -n \
      -v 'count(/WIM/IMAGE[@INDEX="1"])' -n \
      -v 'normalize-space(/WIM/IMAGE[@INDEX="1"]/DESCRIPTION)' -n \
      <<< "$result" 2>/dev/null); then
    error "Cannot verify the prepared install.esd file!"
    return 1
  fi

  mapfile -t fields <<< "$metadata"

  resultCount="${fields[0]:-}"
  resultIndex="${fields[1]:-}"
  resultEdition="${fields[2]:-}"

  if [[ "$resultCount" != "1" ]] || [[ "$resultIndex" != "1" ]]; then
    error "Prepared install.esd does not contain exactly one image at index 1!"
    return 1
  fi

  if [[ "${version,,}" != "http"* ]] &&
      [[ "${resultEdition,,}" != "${edition,,}" ]]; then
    error "Prepared install.esd does not contain only '$edition' at index 1!"
    return 1
  fi

  return 0
}

normalizeBatch() {

  local file="$1"
  local bom tmp encoding

  [ ! -s "$file" ] && return 0

  bom=$(od -An -N2 -tx1 "$file" | tr -d ' \n') || return 1

  # Convert only BOM-marked UTF-16 files; unmarked ANSI and UTF-8 batch files
  # are deliberately left unchanged.
  case "$bom" in
    "fffe" ) encoding="UTF-16LE" ;;
    "feff" ) encoding="UTF-16BE" ;;
    * ) return 0 ;;
  esac

  if ! tmp=$(mktemp "${file}.XXXXXX"); then
    error "Failed to create temporary batch file!"
    return 1
  fi

  if ! tail -c +3 "$file" | iconv -f "$encoding" -t UTF-8 > "$tmp"; then
    rm -f "$tmp"
    error "Failed to convert $file from $encoding to UTF-8!"
    return 1
  fi

  if ! chmod --reference="$file" "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    error "Failed to replace batch file: $file"
    return 1
  fi

  return 0
}

reportBatchMatches() {

  local file="$1"
  local source="$2"
  local pattern="$3"
  local message="$4"
  local suggestion="$5"

  local matches line
  matches=$(grep -Pin "$pattern" "$file" || true)

  [ -n "$matches" ] || return 0

  warn "$message in $source:"

  while IFS= read -r line; do
    printf '  %s\n' "$line" >&2
  done <<< "$matches"

  printf '  %s\n\n' "$suggestion" >&2

  return 0
}

checkBatch() {

  local file="$1"

  local tmp output
  local matches line
  local enabled_rules

  [ -s "$file" ] || return 0

  if ! tmp=$(mktemp -d /tmp/blinter.XXXXXX); then
    warn "failed to create temporary Blinter directory."
    return 0
  fi

  local source="your install.bat file"
  [ -n "${COMMAND:-}" ] && source="your COMMAND variable"

  # Only check rules that indicate likely execution or behavioural failures.
  enabled_rules="E001,E002,E003,E004,E005,E006,E007,E008"
  enabled_rules+=",E009,E010,E011,E012,E013,E014,E015,E016"
  enabled_rules+=",E017,E018,E019,E020,E021,E022,E023,E024"
  enabled_rules+=",E025,E027,E028,E029,E030,E031,E032,E033,E034"
  enabled_rules+=",W004,W005,W013,W017,W021,W022,W034,W038,W040"

  if enabled "$DEBUG"; then
    if LC_ALL=C grep -Pq '[^\x09\x0D\x20-\x7E]' "$file"; then
      warn "non-ASCII characters were detected in $source and may not execute correctly in Windows Command Prompt."
    fi
  fi

  cat > "$tmp/blinter.ini" <<EOC
[general]
min_severity = warning
show_summary = false

[rules]
enabled_rules = $enabled_rules
EOC

  output=$(
    cd "$tmp"
    python3 -m blinter "$file" 2>&1 || true
  )

  # Remove header.
  output=$(
    awk '
      /^DETAILED ISSUES:/ {
        found = 1
        next
      }

      found && !started {
        if (/^-+$/) {
          started = 1
        }
        next
      }

      started {
        print
      }
    ' <<< "$output"
  )

  output="${output#"${output%%[!$'\r\n ']*}"}"
  output="${output%"${output##*[!$'\r\n ']}"}"

  if grep -Eq '^(ERROR|WARNING|SECURITY) LEVEL ISSUES:$' <<< "$output"; then

    warn "possible issues were detected in $source:"
    printf '\n%s\n\n' "$output" >&2
  fi

  rm -rf "$tmp" || true

  reportBatchMatches \
    "$file" \
    "$source" \
    '(?<!\\)\\host[.]lan[\\]' \
    "invalid single-backslash UNC path detected" \
    'Use "\\host.lan\Data\..." instead of "\host.lan\Data\...".'

  reportBatchMatches \
    "$file" \
    "$source" \
    '(?<![\\[:alnum:]._-])host[.]lan[\\]' \
    "UNC path without leading backslashes detected" \
    'Use "\\host.lan\Data\..." instead of "host.lan\Data\...".'

  reportBatchMatches \
    "$file" \
    "$source" \
    '//host[.]lan/' \
    "invalid forward-slash UNC path detected" \
    'Use "\\host.lan\Data\..." instead of "//host.lan/Data/...".'

  reportBatchMatches \
    "$file" \
    "$source" \
    '\\\\host[.]lan\\shared(?:[\\/]|$)' \
    "invalid Samba share name detected" \
    'The "/shared" folder is exposed to Windows as "\\host.lan\Data".'

  return 0
}

getBootLoadSize() {

  local iso="$1"
  local dir="$2"
  local desc="$3"

  local boot_info size value

  case "${DETECTED,,}" in

    "win2k"* | "winxp"* | "win2003"* )

      # NT 5.x media may not expose a reliable catalog sector count, so derive
      # it directly from the extracted boot image.
      if [ ! -s "$dir/$ETFS" ]; then
        error "Failed to locate file \"$ETFS\" in $desc ISO image!"
        return 1
      fi

      if ! size=$(stat -c%s "$dir/$ETFS"); then
        error "Failed to determine boot image size from $desc ISO!"
        return 1
      fi

      if (( size < 512 || size % 512 != 0 )); then
        error "Invalid boot image size found in $desc ISO!"
        return 1
      fi

      BOOT_LOAD_SIZE=$((size / 512)) ;;

    * )

      # Other legacy media use the El Torito Nsect value from the ISO catalog.
      if ! boot_info=$(isoinfo -d -i "$iso"); then
        error "Failed to read boot image information from $desc ISO!"
        return 1
      fi

      value=$(awk '/Nsect / { print $NF; exit }' <<< "$boot_info")

      if [ -z "$value" ]; then
        error "Failed to determine boot image load size from $desc ISO!"
        return 1
      fi

      if [[ ! "$value" =~ ^[[:xdigit:]]{1,4}$ ]]; then
        error "Invalid boot image load size found in $desc ISO!"
        return 1
      fi

      BOOT_LOAD_SIZE=$((16#$value)) ;;

  esac

  if (( BOOT_LOAD_SIZE < 1 || BOOT_LOAD_SIZE > 65535 )); then
    error "Invalid boot image load size found in $desc ISO!"
    return 1
  fi

  return 0
}

extractBootImage() {

  local iso="$1"
  local dir="$2"
  local desc="$3"

  local actual expected offset info

  ETFS="boot.img"

  [ -s "$dir/$ETFS" ] && return 0
  rm -f "$dir/$ETFS" || return 1

  if ! info=$(isoinfo -d -i "$iso"); then
    error "Failed to read boot image information from $desc ISO!"
    return 1
  fi

  offset=$(awk '/Bootoff / { print $NF; exit }' <<< "$info")

  if [ -z "$offset" ]; then
    error "Failed to determine boot image offset from $desc ISO!"
    return 1
  fi

  if [[ ! "$offset" =~ ^[0-9]+$ ]]; then
    error "Invalid boot image location found in $desc ISO!"
    return 1
  fi

  # isoinfo reports the boot offset in 2048-byte sectors, while dd below uses
  # 512-byte blocks, hence the factor of four.
  if ! dd "if=$iso" "of=$dir/$ETFS" bs=512 "count=$BOOT_LOAD_SIZE" "skip=$((offset * 4))" status=none; then

    rm -f "$dir/$ETFS" || true
    error "Failed to extract boot image from $desc ISO!"
    return 1
  fi

  expected=$((BOOT_LOAD_SIZE * 512))

  if ! actual=$(stat -c%s "$dir/$ETFS"); then
    rm -f "$dir/$ETFS" || true
    error "Failed to determine boot image size from $desc ISO!"
    return 1
  fi

  if (( actual != expected )); then
    rm -f "$dir/$ETFS" || true
    error "Failed to extract complete boot image from $desc ISO!"
    return 1
  fi

  return 0
}

buildImage() {

  local dir="$1"

  local cat="BOOT.CAT"
  local log="/run/shm/iso.log"
  local base size desc rc=0

  if [ -f "$BOOT" ]; then
    error "File $BOOT does already exist?!" && return 1
  fi

  base=$(basename "$BOOT")
  local out="$TMP/${base%.*}.tmp"

  if ! rm -f "$out"; then
    error "Failed to remove temporary ISO image: $out"
    return 1
  fi

  desc=$(printVariant "$DETECTED" "ISO")

  local msg="Building $desc image"
  [[ "${ISO,,}" == *.esd ]] && msg+=" from ESD file"
  info "$msg..." && html "$msg..."

  [ -z "$LABEL" ] && LABEL="Windows"

  if [ ! -f "$dir/$ETFS" ] || [ ! -s "$dir/$ETFS" ]; then
    error "Failed to locate file \"$ETFS\" in ISO image!" && return 1
  fi

  if ! size=$(du -b --max-depth=0 "$dir" | cut -f1); then
    error "Failed to calculate the size of directory \"$dir\"!"
    return 1
  fi

  checkFreeSpace "$TMP" "$size" || return 1

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]] && [ -z "${BOOT_LOAD_SIZE:-}" ]; then
    if [[ "${DETECTED,,}" != "win9"* && "${DETECTED,,}" != "winnt4" ]]; then
      error "Failed to determine the boot image load size!"
      return 1
    fi
  fi

  /run/progress.sh "$out" "$size" "$msg ([P])..." &

  local -a args=(
    -o "$out"
    -b "$ETFS"
  )

  local -a name_args=(
    -J
    -l
    -D
    -N
    -joliet-long
    -relaxed-filenames
    -V "${LABEL::30}"
  )

  # Use separate layouts for modern hybrid media, NT 5.x legacy media, Win9x,
  # and other legacy releases because their El Torito requirements differ.
  if [[ "${BOOT_MODE,,}" != "windows_legacy" ]]; then

    args+=(
      -no-emul-boot
      -c "$cat"
      -iso-level 4
      "${name_args[@]}"
      -udf
      -boot-info-table
      -eltorito-alt-boot
      -eltorito-boot "$EFISYS"
      -no-emul-boot
      -allow-limited-size
    )

  else

    case "${DETECTED,,}" in

      "win2k"* | "winxp"* | "win2003"* )

        args+=(
          -no-emul-boot
          -boot-load-seg 1984
          -boot-load-size "$BOOT_LOAD_SIZE"
          -c "$cat"
          -iso-level 2
          "${name_args[@]}"
        ) ;;

      "win9"* | "winnt4" )

        args+=(
          -J
          -r
          -V "${LABEL::30}"
        ) ;;

      * )

        args+=(
          -no-emul-boot
          -boot-load-size "$BOOT_LOAD_SIZE"
          -c "$cat"
          -iso-level 2
          "${name_args[@]}"
          -udf
          -allow-limited-size
        ) ;;

    esac

  fi

  genisoimage "${args[@]}" -quiet "$dir" 2> "$log" || rc=$?

  fKill "progress.sh"

  if (( rc != 0 )); then
    [ -s "$log" ] && echo "$(<"$log")"
    error "Failed to build image!"
    return "$rc"
  fi

  local err=""
  local hide="Warning: creating filesystem that does not conform to ISO-9660."

  [ -s "$log" ] && err="$(<"$log")"

  # UDF hybrid media intentionally triggers this genisoimage warning.
  if [ -n "$err" ] && [[ "$err" != "$hide" ]]; then
    echo "$err"
  fi

  mv -f "$out" "$BOOT" || return

  if ! setOwner "$BOOT"; then
    warn "Failed to set the owner for \"$BOOT\" !"
  fi

  return 0
}

return 0
