#!/usr/bin/env bash
set -Eeuo pipefail

getPlatform() {

  local xml="$1"
  local platform="x64"
  local x86 x64 arm64 count=0

  x86=$(xmllint --nonet --xpath 'count(/WIM/IMAGE/WINDOWS/ARCH[text()="0"])' - 2>/dev/null <<< "$xml") || x86=0
  x64=$(xmllint --nonet --xpath 'count(/WIM/IMAGE/WINDOWS/ARCH[text()="9"])' - 2>/dev/null <<< "$xml") || x64=0
  arm64=$(xmllint --nonet --xpath 'count(/WIM/IMAGE/WINDOWS/ARCH[text()="12"])' - 2>/dev/null <<< "$xml") || arm64=0

  (( x86 > 0 )) && ((count++))
  (( x64 > 0 )) && ((count++))
  (( arm64 > 0 )) && ((count++))

  if (( count > 1 )); then
    platform="mixed"
  elif (( x86 > 0 )); then
    platform="x86"
  elif (( arm64 > 0 )); then
    platform="arm64"
  fi

  echo "$platform"
  return 0
}

checkPlatform() {

  local xml="$1"
  local platform compat

  platform=$(getPlatform "$xml")

  case "${platform,,}" in
    "x86" ) compat="x64" ;;
    "x64" ) compat="$platform" ;;
    "arm64" ) compat="$platform" ;;
    "mixed" )
      error "Windows images with mixed architectures are not supported!"
      return 1
      ;;
    * ) compat="${PLATFORM,,}" ;;
  esac

  [[ "${compat,,}" == "${PLATFORM,,}" ]] && return 0

  error "You cannot boot ${platform^^} images on a $PLATFORM CPU!"
  return 1
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
  local result_name="$2"
  local -n result_ref="$result_name"

  result_ref=("$wanted")

  # Treat normal and Evaluation variants of the same edition as compatible.
  # The exact requested variant is always checked first.
  if [[ "${wanted,,}" == *"-eval" ]]; then
    result_ref+=("${wanted%-eval}")
  else
    result_ref+=("$wanted-eval")
  fi
}

hasAnswerFile() {

  local id="$1"
  local file="/run/assets/$id.xml"

  [ -s "$file" ] && return 0

  if [[ "${id,,}" == *"-eval" ]]; then
    file="/run/assets/${id%-eval}.xml"
    [ -s "$file" ] && return 0
  fi

  # Editions without a dedicated template can use the generic template.
  case "${id,,}" in
    "win7"* | "win8"* | "win10"* | "win11"* | "winvista"* | "win20"* )
      file="/run/assets/${id%%-*}.xml"
      [ -s "$file" ] && return 0
      ;;
  esac

  return 1
}

getVersionPriority() {

  local id="${1,,}"
  local base="${2,,}"
  local order_name="EDITION_ORDER"
  local edition entry priority patterns pattern
  local result="other" prefix score best_score=-1

  id="${id%-eval}"

  case "$base" in
    "win20"* )
      order_name="SERVER_EDITION_ORDER"
      ;;
  esac

  local -n order_ref="$order_name"

  edition="${id#"$base"}"
  edition="${edition#-}"

  # Use the most specific matching pattern. This prevents broad patterns
  # such as enterprise-* from taking precedence over enterprise-iot-*.
  for entry in "${order_ref[@]}"; do

    IFS='|' read -r _ priority patterns <<< "$entry"

    for pattern in $patterns; do

      if [ "$pattern" = "@default" ]; then
        [ -z "$edition" ] || continue
        score=1
      elif [[ "$pattern" == *"*" ]]; then
        prefix="${pattern%\*}"
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
  local -n versions_ref="$versions_name"
  local -n bases_ref="$bases_name"
  local -n groups_ref="$groups_name"
  local -n indexes_ref="$indexes_name"

  local count i image_index
  local display product image platform
  local edition_id install_type flags
  local candidate candidate_id candidate_base key

  versions_ref=()
  bases_ref=()
  groups_ref=()
  indexes_ref=()

  platform=$(getPlatform "$xml")
  count=$(xmllint --nonet --xpath 'count(/WIM/IMAGE)' - 2>/dev/null <<< "$xml") || return 0

  for ((i=1; i<=count; i++)); do

    image_index=$(xmllint --nonet --xpath "string(/WIM/IMAGE[$i]/@INDEX)" - 2>/dev/null <<< "$xml") || continue
    display=$(xmllint --nonet --xpath "string(/WIM/IMAGE[$i]/DISPLAYNAME)" - 2>/dev/null <<< "$xml") || display=""
    product=$(xmllint --nonet --xpath "string(/WIM/IMAGE[$i]/WINDOWS/PRODUCTNAME)" - 2>/dev/null <<< "$xml") || product=""
    image=$(xmllint --nonet --xpath "string(/WIM/IMAGE[$i]/NAME)" - 2>/dev/null <<< "$xml") || image=""
    edition_id=$(xmllint --nonet --xpath "string(/WIM/IMAGE[$i]/WINDOWS/EDITIONID)" - 2>/dev/null <<< "$xml") || edition_id=""
    install_type=$(xmllint --nonet --xpath "string(/WIM/IMAGE[$i]/WINDOWS/INSTALLATIONTYPE)" - 2>/dev/null <<< "$xml") || install_type=""
    flags=$(xmllint --nonet --xpath "string(/WIM/IMAGE[$i]/FLAGS)" - 2>/dev/null <<< "$xml") || flags=""

    [ -n "$image_index" ] || continue
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
      local name="${display:-${image:-$product}}"
      [ -n "$name" ] && warn "Unknown image name: '$name'"
      continue
    fi

    key="${candidate_id,,}"

    # Some client media use the same friendly name-derived ID for distinct
    # editions. Preserve the established unsuffixed Pro ID, and use the
    # structured edition metadata only to disambiguate a collision.
    if [[ -v "indexes_ref[$key]" ]]; then
      local structured=""

      case "${candidate_base,,}" in
        "winvista"* | "win7"* | "win8"* | "win10"* | "win11"* )
          structured=$(normalizeEditionID "${edition_id:-${flags:-}}" "$candidate_base")
          ;;
        "win20"* )
          structured=$(normalizeServerEditionID "${flags:-$edition_id}")

          # Some media use the same EDITIONID for Core and Desktop images.
          # INSTALLATIONTYPE provides the structural distinction without
          # requiring a hardcoded marketing name.
          if [[ "${install_type,,}" == *"core"* &&
            "$structured" != *"-core" ]]; then
            structured+="-core"
          fi
          ;;
      esac

      if [ -n "$structured" ]; then
        candidate_id="$candidate_base-$structured"
        key="${candidate_id,,}"
      fi
    fi

    if [[ -v "indexes_ref[$key]" ]]; then
      warn "Duplicate image identity '$candidate_id' at indexes ${indexes_ref[$key]} and $image_index"
      continue
    fi

    indexes_ref["$key"]="$image_index"
    versions_ref+=("$candidate_id")
    bases_ref+=("$candidate_base")
    groups_ref+=("$(getVersionPriority "$candidate_id" "$candidate_base")")

  done

  return 0
}

selectVersion() {

  local versions_name="$1"
  local indexes_name="$2"
  local preferred_name="$3"
  local result_name="$4"
  local index_name="$5"
  local -n version_list="$versions_name"
  local -n index_map="$indexes_name"
  local -n preference_list="$preferred_name"
  local -n selected_version="$result_name"
  local -n selected_image_index="$index_name"

  local wanted candidate match key
  local -a candidates=()

  for wanted in "${preference_list[@]}"; do

    [ -n "$wanted" ] || continue
    getCompatibleVersions "$wanted" candidates

    for candidate in "${candidates[@]}"; do

      match=$(hasVersion "$candidate" "${version_list[@]}") || continue
      hasAnswerFile "$match" || continue

      key="${match,,}"
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
  local -n edition_versions="$versions_name"
  local -n edition_bases="$bases_name"
  local -n edition_groups="$groups_name"
  local -n edition_order="$order_name"

  local base edition entry suffix priority i
  local -a preferred=()
  local -A seen=()

  if [ -n "$EDITION" ]; then

    for base in "${edition_bases[@]}"; do
      edition=$("$normalize_name" "$EDITION" "$base")
      preferred+=("$base${edition:+-$edition}")
    done

    if selectVersion \
        "$versions_name" \
        "$indexes_name" \
        preferred \
        "$result_name" \
        "$index_name"; then
      return 0
    fi

    warn "edition '$EDITION' is not supported by this image, using automatic selection instead."
  fi

  if [ -n "$suggested" ]; then

    preferred=("$suggested")

    if selectVersion \
        "$versions_name" \
        "$indexes_name" \
        preferred \
        "$result_name" \
        "$index_name"; then
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

  if selectVersion \
      "$versions_name" \
      "$indexes_name" \
      preferred \
      "$result_name" \
      "$index_name"; then
    return 0
  fi

  # Then try noncanonical editions from the same preference groups.
  preferred=()
  seen=()

  for entry in "${edition_order[@]}"; do

    IFS='|' read -r _ priority _ <<< "$entry"

    [[ -v "seen[$priority]" ]] && continue
    seen["$priority"]="Y"

    for ((i=0;i<${#edition_versions[@]};i++)); do
      [[ "${edition_groups[$i]}" == "$priority" ]] || continue
      preferred+=("${edition_versions[$i]}")
    done

  done

  selectVersion \
    "$versions_name" \
    "$indexes_name" \
    preferred \
    "$result_name" \
    "$index_name"
}

detectVersion() {

  local xml="$1"
  local suggested="${2:-}"
  local result_name="$3"
  local index_name="$4"
  local -n result_ref="$result_name"
  local -n index_ref="$index_name"

  local order_name="EDITION_ORDER"
  local normalize_name="normalizeEditionID"

  local -a bases=()
  local -a groups=()
  local -a versions=()
  local -A image_indexes=()

  result_ref=""
  index_ref=""

  getVersions \
    "$xml" \
    versions \
    bases \
    groups \
    image_indexes

  [ "${#versions[@]}" -eq 0 ] && return 0

  case "${bases[0],,}" in
    "win20"* )
      order_name="SERVER_EDITION_ORDER"
      normalize_name="normalizeServerEditionID"
      ;;
  esac

  selectEdition \
    versions \
    bases \
    groups \
    image_indexes \
    "$suggested" \
    "$result_name" \
    "$index_name" \
    "$normalize_name" \
    "$order_name" && return 0

  result_ref="${versions[0]}"

  local key="${result_ref,,}"
  index_ref="${image_indexes[$key]}"

  return 0
}

detectLanguage() {

  local xml="$1"
  local index="${2:-}"
  local xpath lang=""

  if [[ "$index" =~ ^[0-9]+$ ]]; then
    xpath="string((/WIM/IMAGE[@INDEX='$index']/WINDOWS/LANGUAGES/DEFAULT | /WIM/IMAGE[@INDEX='$index']/WINDOWS/LANGUAGES/FALLBACK/DEFAULT)[1])"
  else
    xpath='string((/WIM/IMAGE/WINDOWS/LANGUAGES/DEFAULT | /WIM/IMAGE/WINDOWS/LANGUAGES/FALLBACK/DEFAULT)[1])'
  fi

  lang=$(xmllint --nonet --xpath "$xpath" - 2>/dev/null <<< "$xml") || lang=""

  if [ -z "$lang" ]; then
    warn "Language could not be detected from ISO!"
    return 0
  fi

  local culture
  culture=$(getLanguage "$lang" "culture")
  [ -n "$culture" ] && LANGUAGE="$lang" && return 0

  warn "Invalid language detected: \"$lang\""
  return 0
}

skipVersion() {

  local id="$1"

  case "${id,,}" in
    "win9"* | "winxp"* | "win2k"* | "win2003"* )
      return 0 ;;
  esac

  return 1
}

detectLegacy() {

  local dir="$1"
  local find

  [[ "${PLATFORM,,}" != "x64" ]] && return 1

  find=$(find "$dir" -maxdepth 1 -type d -iname WIN95 -print -quit)
  [ -n "$find" ] && DETECTED="win95" && return 0

  find=$(find "$dir" -maxdepth 1 -type d -iname WIN98 -print -quit)
  [ -n "$find" ] && DETECTED="win98" && return 0

  find=$(find "$dir" -maxdepth 1 -type d -iname WIN9X -print -quit)
  [ -n "$find" ] && DETECTED="win9x" && return 0

  find=$(find "$dir" -maxdepth 1 -type f -iname CDROM_W.40 -print -quit)
  [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname CDROM_S.40 -print -quit)
  [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname CDROM_TS.40 -print -quit)
  [ -n "$find" ] && DETECTED="winnt4" && return 0

  find=$(find "$dir" -maxdepth 1 -type f -iname CDROM_NT.5 -print -quit)

  if [ -n "$find" ]; then

    find=$(find "$dir" -maxdepth 1 -type f -iname CDROM_IA.5 -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname CDROM_ID.5 -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname CDROM_IP.5 -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname CDROM_IS.5 -print -quit)
    [ -n "$find" ] && DETECTED="win2k" && return 0

  fi

  find=$(find "$dir" -maxdepth 1 -iname WIN51 -print -quit)

  if [ -n "$find" ]; then

    find=$(find "$dir" -maxdepth 1 -type f -iname WIN51AP -print -quit)
    [ -n "$find" ] && DETECTED="winxpx64" && return 0

    find=$(find "$dir" -maxdepth 1 -type f -iname WIN51IC -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51IP -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname setupxp.htm -print -quit)
    [ -n "$find" ] && DETECTED="winxpx86" && return 0

    find=$(find "$dir" -maxdepth 1 -type f -iname WIN51IS -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51IA -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51IB -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51ID -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51IL -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51AA -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51AD -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51AS -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51MA -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51MD -print -quit)
    [ -n "$find" ] && DETECTED="win2003r2" && return 0

  fi

  return 1
}

resolveImage() {

  local version="$1"

  [ -z "$DETECTED" ] || return 0
  [ -z "$CUSTOM" ] || return 1
  [ -z "${REUSED_ISO:-}" ] || return 1
  [[ "${version,,}" != "http"* ]] || return 1

  local file="/run/assets/$version.xml"

  if [ -s "$file" ]; then
    DETECTED="$version"
    return 0
  fi

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

  skipVersion "${DETECTED,,}" && return 0

  if ! setXML "" && ! enabled "$MANUAL"; then
    MANUAL="Y"

    local desc
    desc=$(printEdition "$DETECTED" "this version")
    warn "the answer file for $desc was not found ($DETECTED.xml), $FB."
  fi

  return 0
}

findImage() {

  local dir="$1"
  local -n result_ref="$2"

  local src
  src=$(find "$dir" -maxdepth 1 -type d -iname sources -print -quit)

  if [ ! -d "$src" ]; then
    warn "failed to locate 'sources' folder in ISO image, $FB"
    return 1
  fi

  result_ref=$(find "$src" -maxdepth 1 -type f \
    \( -iname install.wim -or -iname install.esd \) -print -quit)

  if [ ! -f "$result_ref" ]; then
    warn "failed to locate 'install.wim' or 'install.esd' in ISO image, $FB"
    return 1
  fi

  return 0
}

readImageInfo() {

  local wim="$1"
  local -n result_ref="$2"

  result_ref=$(wimlib-imagex info -xml "$wim" |
    iconv -f UTF-16LE -t UTF-8) || {
    local rc=$?

    if (( rc >= 129 )); then
      exit "$rc"
    fi

    warn "failed to read Windows image information, $FB"
    return 1
  }

  return 0
}

getSuggestion() {

  [ -z "$CUSTOM" ] || return 0
  [ -n "${REUSED_ISO:-}" ] || return 0

  echo "${SUGGEST:-}"
}

validateEdition() {

  [ -n "$EDITION" ] || return 0

  case "${DETECTED,,}" in
    "win20"* )
      local edition
      edition=$(normalizeServerEditionID "$EDITION")

      if [ -n "$edition" ] &&
        [[ "${DETECTED,,}" != *"-${edition,,}" &&
          "${DETECTED,,}" != *"-${edition,,}-eval" ]]; then
        EDITION=""
      fi
      ;;
  esac

  return 0
}

unknownImage() {

  local msg="Failed to determine Windows version from image"

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
  local -n result_ref="$3"

  result_ref=$(printEdition "$DETECTED" "$DETECTED" "Y")

  detectLanguage "$info_xml" "$index"

  if [[ "${LANGUAGE,,}" != "en" && "${LANGUAGE,,}" != "en-"* ]]; then
    local language
    language=$(getLanguage "$LANGUAGE" "desc")
    result_ref+=" ($language)"
  fi

  return 0
}

configureImage() {

  local index="$1"
  local desc="$2"

  setXML "" "$index" && return 0

  if [[ "$DETECTED" == "win81x86"* ||
    "$DETECTED" == "win10x86"* ]]; then
    error "The 32-bit version of $desc is not supported!"
    return 1
  fi

  local msg="the answer file for $desc was not found ($DETECTED.xml)"
  local fallback="/run/assets/${DETECTED%%-*}.xml"

  if setXML "$fallback" "$index" || enabled "$MANUAL"; then
    ! enabled "$MANUAL" && warn "${msg}."
  else
    MANUAL="Y"
    warn "${msg}, $FB."
  fi

  return 0
}

detectImage() {

  local dir="$1"
  local version="$2"
  local desc

  XML=""

  resolveImage "$version" || :

  if [ -n "$DETECTED" ]; then
    setImage
    return 0
  fi

  info "Detecting version from ISO image..."

  if detectLegacy "$dir"; then
    desc=$(printEdition "$DETECTED" "$DETECTED" "Y")
    info "Detected: $desc"
    return 0
  fi

  local wim
  findImage "$dir" wim || return 1

  local image_info
  readImageInfo "$wim" image_info || return 1

  checkPlatform "$image_info" || exit 67

  local suggested
  suggested=$(getSuggestion)

  local index
  detectVersion "$image_info" "$suggested" DETECTED index
  validateEdition

  if [ -z "$DETECTED" ]; then
    unknownImage
    return 0
  fi

  describeImage "$image_info" "$index" desc
  info "Detected: $desc"

  configureImage "$index" "$desc" || return 1

  return 0
}
