#!/usr/bin/env bash
set -Eeuo pipefail

getPlatform() {

  local xml="$1"
  local tag="ARCH"
  local platform="x64"

  local -a arches=()

  mapfile -t arches < <(
    sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$xml" |
      sort -u
  )

  if [ "${#arches[@]}" -gt 1 ]; then
    platform="mixed"
  elif [ "${#arches[@]}" -eq 1 ]; then
    local arch="${arches[0]}"

    case "${arch,,}" in
      "0" ) platform="x86" ;;
      "9" ) platform="x64" ;;
      "12" ) platform="arm64" ;;
    esac
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

  local actual i
  local -a actuals=("$@")
  local -a expected=("$wanted")
  local -a selected=("$wanted")

  # Treat normal and Evaluation variants of the same edition as compatible.
  # The exact requested variant is always checked first.
  if [[ "${wanted,,}" == *"-eval" ]]; then
    expected+=("${wanted%-eval}")
    selected+=("${wanted%-eval}")
  else
    expected+=("$wanted-eval")
    selected+=("$wanted-eval")
  fi

  for (( i=0; i<${#expected[@]}; i++ )); do

    local expected_id="${expected[$i]}"
    local selected_id="${selected[$i]}"

    for actual in "${actuals[@]}"; do
      [[ "${actual,,}" == "${expected_id,,}" ]] || continue

      local file="/run/assets/$selected_id.xml"

      if [ -s "$file" ]; then
        echo "$selected_id"
        return 0
      fi

      if [[ "${selected_id,,}" == *"-eval" ]]; then
        local source="/run/assets/${selected_id%-eval}.xml"

        if [ -s "$source" ]; then
          echo "$selected_id"
          return 0
        fi
      fi

      # Editions without a dedicated template can use the generic template.
      case "${selected_id,,}" in
        "win7"* | "win8"* | "win10"* | "win11"* | "winvista"* | \
        "win2003"* | "win2008"* | "win2012"* | "win2016"* | \
        "win2019"* | "win2022"* | "win2025"* )
          file="/run/assets/${selected_id%%-*}.xml"

          if [ -s "$file" ]; then
            echo "$selected_id"
            return 0
          fi
          ;;
      esac
    done
  done

  return 1
}

getVersionPriority() {

  local id="${1%-eval}"
  local base="$2"
  local edition="${id#"$base"}"

  edition="${edition#-}"

  case "$edition" in
    "iot" | "iot-"* | "enterprise-iot" | "enterprise-iot-"* )
      echo "iot"
      ;;
    "ltsc" | "ltsc-"* | "enterprise-ltsc" | "enterprise-ltsc-"* )
      echo "ltsc"
      ;;
    "enterprise" | "enterprise-"* )
      echo "enterprise"
      ;;
    "ultimate" | "ultimate-"* )
      echo "ultimate"
      ;;
    "education" | "education-"* | "pro-education" | "pro-education-"* )
      echo "education"
      ;;
    "home" | "home-"* )
      echo "home"
      ;;
    "starter" | "starter-"* )
      echo "starter"
      ;;
    "hv" | "hv-"* )
      echo "hv"
      ;;
    "" | "n" | "pro" | "pro-"* | "professional" | "professional-"* | \
    "business" | "business-"* )
      echo "default"
      ;;
    * )
      echo "other"
      ;;
  esac

  return 0
}

detectVersion() {

  local xml="$1"
  local suggested="${2:-}"
  local result_name="$3"
  local index_name="$4"
  local -n result="$result_name"
  local -n result_index="$index_name"

  local -a bases=()
  local -a groups=()
  local -a versions=()
  local -A image_indexes=()

  local -a priorities=(
    "enterprise"
    "ultimate"
    "default"
    "iot"
    "ltsc"
    "education"
    "home"
    "starter"
    "hv"
  )

  local -a suffixes=(
    "-enterprise"
    "-ultimate"
    ""
    "-iot"
    "-ltsc"
    "-education"
    "-home"
    "-home-premium"
    "-home-basic"
    "-starter"
    "-hv"
  )

  local -a server_suffixes=(
    ""
    "-datacenter"
    "-enterprise"
    "-web"
    "-foundation"
    "-essentials"
    "-standard-core"
    "-datacenter-core"
    "-enterprise-core"
    "-web-core"
  )

  result=""
  result_index=""

  local image image_index key
  local display product platform

  platform=$(getPlatform "$xml")

  while IFS='|' read -r image_index display product image; do

    [ -n "$image_index" ] || continue

    local candidate candidate_id candidate_base found=""

    for candidate in "$display" "$product" "$image"; do

      [[ "$candidate" == *"Operating System"* ]] && continue
      [ -z "$candidate" ] && continue

      candidate_base=$(fromName "$candidate" "$platform")
      candidate_id=$(getVersion "$candidate" "$platform")

      if [ -z "$candidate_base" ] || [ -z "$candidate_id" ]; then
        continue
      fi

      found="Y"
      key="${candidate_id,,}"
      [[ -v "image_indexes[$key]" ]] && continue

      image_indexes["$key"]="$image_index"
      versions+=("$candidate_id")
      bases+=("$candidate_base")
      groups+=("$(getVersionPriority "$candidate_id" "$candidate_base")")

    done

    if [ -z "$found" ]; then
      local name="${display:-${product:-$image}}"
      [ -n "$name" ] && warn "Unknown image name: '$name'"
    fi

  done < <(
    awk '
      /<IMAGE INDEX="/ {
        image_index = $0
        sub(/^.*<IMAGE INDEX="/, "", image_index)
        sub(/".*$/, "", image_index)
        display = product = name = ""
      }

      image_index != "" && /<DISPLAYNAME>/ {
        display = $0
        sub(/^.*<DISPLAYNAME>/, "", display)
        sub(/<\/DISPLAYNAME>.*$/, "", display)
      }

      image_index != "" && /<PRODUCTNAME>/ {
        product = $0
        sub(/^.*<PRODUCTNAME>/, "", product)
        sub(/<\/PRODUCTNAME>.*$/, "", product)
      }

      image_index != "" && /<NAME>/ {
        name = $0
        sub(/^.*<NAME>/, "", name)
        sub(/<\/NAME>.*$/, "", name)
      }

      /<\/IMAGE>/ {
        print image_index "|" display "|" product "|" name
        image_index = ""
      }
    ' <<< "$xml"
  )

  [ "${#versions[@]}" -eq 0 ] && return 0

  local base match prefer

  if [ -n "$EDITION" ]; then

    local edition tried=""

    for base in "${bases[@]}"; do

      case "${base,,}" in
        "win20"* )
          edition=$(normalizeServerEditionID "$EDITION")
          ;;
        * )
          edition=$(normalizeEditionID "$EDITION" "$base")
          ;;
      esac

      tried="Y"
      prefer="$base"
      [ -n "$edition" ] && prefer+="-$edition"

      if match=$(hasVersion "$prefer" "${versions[@]}"); then
        key="${match,,}"
        result="$match"
        result_index="${image_indexes[$key]}"

        return 0
      fi

    done

    if [ -n "$tried" ]; then
      warn "edition '$EDITION' is not supported by this image, using automatic selection instead."
    fi

  fi

  # For reused automatic media, prefer the edition selected by parseVersion()
  # when that edition is actually present in the image. An explicit EDITION
  # remains authoritative because it is handled above.
  if [ -n "$suggested" ]; then

    if match=$(hasVersion "$suggested" "${versions[@]}"); then
      key="${match,,}"
      result="$match"
      result_index="${image_indexes[$key]}"

      return 0
    fi

  fi

  # Server media defaults to the normal Standard GUI edition. If Standard
  # is absent, prefer another known GUI edition before any Core variant.
  
  local suffix

  for suffix in "${server_suffixes[@]}"; do
    for base in "${bases[@]}"; do

      case "${base,,}" in
        "win20"* )

          prefer="$base$suffix"

          if match=$(hasVersion "$prefer" "${versions[@]}"); then
            key="${match,,}"
            result="$match"
            result_index="${image_indexes[$key]}"
            return 0
          fi
          ;;
      esac

    done
  done

  # Prefer the normal edition within each selection family. hasVersion()
  # still allows its Evaluation counterpart when the normal variant is absent.
  for suffix in "${suffixes[@]}"; do
    for base in "${bases[@]}"; do

      prefer="$base$suffix"

      if match=$(hasVersion "$prefer" "${versions[@]}"); then
        key="${match,,}"
        result="$match"
        result_index="${image_indexes[$key]}"
        return 0
      fi
  
    done
  done

  # When the normal edition is absent, select another compatible member of
  # that family, such as N, Workstations, or a future dynamic variant.
  local priority i

  for priority in "${priorities[@]}"; do
    for (( i=0; i<${#versions[@]}; i++ )); do

      [[ "${groups[$i]}" == "$priority" ]] || continue

      local actual="${versions[$i]}"

      if match=$(hasVersion "$actual" "${versions[@]}"); then
        key="${match,,}"
        result="$match"
        result_index="${image_indexes[$key]}"
        return 0
      fi
  
    done
  done

  # Future or unusual editions that do not belong to a known selection
  # family use the first recognized WIM image.
  result="${versions[0]}"
  key="${result,,}"
  result_index="${image_indexes[$key]}"

  return 0
}

detectLanguage() {

  local xml="$1"
  local lang=""

  if [[ "$xml" == *"LANGUAGE><DEFAULT>"* ]]; then
    lang="${xml#*LANGUAGE><DEFAULT>}"
    lang="${lang%%<*}"
  else
    if [[ "$xml" == *"FALLBACK><DEFAULT>"* ]]; then
      lang="${xml#*FALLBACK><DEFAULT>}"
      lang="${lang%%<*}"
    fi
  fi

  if [ -z "$lang" ]; then
    warn "Language could not be detected from ISO!" && return 0
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

detectImage() {

  local dir="$1"
  local version="$2"
  local desc

  XML=""

  # For normal download routes, avoid inspecting install.wim when the route
  # already maps directly to an available answer file. Routes such as Tiny10
  # and Tiny11 have no corresponding answer file, so their actual Windows
  # edition will be detected from the downloaded image instead.
  if [ -z "$DETECTED" ] && [ -z "$CUSTOM" ] &&
    [ -z "${REUSED_ISO:-}" ] && [[ "${version,,}" != "http"* ]]; then

    local file="/run/assets/$version.xml"

    if [ -s "$file" ]; then
      DETECTED="$version"
    elif [[ "${version,,}" == *"-eval" ]]; then
      local source="/run/assets/${version%-eval}.xml"
      [ -s "$source" ] && DETECTED="$version"
    fi

  fi

  if [ -n "$DETECTED" ]; then

    skipVersion "${DETECTED,,}" && return 0

    if ! setXML "" && ! enabled "$MANUAL"; then
      MANUAL="Y"
      desc=$(printEdition "$DETECTED" "this version")
      warn "the answer file for $desc was not found ($DETECTED.xml), $FB."
    fi

    return 0
  fi

  info "Detecting version from ISO image..."

  if detectLegacy "$dir"; then
    desc=$(printEdition "$DETECTED" "$DETECTED" "Y")
    info "Detected: $desc"
    return 0
  fi

  local src
  src=$(find "$dir" -maxdepth 1 -type d -iname sources -print -quit)

  if [ ! -d "$src" ]; then
    warn "failed to locate 'sources' folder in ISO image, $FB"
    return 1
  fi

  local wim
  wim=$(find "$src" -maxdepth 1 -type f \
    \( -iname install.wim -or -iname install.esd \) -print -quit)

  if [ ! -f "$wim" ]; then
    warn "failed to locate 'install.wim' or 'install.esd' in ISO image, $FB"
    return 1
  fi

  local info
  info=$(wimlib-imagex info -xml "$wim" |
    iconv -f UTF-16LE -t UTF-8) || {
    local rc=$?

    if (( rc >= 129 )); then
      exit "$rc"
    fi

    warn "failed to read Windows image information, $FB"
    return 1
  }

  checkPlatform "$info" || exit 67

  local suggested=""

  if [ -z "$CUSTOM" ] && [ -n "${REUSED_ISO:-}" ]; then
    suggested="${SUGGEST:-}"
  fi

  local index
  detectVersion "$info" "$suggested" DETECTED index

  if [ -n "$EDITION" ]; then
    local edition

    case "${DETECTED,,}" in
      "win2003"* | "win2008"* | "win2012"* | "win2016"* | \
      "win2019"* | "win2022"* | "win2025"* )
        edition=$(normalizeServerEditionID "$EDITION")

        if [ -n "$edition" ] &&
          [[ "${DETECTED,,}" != *"-${edition,,}" &&
            "${DETECTED,,}" != *"-${edition,,}-eval" ]]; then
          EDITION=""
        fi
        ;;
    esac
  fi

  if [ -z "$DETECTED" ]; then
    local msg="Failed to determine Windows version from image"

    if setXML "" || enabled "$MANUAL"; then
      info "${msg}!"
    else
      MANUAL="Y"
      warn "${msg}, $FB."
    fi

    return 0
  fi

  desc=$(printEdition "$DETECTED" "$DETECTED" "Y")

  detectLanguage "$info"

  if [[ "${LANGUAGE,,}" != "en" && "${LANGUAGE,,}" != "en-"* ]]; then
    local language
    language=$(getLanguage "$LANGUAGE" "desc")
    desc+=" ($language)"
  fi

  info "Detected: $desc"
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
