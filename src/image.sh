#!/usr/bin/env bash
set -Eeuo pipefail

getVersionPriority() {

  local id="${1,,}"
  local base="${2,,}"

  local entry priority patterns pattern
  local result="other" score best_score=-1
  local -a order=()

  id="${id%-eval}"

  mapfile -t order < <(getEditionOrder "$base")

  local edition="${id#"$base"}"
  edition="${edition#-}"

  # Use the most specific matching pattern. This prevents broad patterns
  # such as enterprise-* from taking precedence over enterprise-iot-*.
  for entry in "${order[@]}"; do

    IFS='|' read -r _ priority patterns <<< "$entry"

    for pattern in $patterns; do

      if [ "$pattern" = "@default" ]; then
        [ -z "$edition" ] || continue
        score=1
      elif [[ "$pattern" == *"*" ]]; then
        local prefix="${pattern%\*}"
        [[ "$edition" == "$prefix"* ]] || continue
        score="${#pattern}"
      elif [ "$edition" = "$pattern" ]; then
        score="${#pattern}"
      else
        continue
      fi

      if (( score > best_score )); then
        result="$priority"
        best_score="$score"
      fi

    done

  done

  echo "$result"
  return 0
}

getVersions() {

  local xml="$1"
  local versions_name="$2"
  local bases_name="$3"
  local groups_name="$4"
  local indexes_name="$5"

  local -n bases_ref="$bases_name"
  local -n groups_ref="$groups_name"
  local -n indexes_ref="$indexes_name"
  local -n versions_ref="$versions_name"

  local platform image_count records record_count=0
  local image_index display product image edition_id
  local install_type flags candidate candidate_id
  local candidate_base evaluation key name structured
  local separator=$'\x1f'

  bases_ref=()
  groups_ref=()
  indexes_ref=()
  versions_ref=()

  platform=$(getPlatform "$xml") || return 1

  image_count=$(xmlstarlet sel -T -t -v 'count(/WIM/IMAGE)' - 2>/dev/null <<< "$xml") || return 1

  if [[ ! "$image_count" =~ ^[0-9]+$ ]]; then
    error "Invalid image count in WIM metadata: '$image_count'"
    return 1
  fi

  (( image_count > 0 )) || return 0

  # Keep one compact record per image. XML 1.0 cannot contain U+001F, so it
  # can safely separate fields while all edition logic remains in Bash.
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

    ((record_count += 1))

    [ -n "$image_index" ] || continue

    if [[ ! "$image_index" =~ ^[1-9][0-9]*$ ]]; then
      warn "Invalid image index in WIM metadata: '$image_index'"
      continue
    fi

    candidate_id=""
    candidate_base=""

    # NAME normally contains the most precise edition identifier (including
    # Server Core), while DISPLAYNAME is the best fallback for other images.
    for candidate in "$image" "$display" "$product"; do

      [[ "$candidate" == *"Operating System"* ]] && continue
      [ -n "$candidate" ] || continue

      candidate_base=$(fromName "$candidate" "$platform")
      candidate_id=$(getVersion "$candidate" "$platform")

      [ -n "$candidate_base" ] && [ -n "$candidate_id" ] && break

    done

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

    # Some client media use the same friendly name-derived ID for distinct
    # editions. Preserve the established unsuffixed Pro ID, and use the
    # structured edition metadata only to disambiguate a collision.
    if [[ -v "indexes_ref[$key]" ]]; then
      structured=""

      case "${candidate_base,,}" in
        "winvista"* | "win7"* | "win8"* | "win10"* | "win11"* )
          structured=$(normalizeEditionID "${edition_id:-${flags:-}}" "$candidate_base") || return 1
          ;;
        "win20"* )
          structured=$(normalizeServerEditionID "${flags:-$edition_id}") || return 1

          # Some media use the same EDITIONID for Core and Desktop images.
          # INSTALLATIONTYPE provides the structural distinction without
          # requiring a hardcoded marketing name.
          if [[ "${install_type,,}" == *"core"* && "$structured" != *"-core" ]]; then
            structured+="-core"
          fi
          ;;
      esac

      if [ -n "$structured" ]; then
        candidate_id="$candidate_base-$structured$evaluation"
        key="${candidate_id,,}"
      fi
    fi

    if [[ -v "indexes_ref[$key]" ]]; then
      warn "Duplicate image identity '$candidate_id' at indexes ${indexes_ref[$key]} and $image_index"
      continue
    fi

    indexes_ref["$key"]="$image_index"
    versions_ref+=( "$candidate_id" )
    bases_ref+=( "$candidate_base" )
    groups_ref+=( "$(getVersionPriority "$candidate_id" "$candidate_base")" )

  done <<< "$records"

  if (( record_count != image_count )); then
    error "Expected $image_count image records in WIM metadata, found $record_count!"
    return 1
  fi

  return 0
}

selectVersion() {

  local versions_name="$1"
  local indexes_name="$2"
  local preferred_name="$3"
  local result_name="$4"
  local index_name="$5"

  local -a candidates=()
  local -n version_list="$versions_name"
  local -n index_map="$indexes_name"
  local -n preference_list="$preferred_name"
  local -n selected_version="$result_name"
  local -n selected_image_index="$index_name"
  local wanted candidate match

  # A detected edition is only selectable when a matching answer file can
  # actually be staged for it.
  for wanted in "${preference_list[@]}"; do

    [ -n "$wanted" ] || continue
    mapfile -t candidates < <(getCompatibleVersions "$wanted")

    for candidate in "${candidates[@]}"; do

      match=$(hasVersion "$candidate" "${version_list[@]}") || continue
      hasAnswerFile "$match" || continue

      local key="${match,,}"
      selected_version="$match"
      selected_image_index="${index_map[$key]}"
      return 0

    done

  done

  return 1
}

selectEdition() {

  local versions_name="$1"
  local bases_name="$2"
  local groups_name="$3"
  local indexes_name="$4"
  local suggested="$5"
  local result_name="$6"
  local index_name="$7"
  local normalize_name="$8"
  local order_name="$9"

  local -A seen=()
  local -a preferred=()
  local -n edition_bases="$bases_name"
  local -n edition_order="$order_name"
  local -n edition_groups="$groups_name"
  local -n edition_versions="$versions_name"
  local base edition entry suffix priority i

  # Selection precedence is explicit EDITION, source suggestion, canonical
  # edition order, then noncanonical editions from the same priority groups.
  if [ -n "$EDITION" ]; then

    for base in "${edition_bases[@]}"; do
      edition=$("$normalize_name" "$EDITION" "$base") || return 1
      preferred+=("$base${edition:+-$edition}")
    done

    if selectVersion "$versions_name" "$indexes_name" preferred "$result_name" "$index_name"; then
      return 0
    fi

    warn "edition '$EDITION' is not supported by this image, using automatic selection instead."
  fi

  if [ -n "$suggested" ]; then

    preferred=("$suggested")

    if selectVersion "$versions_name" "$indexes_name" preferred "$result_name" "$index_name"; then
      return 0
    fi

  fi

  # First try each canonical edition in its configured order.
  preferred=()

  for entry in "${edition_order[@]}"; do

    IFS='|' read -r suffix _ _ <<< "$entry"

    for base in "${edition_bases[@]}"; do
      preferred+=("$base$suffix")
    done

  done

  if selectVersion "$versions_name" "$indexes_name" preferred "$result_name" "$index_name"; then
    return 0
  fi

  # Then try noncanonical editions from the same preference groups.
  seen=()
  preferred=()

  for entry in "${edition_order[@]}"; do

    IFS='|' read -r _ priority _ <<< "$entry"

    [[ -v "seen[$priority]" ]] && continue
    seen["$priority"]="Y"

    for ((i=0;i<${#edition_versions[@]};i++)); do
      [[ "${edition_groups[$i]}" == "$priority" ]] || continue
      preferred+=("${edition_versions[$i]}")
    done

  done

  selectVersion "$versions_name" "$indexes_name" preferred "$result_name" "$index_name"
}

detectVersion() {

  local xml="$1"
  local suggested="${2:-}"

  local -a bases=()
  local -a groups=()
  local -a versions=()
  local -A image_indexes=()
  local -a selection_order=()
  local result="" index=""

  getVersions "$xml" versions bases groups image_indexes || return 1

  if [ "${#versions[@]}" -eq 0 ]; then
    printf '%s\n%s\n' "$result" "$index"
    return 0
  fi

  local normalize="normalizeEditionID"

  case "${bases[0],,}" in
    "win20"* )
      normalize="normalizeServerEditionID" ;;
  esac

  mapfile -t selection_order < <(getEditionOrder "${bases[0]}")

  if selectEdition versions bases groups image_indexes "$suggested" result index "$normalize" selection_order; then
    printf '%s\n%s\n' "$result" "$index"
    return 0
  fi

  # Keep the first detected image identity when no edition with a usable answer
  # file was found, so manual and generic fallback handling can still continue.
  result="${versions[0]}"
  local key="${result,,}"
  index="${image_indexes[$key]}"

  printf '%s\n%s\n' "$result" "$index"
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
    lang=$(xmlstarlet sel -T -t -v "normalize-space(string(($path)[1]))" - 2>/dev/null <<< "$xml") || lang=""

    [ -n "$lang" ] && break
  done

  if [ -z "$lang" ]; then
    warn "Language could not be detected from ISO!"
    return 0
  fi

  culture=$(getLanguage "$lang" "culture") || return 1

  if [ -n "$culture" ]; then
    LANGUAGE="$lang"
    return 0
  fi

  warn "Invalid language detected: \"$lang\""
  return 0
}

getImageSize() {

  local stage="$1"
  local folder="${2:-}"

  local size bytes path
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

    if ! read -r bytes _ < <(du -Llsb --apparent-size -- "$path"); then
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

hasVersion() {

  local wanted="$1"
  shift

  local actual

  for actual in "$@"; do
    [[ "${actual,,}" == "${wanted,,}" ]] || continue
    echo "$actual"
    return 0
  done

  return 1
}

getCompatibleVersions() {

  local wanted="$1"

  printf '%s\n' "$wanted"

  # Treat normal and Evaluation variants of the same edition as compatible.
  # The exact requested variant is always checked first.
  if [[ "${wanted,,}" == *"-eval" ]]; then
    printf '%s\n' "${wanted%-eval}"
  else
    printf '%s\n' "$wanted-eval"
  fi
}

checkPlatform() {

  local xml="$1"
  local platform

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
      if [[ "${platform,,}" == "x64" || "${platform,,}" == "x86" ]]; then
        return 0
      fi ;;
    "arm64" )
      if [[ "${platform,,}" == "arm64" ]]; then
        return 0
      fi ;;
    * )
      error "Unsupported container platform: $PLATFORM"
      return 1 ;;
  esac

  error "You cannot boot ${platform^^} images on a $PLATFORM CPU!"
  return 1
}

getPlatform() {

  local xml="$1"

  local image_count invalid_count 
  local x86 x64 arm64 unknown value
  local platform="" count=0 output
  local -a counts=()

  if ! output=$(xmlstarlet sel \
    -T -t \
    -v 'count(/WIM/IMAGE)' -n \
    -v 'count(/WIM/IMAGE[count(WINDOWS/ARCH) != 1])' -n \
    -v 'count(/WIM/IMAGE/WINDOWS/ARCH[normalize-space(.)="0"])' -n \
    -v 'count(/WIM/IMAGE/WINDOWS/ARCH[normalize-space(.)="9"])' -n \
    -v 'count(/WIM/IMAGE/WINDOWS/ARCH[normalize-space(.)="12"])' -n \
    -v 'count(/WIM/IMAGE/WINDOWS/ARCH[normalize-space(.)!="0" and normalize-space(.)!="9" and normalize-space(.)!="12"])' -n \
    - 2>/dev/null <<< "$xml"); then
    error "Failed to read architecture metadata from WIM image!"
    return 1
  fi

  mapfile -t counts <<< "$output"

  if (( ${#counts[@]} != 6 )); then
    error "Failed to read architecture counts from WIM metadata!"
    return 1
  fi

  for value in "${counts[@]}"; do
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
      error "Invalid architecture count in WIM metadata: '$value'"
      return 1
    fi
  done

  image_count="${counts[0]}"
  invalid_count="${counts[1]}"
  x86="${counts[2]}"
  x64="${counts[3]}"
  arm64="${counts[4]}"
  unknown="${counts[5]}"

  if (( image_count == 0 )); then
    error "No images were found in WIM metadata!"
    return 1
  fi

  if (( invalid_count > 0 )); then
    error "Missing or duplicate architecture metadata in WIM image!"
    return 1
  fi

  if (( unknown > 0 )); then
    error "Unsupported architecture value in WIM metadata!"
    return 1
  fi

  (( x86 > 0 )) && ((count += 1))
  (( x64 > 0 )) && ((count += 1))
  (( arm64 > 0 )) && ((count += 1))

  if (( count > 1 )); then
    platform="mixed"
  elif (( x86 > 0 )); then
    platform="x86"
  elif (( x64 > 0 )); then
    platform="x64"
  elif (( arm64 > 0 )); then
    platform="arm64"
  else
    error "Failed to determine architecture from WIM metadata!"
    return 1
  fi

  echo "$platform"
  return 0
}

canUseSetupImage() {

  local id="$1"
  local iso="$2"

  supportsXML "$id" || return 1
  [[ "${iso,,}" == *".esd" ]] && return 1

  return 0
}

createImageDirectory() {

  local image="$1"
  local directory="$2"

  # Treat an existing directory as success; create it only when mdir cannot
  # already resolve it.
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

  # Build and verify a temporary FAT32 image before replacing the active setup
  # image, so a partial write never becomes boot media.
  rm -f -- "$tmp" || return 1

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

detectLegacy() {

  local dir="$1"

  local marker

  [[ "${PLATFORM,,}" == "x64" ]] || return 1

  # Legacy media is identified from setup marker files rather than WIM
  # metadata. The order is intentional because several releases share markers.
  marker=$(find "$dir" -maxdepth 1 -type d -iname 'ia64' -print -quit) || return 1

  if [ -n "$marker" ]; then
    error "Windows IA-64 (Itanium) images are not supported by this container!"
    return 1
  fi

  marker=$(find "$dir" -maxdepth 1 -type d -iname WIN95 -print -quit) || return 1

  if [ -n "$marker" ]; then
    DETECTED="win95"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type d -iname WIN98 -print -quit) || return 1

  if [ -n "$marker" ]; then
    DETECTED="win98"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type d -iname WIN9X -print -quit) || return 1

  if [ -n "$marker" ]; then
    DETECTED="win9x"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type f \
    \( \
      -iname CDROM_W.40 -o \
      -iname CDROM_S.40 -o \
      -iname CDROM_TS.40 \
    \) \
    -print -quit) || return 1

  if [ -n "$marker" ]; then
    DETECTED="winnt4"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type f -iname CDROM_NT.5 -print -quit) || return 1

  if [ -n "$marker" ]; then

    marker=$(find "$dir" -maxdepth 1 -type f \
      \( \
        -iname CDROM_IA.5 -o \
        -iname CDROM_ID.5 -o \
        -iname CDROM_IP.5 -o \
        -iname CDROM_IS.5 \
      \) \
      -print -quit) || return 1

    if [ -n "$marker" ]; then
      DETECTED="win2k"
      return 0
    fi

  fi

  # WIN51 identifies the NT 5.1/5.2 media family; the companion marker then
  # distinguishes XP x86, XP x64, and Server 2003.
  marker=$(find "$dir" -maxdepth 1 -iname WIN51 -print -quit) || return 1
  [ -n "$marker" ] || return 1

  marker=$(find "$dir" -maxdepth 1 -type f -iname WIN51AP -print -quit) || return 1

  if [ -n "$marker" ]; then
    DETECTED="winxpx64"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type f \
    \( \
      -iname WIN51IC -o \
      -iname WIN51IP -o \
      -iname setupxp.htm \
    \) \
    -print -quit) || return 1

  if [ -n "$marker" ]; then
    DETECTED="winxpx86"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type f \
    \( \
      -iname WIN51IS -o \
      -iname WIN51IA -o \
      -iname WIN51IB -o \
      -iname WIN51ID -o \
      -iname WIN51IL -o \
      -iname WIN51AA -o \
      -iname WIN51AD -o \
      -iname WIN51AS -o \
      -iname WIN51MA -o \
      -iname WIN51MD -o \
      -iname WIN51MP \
    \) \
    -print -quit) || return 1

  if [ -n "$marker" ]; then
    DETECTED="win2003r2"
    return 0
  fi

  return 1
}

detectReactOS() {

  local dir="$1"

  local marker

  marker=$(find "$dir" -maxdepth 2 -type f \
    \( -ipath '*/reactos/reactos.inf' -o -ipath '*/reactos/unattend.inf' \) -print -quit) || return 1

  [ -n "$marker" ] || return 1

  DETECTED="reactos"
  return 0
}

resolveImage() {

  local version="$1"

  XML=""
  FB="falling back to manual installation!"

  [ -z "$DETECTED" ] || return 0

  # Reused and arbitrary URL media must be inspected because their actual
  # contents may no longer match the requested VERSION.
  [ -z "${REUSED_ISO:-}" ] || return 1
  [[ "${version,,}" != "http"* ]] || return 1

  # Only direct-boot custom media can safely bypass content detection.
  if [ -n "$CUSTOM" ]; then
    supportsUnattended "$version" && return 1
    DETECTED="$version"
    return 0
  fi

  local file="/run/assets/$version.xml"

  if [ -s "$file" ]; then
    DETECTED="$version"
    return 0
  fi

  # Evaluation media may reuse the normal edition's answer-file template.
  if [[ "${version,,}" == *"-eval" ]]; then
    local source="/run/assets/${version%-eval}.xml"

    if [ -s "$source" ]; then
      DETECTED="$version"
      return 0
    fi
  fi

  return 1
}

setImage() {

  supportsXML "${DETECTED,,}" || return 0

  setXML "" && return 0
  enabled "$MANUAL" && return 0

  # A missing answer file is a supported manual-install path, not a hard media
  # failure.
  MANUAL="Y"

  local desc
  desc=$(printEdition "$DETECTED" "this version") || return 1

  warn "the answer file for $desc was not found ($DETECTED.xml), $FB."
  return 0
}

findIsoImage() {

  local iso="$1"

  local path

  # Prefer install.wim when both payload forms are present.
  for path in /sources/install.wim /sources/install.esd; do

    if udfread stat --ignore-case "$iso" "$path" >/dev/null 2>&1; then

      printf '%s' "$path"
      return 0
    fi

  done

  return 1
}

readWimHeader() {

  local iso="$1"
  local image="$2"

  local size signature
  local header="$TMP/wim-header.bin"

  rm -f -- "$header" || return 1

  # Read only the fixed WIM header so metadata can be located without
  # extracting install.wim or install.esd from the ISO.
  if ! udfread range --ignore-case -o "$header" "$iso" "$image" 0 208 >/dev/null 2>&1 ||
      ! size=$(stat -c%s -- "$header") || (( size != 208 )) ||
      ! signature=$(od -An -N8 -tx1 "$header" | tr -d ' \n') || [[ "$signature" != "4d5357494d000000" ]]; then

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

  local raw result root xml_count
  local header_size version
  local part_number total_parts image_count
  local xml_offset xml_size xml_original xml_flags
  local -a bytes=() values=()

  [ -f "$header" ] || return 1
  raw=$(od -An -v -N208 -tu1 -- "$header") || return 1

  read -r -a bytes <<< "${raw//$'\n'/ }"
  (( ${#bytes[@]} == 208 )) || return 1

  # Validate the MSWIM\0\0\0 signature.
  (( bytes[0] == 77 &&
     bytes[1] == 83 &&
     bytes[2] == 87 &&
     bytes[3] == 73 &&
     bytes[4] == 77 &&
     bytes[5] == 0 &&
     bytes[6] == 0 &&
     bytes[7] == 0 )) || return 1

  # Header size at offset 0x08.
  header_size=$(( \
    bytes[8] |
    bytes[9] << 8 |
    bytes[10] << 16 |
    bytes[11] << 24
  ))

  (( header_size == 208 )) || return 1

  # WIM version at offset 0x0c.
  version=$(( \
    bytes[12] |
    bytes[13] << 8 |
    bytes[14] << 16 |
    bytes[15] << 24
  ))

  (( version == 0x10d00 || version == 0x0e00 )) || return 1

  # Split-WIM information at offsets 0x28 and 0x2a.
  part_number=$((bytes[40] | bytes[41] << 8))
  total_parts=$((bytes[42] | bytes[43] << 8))

  (( part_number > 0 &&
     total_parts > 0 &&
     part_number <= total_parts )) || return 1

  # Image count at offset 0x2c.
  image_count=$(( \
    bytes[44] |
    bytes[45] << 8 |
    bytes[46] << 16 |
    bytes[47] << 24
  ))

  (( image_count > 0 && image_count <= 65535 )) || return 1

  result=$(parseWimHeader "$iso" "$image" "$header") || return 1
  mapfile -t values <<< "$result"
  (( ${#values[@]} == 4 )) || return 1
  xml_offset="${values[0]}"
  xml_size="${values[1]}"
  xml_original="${values[2]}"
  xml_flags="${values[3]}"

  [[ "$xml_offset" =~ ^[0-9]+$ &&
     "$xml_size" =~ ^[0-9]+$ &&
     "$xml_original" =~ ^[0-9]+$ &&
     "$xml_flags" =~ ^[0-9]+$ ]] || return 1

  (( xml_size > 0 &&
     xml_original > 0 &&
     xml_size == xml_original &&
     xml_size % 2 == 0 )) || return 1

  # These resource forms cannot be decoded as a direct UTF-16LE byte range:
  #
  # 0x04: compressed
  # 0x08: spanned
  # 0x10: solid
  #
  # The metadata flag 0x02 is expected and deliberately allowed.
  (( !(xml_flags & 0x1c) )) || return 1

  result=$(udfread range --ignore-case "$iso" "$image" "$xml_offset" "$xml_size" \
           2>/dev/null | iconv -f UTF-16LE -t UTF-8 2>/dev/null
  ) || {
    local rc=$?

    if (( rc >= 129 )); then
      exit "$rc"
    fi

    return 1
  }

  [ -n "$result" ] || return 1

  local metadata separator=$'\x1f'

  metadata=$(xmlstarlet sel \
    -T -t \
    -v 'local-name(/*)' -o "$separator" \
    -v 'count(/*[local-name()="WIM"]/*[local-name()="IMAGE"])' \
    - 2>/dev/null <<< "$result") || return 1

  IFS="$separator" read -r root xml_count <<< "$metadata"

  [ "$root" = "WIM" ] || return 1
  [[ "$xml_count" =~ ^[0-9]+$ ]] || return 1
  (( xml_count == image_count )) || return 1

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
    return 1
  fi

  if ! raw=$(od -An -v -j8 -N88 -tu1 -- "$header"); then
    return 1
  fi

  read -r -a bytes <<< "${raw//$'\n'/ }"

  if (( ${#bytes[@]} != 88 )); then
    return 1
  fi

  local i

  # The WIM header size is a 32-bit little-endian value at offset 0x08.
  for ((i=3; i>=0; i--)); do
    header_size=$((header_size * 256 + bytes[i]))
  done

  if (( header_size != 208 )); then
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
    return 1
  fi

  for ((i=79; i>=72; i--)); do
    parsed_offset=$((parsed_offset * 256 + bytes[i]))
  done

  # The uncompressed XML size is an unsigned 64-bit value at offset 0x58.
  if (( bytes[87] >= 128 )); then
    return 1
  fi

  for ((i=87; i>=80; i--)); do
    parsed_original=$((parsed_original * 256 + bytes[i]))
  done

  if (( parsed_size <= 0 || parsed_offset < header_size || parsed_original <= 0 )); then
    return 1
  fi

  if ! details=$(udfread stat --ignore-case "$iso" "$image" 2>/dev/null); then
    return 1
  fi

  image_size=$(sed -n 's/^Size: \([0-9][0-9]*\) bytes$/\1/p' <<< "$details")

  if [[ ! "$image_size" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if (( parsed_offset > image_size || parsed_size > image_size - parsed_offset )); then
    return 1
  fi

  printf '%s\n' "$parsed_offset" "$parsed_size" "$parsed_original" "$parsed_flags"

  return 0
}

findImage() {

  local dir="$1"
  local sources result

  sources=$(find "$dir" -maxdepth 1 -type d -iname sources -print -quit) || return 1

  if [ ! -d "$sources" ]; then
    warn "failed to locate 'sources' folder in ISO image, $FB"
    return 1
  fi

  result=$(find "$sources" -maxdepth 1 -type f \( -iname install.wim -or -iname install.esd \) -print -quit) || return 1

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

  result=$(wimlib-imagex info -xml "$wim" | iconv -f UTF-16LE -t UTF-8) || {
    local rc=$?

    if (( rc >= 129 )); then
      exit "$rc"
    fi

    result=""
  }

  if [ -z "$result" ]; then
    warn "failed to read Windows image information, $FB"
    return 1
  fi

  printf '%s' "$result"
  return 0
}

getSuggestion() {

  [ -z "$CUSTOM" ] || return 0
  [ -n "${REUSED_ISO:-}" ] || return 0

  # A reused ISO may still correspond to the originally requested catalog
  # version, but the suggestion remains only a preference during detection.
  echo "${SUGGEST:-}"
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

  local msg="Failed to determine Windows version from image"

  # Unknown media can continue when a custom answer file or manual mode already
  # provides the required installation path; otherwise force manual fallback.
  if setXML "" || enabled "$MANUAL"; then
    info "${msg}!"
  else
    MANUAL="Y"
    warn "${msg}, $FB."
  fi

  return 0
}

describeImage() {

  local info_xml="$1"
  local index="$2"

  local result
  result=$(printEdition "$DETECTED" "$DETECTED" "Y") || return 1

  detectLanguage "$info_xml" "$index" || return 1

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

  # Prefer the exact answer file, then a family-level fallback. Manual mode is
  # the final supported path when neither can be generated.
  setXML "" "$index" && return 0

  if [[ "$DETECTED" == "win81x86"* || "$DETECTED" == "win10x86"* ]]; then
    error "The 32-bit version of $desc is not supported!"
    exit 67
  fi

  local msg="the answer file for $desc was not found ($DETECTED.xml)"
  local fallback="/run/assets/${DETECTED%%-*}.xml"

  if setXML "$fallback" "$index"; then
    if ! enabled "$MANUAL"; then
      warn "${msg}."
    fi
    return 0
  fi

  enabled "$MANUAL" && return 0

  MANUAL="Y"
  warn "${msg}, $FB."

  return 0
}

detectImageInfo() {

  local image_info="$1"

  local desc suggested index

  checkPlatform "$image_info" || exit 67

  suggested=$(getSuggestion) || return 1

  local output
  output=$(detectVersion "$image_info" "$suggested") || return 1

  local -a detected=()
  mapfile -t detected <<< "$output"

  DETECTED="${detected[0]:-}"
  index="${detected[1]:-}"

  validateEdition || return 1

  if [ -z "$DETECTED" ]; then
    unknownImage || return 1
    return 0
  fi

  desc=$(describeImage "$image_info" "$index") || return 1
  info "Detected: $desc"

  configureImage "$index" "$desc" || return 1

  return 0
}

detectIsoImage() {

  local iso="$1"

  local image header image_info

  # Return 1 when direct ISO inspection is unavailable so the caller may fall
  # back to extraction; return 2 when metadata was read but configuration failed.

  image=$(findIsoImage "$iso") || return 1
  header=$(readWimHeader "$iso" "$image") || return 1
  image_info=$(readIsoImageInfo "$iso" "$image" "$header") || return 1

  info "Detecting version from ISO image..."
  detectImageInfo "$image_info" || return 2

  return 0
}

detectImage() {

  local dir="$1"

  local desc

  info "Detecting version from ISO image..."

  # Marker-based legacy and ReactOS detection must run before looking for a WIM.
  if detectLegacy "$dir" || detectReactOS "$dir"; then
    desc=$(printEdition "$DETECTED" "$DETECTED" "Y") || return 1
    info "Detected: $desc"
    return 0
  fi

  local wim
  wim=$(findImage "$dir") || return 1

  local image_info
  image_info=$(readImageInfo "$wim") || return 1

  detectImageInfo "$image_info"
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

      BOOT_LOAD_SIZE=$((size / 512))
      ;;

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

      if [[ ! "$value" =~ ^[0-9]+$ ]] || [ "${#value}" -gt 5 ]; then
        error "Invalid boot image load size found in $desc ISO!"
        return 1
      fi

      BOOT_LOAD_SIZE=$((10#$value))
      ;;
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

  local offset info

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

  if [ ! -s "$dir/$ETFS" ]; then
    rm -f "$dir/$ETFS" || true
    error "Failed to locate file \"$ETFS\" in $desc ISO image!"
    return 1
  fi

  return 0
}

buildImage() {

  local dir="$1"

  local cat="BOOT.CAT"
  local log="/run/shm/iso.log"
  local base size desc failed=""

  if [ -f "$BOOT" ]; then
    error "File $BOOT does already exist?!" && return 1
  fi

  base=$(basename "$BOOT")
  local out="$TMP/${base%.*}.tmp"
  rm -f "$out"

  desc=$(printVariant "$DETECTED" "ISO")

  local msg="Building $desc image"
  [[ "${ISO,,}" == *.esd ]] && msg+=" from ESD file"
  info "$msg..." && html "$msg..."

  [ -z "$LABEL" ] && LABEL="Windows"

  if [ ! -f "$dir/$ETFS" ] || [ ! -s "$dir/$ETFS" ]; then
    error "Failed to locate file \"$ETFS\" in ISO image!" && return 1
  fi

  if [[ "${BOOT_MODE,,}" == "windows_legacy" &&
    "${DETECTED,,}" != "win9"* &&
    -z "${BOOT_LOAD_SIZE:-}" ]]; then
    error "Failed to determine the boot image load size!"
    return 1
  fi

  if ! size=$(du -b --max-depth=0 "$dir" | cut -f1); then
    error "Failed to calculate the size of directory \"$dir\"!"
    return 1
  fi

  checkFreeSpace "$TMP" "$size" || return 1

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

      "win9"* )

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

  if ! genisoimage "${args[@]}" -quiet "$dir" 2> "$log"; then
    failed="y"
  fi

  fKill "progress.sh"

  if [ -n "$failed" ]; then
    [ -s "$log" ] && echo "$(<"$log")"
    error "Failed to build image!" && return 1
  fi

  local err=""
  local hide="Warning: creating filesystem that does not conform to ISO-9660."

  [ -s "$log" ] && err="$(<"$log")"

  # UDF hybrid media intentionally triggers this genisoimage warning.
  if [ -n "$err" ] && [[ "$err" != "$hide" ]]; then
    echo "$err"
  fi

  mv -f "$out" "$BOOT" || return 1

  if ! setOwner "$BOOT"; then
    warn "Failed to set the owner for \"$BOOT\" !"
  fi

  return 0
}

return 0
