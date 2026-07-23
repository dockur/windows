#!/usr/bin/env bash
set -Eeuo pipefail

getPlatform() {

  local xml="$1"
  local tag="ARCH"
  local platform="x64"
  local arch

  arch=$(sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$xml")

  case "${arch,,}" in
    "0" ) platform="x86" ;;
    "9" ) platform="x64" ;;
    "12" ) platform="arm64" ;;
  esac

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
    * ) compat="${PLATFORM,,}" ;;
  esac

  [[ "${compat,,}" == "${PLATFORM,,}" ]] && return 0

  error "You cannot boot ${platform^^} images on a $PLATFORM CPU!"
  return 1
}

hasVersion() {

  local wanted="$1"
  shift

  local actual expected_id selected_id file source
  local i

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

    expected_id="${expected[$i]}"
    selected_id="${selected[$i]}"

    for actual in "${actuals[@]}"; do
      [[ "${actual,,}" == "${expected_id,,}" ]] || continue

      file="/run/assets/$selected_id.xml"

      if [ -s "$file" ]; then
        echo "$selected_id"
        return 0
      fi

      if [[ "${selected_id,,}" == *"-eval" ]]; then
        source="/run/assets/${selected_id%-eval}.xml"

        if [ -s "$source" ]; then
          echo "$selected_id"
          return 0
        fi
      fi

      # Client editions without a dedicated template can use the generic
      # template. updateImage() makes that copy edition-neutral.
      case "${selected_id,,}" in
        "win7"* | "win8"* | "win10"* | "win11"* | "winvista"* )
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

selectVersion() {

  local tag="$1"
  local xml="$2"
  local platform="$3"

  local name id base prefer match suffix actual
  local tried=""

  local -a versions=()
  local -a bases=()
  local -a priorities=(
    "-enterprise"
    "-ultimate"
    ""
    "-iot"
    "-ltsc"
    "-education"
    "-home"
    "-starter"
    "-hv"
  )

  while IFS= read -r name; do
    [[ "$name" == *"Operating System"* ]] && continue
    [ -z "$name" ] && continue

    base=$(fromName "$name" "$platform")
    id=$(getVersion "$name" "$platform")

    if [ -z "$base" ] || [ -z "$id" ]; then
      warn "Unknown ${tag,,}: '$name'"
      continue
    fi

    versions+=("$id")
    bases+=("$base")
  done < <(
    sed -n \
      "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" \
      <<< "$xml"
  )

  [ "${#versions[@]}" -eq 0 ] && return 0

  if [ -n "$EDITION" ]; then

    for base in "${bases[@]}"; do
      [[ "${base,,}" == win20* ]] && continue

      tried="Y"

      case "${EDITION,,}" in
        "pro" | "professional" | "business" )
          prefer="$base"
          ;;
        * )
          prefer="$base-${EDITION,,}"
          ;;
      esac

      if match=$(hasVersion "$prefer" "${versions[@]}"); then
        echo "$match"
        return 0
      fi
    done

    if [ -n "$tried" ]; then
      warn "Edition '$EDITION' is not supported by this image, using automatic selection instead."
    fi
  fi

  # Preserve the existing preference for Enterprise, Ultimate, and the
  # normal Pro/Professional/Business edition. The remaining entries provide
  # deterministic selection when those editions are absent.
  for suffix in "${priorities[@]}"; do
    for base in "${bases[@]}"; do
      prefer="$base$suffix"

      # Automatic selection must prefer an edition that is actually present.
      for actual in "${versions[@]}"; do
        [[ "${actual%-eval}" == "${prefer%-eval}" ]] || continue

        if match=$(hasVersion "$prefer" "${versions[@]}"); then
          echo "$match"
          return 0
        fi
      done
    done
  done

  # Future or unusual edition that getVersion() recognizes but which is not
  # included in the priority list: use the first recognized WIM image.
  echo "${versions[0]}"
  return 0
}

detectVersion() {

  local xml="$1"
  local id platform

  platform=$(getPlatform "$xml")
  id=$(selectVersion "DISPLAYNAME" "$xml" "$platform")
  [ -z "$id" ] && id=$(selectVersion "PRODUCTNAME" "$xml" "$platform")
  [ -z "$id" ] && id=$(selectVersion "NAME" "$xml" "$platform")

  echo "$id"
  return 0
}

getImageIndex() {

  local xml="$1"
  local wanted="$2"
  local platform tag index name id

  local -a matches=()

  [ -z "$wanted" ] && return 1

  platform=$(getPlatform "$xml")

  for tag in DISPLAYNAME PRODUCTNAME NAME; do

    matches=()

    while IFS=$'\t' read -r index name; do
      [ -n "$index" ] || continue
      [[ "$name" == *"Operating System"* ]] && continue
      [ -z "$name" ] && continue

      id=$(getVersion "$name" "$platform")
      [[ "${id,,}" == "${wanted,,}" ]] || continue

      matches+=("$index")
    done < <(
      awk -v tag="$tag" '
        /<IMAGE INDEX="/ {
          image_index = $0
          sub(/^.*<IMAGE INDEX="/, "", image_index)
          sub(/".*$/, "", image_index)
        }

        image_index != "" && $0 ~ "<" tag ">" {
          value = $0
          sub("^.*<" tag ">", "", value)
          sub("</" tag ">.*$", "", value)
          print image_index "\t" value
        }

        /<\/IMAGE>/ {
          image_index = ""
        }
      ' <<< "$xml"
    )

    case "${#matches[@]}" in
      0 )
        continue
        ;;
      1 )
        echo "${matches[0]}"
        return 0
        ;;
      * )
        # Several WIM entries collapse to the same internal version ID,
        # so selecting one of their indexes would be arbitrary.
        return 1
        ;;
    esac

  done

  return 1
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
  local desc msg language
  local file source

  XML=""

  # For normal download routes, avoid inspecting install.wim when the route
  # already maps directly to an available answer file. Routes such as Tiny10
  # and Tiny11 have no corresponding answer file, so their actual Windows
  # edition will be detected from the downloaded image instead.
  if [ -z "$DETECTED" ] && [ -z "$CUSTOM" ] &&
    [ -z "${REUSED_ISO:-}" ] && [[ "${version,,}" != "http"* ]]; then

    file="/run/assets/$version.xml"

    if [ -s "$file" ]; then
      DETECTED="$version"
    elif [[ "${version,,}" == *"-eval" ]]; then
      source="/run/assets/${version%-eval}.xml"
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
    desc=$(printEdition "$DETECTED" "$DETECTED")
    info "Detected: $desc"
    return 0
  fi

  local src wim info index
  src=$(find "$dir" -maxdepth 1 -type d -iname sources -print -quit)

  if [ ! -d "$src" ]; then
    warn "failed to locate 'sources' folder in ISO image, $FB"
    return 1
  fi

  wim=$(find "$src" -maxdepth 1 -type f \
    \( -iname install.wim -or -iname install.esd \) -print -quit)

  if [ ! -f "$wim" ]; then
    warn "failed to locate 'install.wim' or 'install.esd' in ISO image, $FB"
    return 1
  fi

  if ! info=$(wimlib-imagex info -xml "$wim" |
    iconv -f UTF-16LE -t UTF-8); then
    warn "failed to read Windows image information, $FB"
    return 1
  fi

  checkPlatform "$info" || exit 67

  DETECTED=$(detectVersion "$info")

  if [ -z "$DETECTED" ]; then
    msg="Failed to determine Windows version from image"

    if setXML "" || enabled "$MANUAL"; then
      info "${msg}!"
    else
      MANUAL="Y"
      warn "${msg}, $FB."
    fi

    return 0
  fi

  index=$(getImageIndex "$info" "$DETECTED") || index=""
  desc=$(printEdition "$DETECTED" "$DETECTED")

  detectLanguage "$info"

  if [[ "${LANGUAGE,,}" != "en" && "${LANGUAGE,,}" != "en-"* ]]; then
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

  msg="the answer file for $desc was not found ($DETECTED.xml)"
  local fallback="/run/assets/${DETECTED%%-*}.xml"

  if setXML "$fallback" || enabled "$MANUAL"; then
    ! enabled "$MANUAL" && warn "${msg}."
  else
    MANUAL="Y"
    warn "${msg}, $FB."
  fi

  return 0
}
