#!/usr/bin/env bash
set -Eeuo pipefail

handleCurlError() {

  local code="$1"
  local server="$2"
  local reason="${3:-}"

  local signal

  if [ -n "$reason" ] && (( code <= 125 )); then
    error "Request to $server servers failed: ${reason%.}."
    return 1
  fi

  case "$code" in
    126) error "The curl command could not be executed." ;;
    127) error "The curl command was not found." ;;
    *)
      if (( code < 129 )); then
        error "Request to $server servers failed with curl exit status $code."
        return 1
      fi

      signal=$(kill -l "$((code - 128))" 2>/dev/null || true)

      case "$signal" in
        INT) error "Curl was interrupted." ;;
        SEGV | ABRT) error "Curl crashed with signal $signal." ;;
        "") error "Curl terminated with exit status $code." ;;
        *) error "Curl terminated due to signal $signal." ;;
      esac ;;
  esac

  return 1
}

curlRequest() {

  local server="$1"
  local agent="$2"
  shift 2

  local log reason response

  if ! log=$(mktemp -p "$QEMU_DIR"); then
    error "Failed to create a temporary curl log."
    return 1
  fi

  # Preserve curl's status under errexit so its stderr can be translated
  # into a useful error instead of terminating the script immediately.
  {
    response=$(LC_ALL=C curl \
      --silent \
      --show-error \
      --max-time 30 \
      --user-agent "$agent" \
      --fail \
      --proto =https \
      --tlsv1.2 \
      --http1.1 \
      "$@" 2>"$log")
    local rc=$?
  } || :

  if (( rc != 0 )); then

    reason=$(sed -nE 's/^curl: \([0-9]+\) //p' "$log" | tail -n 1)

    rm -f "$log"
    handleCurlError "$rc" "$server" "$reason"

    return 1
  fi

  rm -f "$log"

  printf '%s' "$response"
  return 0
}

downloadWindowsLink() {

  local productId="$1"
  local url="$2"
  local agent="$3"
  local language="$4"
  local lang="$5"
  local desc="$6"
  local type="$7"

  local ovToken="" ovTicks=""
  local profile="606624d44113"
  local skuId skuJson linkJson
  local link ovData ovTime session

  # Prefer the Linux kernel UUID source, with uuidgen as a portable fallback
  # for macOS and systems without /proc.
  if ! session=$(cat /proc/sys/kernel/random/uuid 2> /dev/null || uuidgen --random); then
    error "Failed to generate session ID!"
    return 1
  fi

  session="${session//[![:print:]]/}"

  if [ -z "$session" ]; then
    error "Failed to generate session ID!"
    return 1
  fi

  # Register the session with Microsoft's anti-abuse endpoint before
  # requesting SKU or download links.

  local orgId="y6jn8c31"
  local vlsUrl="https://vlscppe.microsoft.com/tags?org_id=$orgId&session_id=$session"

  enabled "$DEBUG" && echo "Getting Session ID: $session"

  curlRequest "Microsoft" "$agent" \
    --output /dev/null \
    --header "Accept:" \
    --max-filesize 100K \
    -- "$vlsUrl" || return 1

  # Complete Microsoft's ov-df challenge by retrieving a token and timing
  # value, then returning both with the current timestamp.

  local instance="560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175"
  local ovUrl="https://ov-df.microsoft.com/mdt.js?instanceId=$instance&PageId=si&session_id=$session"

  enabled "$DEBUG" && echo -n "Getting OV data: "

  ovData=$(curlRequest "Microsoft" "$agent" \
    --header "Accept:" \
    --max-filesize 1M \
    -- "$ovUrl") || return 1

  if [[ $ovData =~ [\?\&]w=([A-Fa-f0-9]+) ]]; then
    ovToken="${BASH_REMATCH[1]}"
  fi

  if [[ $ovData =~ rticks=\"\+?([0-9]+) ]]; then
    ovTicks="${BASH_REMATCH[1]}"
  fi

  if [[ -z $ovToken || -z $ovTicks ]]; then
    error "Could not extract ov-df data from Microsoft server!"
    return 1
  fi

  enabled "$DEBUG" && echo "$ovToken"

  sleep 0.2

  ovTime=$(date +%s%3N)
  ovUrl="https://ov-df.microsoft.com/?session_id=$session&CustomerId=$instance&PageId=si&w=$ovToken&mdt=$ovTime&rticks=$ovTicks"

  enabled "$DEBUG" && echo "Sending OV reply: $instance"

  curlRequest "Microsoft" "$agent" \
    --output /dev/null \
    --header "Accept:" \
    --max-filesize 100K \
    -- "$ovUrl" || return 1

  enabled "$DEBUG" && echo -n "Getting language SKU ID: "

  local skuUrl="https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$profile&ProductEditionId=$productId&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$session"

  skuJson=$(curlRequest "Microsoft" "$agent" \
    --referer "$url" \
    --header "Accept:" \
    --max-filesize 100K \
    -- "$skuUrl") || return 1

  # Guard jq under errexit so malformed API data can be handled as a normal
  # missing-result error. The same pattern is reused for the link response.
  { skuId=$(printf '%s\n' "$skuJson" | jq --arg LANG "$language" -r 'first(.Skus[]? | select(.Language == $LANG) | .Id) // empty') 2>/dev/null; local rc=$?; } || :

  if [ -z "$skuId" ] || [[ "${skuId,,}" == "null" ]] || (( rc != 0 )); then
    language=$(getLanguage "$lang" "desc")
    error "No download in the $language language available for $desc!"
    return 1
  fi

  enabled "$DEBUG" && echo "$skuId"
  enabled "$DEBUG" && echo "Getting ISO download link..."

  # Microsoft normally applies request or IP blocking on this final connector
  # call rather than during the preceding session setup.

  local linkUrl="https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=$profile&ProductEditionId=undefined&SKU=$skuId&friendlyFileName=undefined&Locale=en-US&sessionID=$session"

  linkJson=$(curlRequest "Microsoft" "$agent" \
    --referer "$url" \
    --header "Accept:" \
    --max-filesize 100K \
    -- "$linkUrl") || return 1

  if ! [ "$linkJson" ]; then
    error "Microsoft servers gave us an empty response to our request for an automated download."
    return 1
  fi

  if grep -Fq "Sentinel marked this request as rejected." <<< "$linkJson"; then
    error "Microsoft blocked the automated download request based on your IP address."
    return 1
  fi

  if grep -Fq "We are unable to complete your request at this time." <<< "$linkJson"; then
    error "Microsoft blocked the automated download request."
    return 1
  fi

  { link=$(printf '%s\n' "$linkJson" | jq --argjson TYPE "$type" -r 'first(.ProductDownloadOptions[]? | select(.DownloadType == $TYPE) | .Uri) // empty') 2>/dev/null; rc=$?; } || :

  if [ -z "$link" ] || [[ "${link,,}" == "null" ]] || (( rc != 0 )); then
    error "Microsoft server gave us no download link to our request for an automated download!"
    info "Response: $linkJson"
    return 1
  fi

  MIDO_URL="$link"
  return 0
}

downloadWindows() {

  local id="$1"
  local lang="$2"
  local desc="$3"

  local agent language page
  local productId type winVer

  agent=$(getAgent)
  language=$(getLanguage "$lang" "name")

  case "${id,,}" in
    "win10x64" )
      productId="2618"
      winVer="10"
      type="1" ;;
    "win11x64" )
      productId="3321"
      winVer="11"
      type="1" ;;
    "win11arm64" )
      productId="3324"
      winVer="11arm64"
      type="2" ;;
    * )
      error "Invalid VERSION specified, value \"$id\" is not recognized!"
      return 1 ;;
  esac

  local url="https://www.microsoft.com/en-us/software-download/windows$winVer"
  [[ "${id,,}" == "win10"* ]] && url+="ISO"

  enabled "$DEBUG" && echo "Using Product edition ID: $productId"

  if downloadWindowsLink "$productId" "$url" "$agent" "$language" "$lang" "$desc" "$type"; then
    return 0
  fi

  sleep 1

  # Product edition IDs can change. If the configured ID fails, recover the
  # current value from Microsoft's public download page and retry once.
  local msg="retrying using a different method..."
  info "Microsoft download request failed, $msg"
  enabled "$DEBUG" && echo "Parsing download page: ${url}"

  page=$(curlRequest "Microsoft" "$agent" \
    --header "Accept:" \
    --max-filesize 1M \
    -- "$url") || return 1

  enabled "$DEBUG" && echo -n "Getting Product edition ID: "
  productId=$(printf '%s' "$page" |
    tr '\r\n' '  ' |
    grep -Eio "<option[^>]*value=[\"'][0-9]+[\"'][^>]*>[[:space:]]*Windows[^<]*" |
    sed -nE "s/.*value=[\"']([0-9]+)[\"'].*/\1/p" |
    sed -n '1p' |
    cut -c 1-16 || true)
  enabled "$DEBUG" && echo "$productId"

  if [ -z "$productId" ]; then
    info "Failed to fetch the Product edition ID from the download page, $msg"
    return 1
  fi

  if ! downloadWindowsLink "$productId" "$url" "$agent" "$language" "$lang" "$desc" "$type"; then
    return 1
  fi

  return 0
}

downloadWindowsEval() {

  local id="$1"
  local lang="$2"
  local desc="$3"

  local culture compare type
  local agent language winVer

  case "${id,,}" in
    "win11${PLATFORM,,}-enterprise-eval" )
      type="enterprise"
      winVer="windows-11-enterprise" ;;
    "win11${PLATFORM,,}-enterprise-iot-eval" )
      type="iot"
      winVer="windows-11-iot-enterprise-ltsc-eval" ;;
    "win11${PLATFORM,,}-enterprise-ltsc-eval" )
      type="ltsc"
      winVer="windows-11-enterprise" ;;
    "win2025-eval" )
      type="server"
      winVer="windows-server-2025" ;;
    "win2022-eval" )
      type="server"
      winVer="windows-server-2022" ;;
    "win2019-hv" )
      type="server"
      winVer="hyper-v-server-2019" ;;
    "win2019-eval" )
      type="server"
      winVer="windows-server-2019" ;;
    "win2016-eval" )
      type="server"
      winVer="windows-server-2016" ;;
    "win2012r2-eval" )
      type="server"
      winVer="windows-server-2012-r2" ;;
    * )
      error "Invalid VERSION specified, value \"$id\" is not recognized!" && return 1 ;;
  esac

  agent=$(getAgent)
  culture=$(getLanguage "$lang" "culture")

  local country="${culture#*-}"
  local link="" links page
  local url="https://www.microsoft.com/en-us/evalcenter/download-$winVer"

  enabled "$DEBUG" && echo "Parsing download page: ${url}"

  page=$(curlRequest "Microsoft" "$agent" \
    --location \
    --max-filesize 1M \
    -- "$url") || return 1

  if ! [ "$page" ]; then
    error "Windows server download page gave us an empty response"
    return 1
  fi

  enabled "$DEBUG" && echo "Getting download link.."

  # Normalize HTML-encoded query separators before extracting fwlinks.
  page=${page//&amp;/&}
  page=${page//&#38;/&}

  links=$(printf '%s\n' "$page" |
    grep -Eio "https://go\.microsoft\.com/fwlink(/p)?/\?[^\"'<>[:space:]]+" |
    grep -Ei '(^|[?&])culture='"${culture,,}"'(&|$)' |
    grep -Ei '(^|[?&])country='"${country,,}"'(&|$)') || {
    # Distinguish a changed or missing English page from an unavailable
    # translation for an otherwise supported product.
    if [[ "${lang,,}" == "en" || "${lang,,}" == "en-"* ]]; then
      error "Windows server download page gave us no download link!"
    else
      language=$(getLanguage "$lang" "desc")
      error "No download in the $language language available for $desc!"
    fi
    return 1
  }

  # Evaluation pages currently expose several matching fwlinks in a known
  # product/platform order, so select the entry for the requested variant.
  case "$type" in
    "iot" )
      case "${PLATFORM,,}" in
        "x64" )
          link=$(printf '%s\n' "$links" | head -n 1) ;;
        "arm64" )
          link=$(printf '%s\n' "$links" | head -n 2 | tail -n 1) ;;
      esac ;;
    "ltsc" )
      case "${PLATFORM,,}" in
        "x64" )
          link=$(printf '%s\n' "$links" | head -n 2 | tail -n 1) ;;
      esac ;;
    "enterprise" )
      case "${PLATFORM,,}" in
        "x64" )
          if [[ "$winVer" != "windows-10"* ]]; then
            link=$(printf '%s\n' "$links" | head -n 1)
          else
            link=$(printf '%s\n' "$links" | head -n 2 | tail -n 1)
          fi ;;
        "arm64" )
          link=$(printf '%s\n' "$links" | head -n 2 | tail -n 1) ;;
      esac ;;
    "server" )
      case "${PLATFORM,,}" in
        "x64" )
          link=$(printf '%s\n' "$links" | head -n 1) ;;
      esac ;;
    * )
      error "Invalid type specified, value \"$type\" is not recognized!" && return 1 ;;
  esac

  [ -z "$link" ] && error "Could not parse download link from page!" && return 1

  # Resolve the fwlink now so later logging and platform validation use the
  # actual ISO URL rather than Microsoft's generic redirect.

  link=$(curlRequest "Microsoft" "$agent" \
    --location \
    --output /dev/null \
    --write-out "%{url_effective}" \
    --head \
    -- "$link") || return 1

  local lower="${link,,}"
  local separator='(^|[[:space:]_./-])'

  # Guard against page-order changes resolving to the wrong architecture
  # before downloading a multi-gigabyte image.
  case "${PLATFORM,,}" in
    "x64" )
      if [[ "$lower" =~ ${separator}(arm64|a64) ]]; then
        echo "Found download link: $link"
        error "Download link is for the wrong platform? Please report this at $SUPPORT/issues"
        return 1
      fi ;;
    "arm64" )
      if [[ "$lower" =~ ${separator}(x64|x86|amd64) ]]; then
        if enabled "$DEBUG"; then
          echo "Found download link: $link"
          echo "Link for ARM platform currently not available!"
        fi
        return 1
      fi ;;
  esac

  # During debug verification, compare the resolved filename with the static
  # catalog entry to expose unexpected changes on Microsoft's page.
  if enabled "$DEBUG" && enabled "$VERIFY" && [[ "${lang,,}" == "en"* ]]; then

    compare=$(getMido "$id" "$lang" "")

    if [ -n "$compare" ]; then
      link_name="${link%%[?#]*}"
      link_name="${link_name##*/}"

      compare_name="${compare%%[?#]*}"
      compare_name="${compare_name##*/}"

      if [[ "${link_name,,}" != "${compare_name,,}" ]]; then
        echo "Retrieved ISO file $link_name does not match the pre-defined filename: $compare_name"
      fi
    fi

  fi

  MIDO_URL="$link"
  return 0
}

getMidoDetected() {

  # Return the answer-file identity for the Microsoft source that actually
  # succeeded without changing the global DETECTED value.

  local version="${1,,}"
  local source="${2,,}"
  local current="$3"
  local default="$version"
  local detected

  [ -z "$source" ] && source="$version"

  # Preserve a DETECTED value that existed before SUGGEST was assigned.
  if enabled "${DETECTED_ORG:-}"; then
    echo "$current"
    return 0
  fi

  # Derive the normal answer-file identity from the requested download route.
  case "$default" in
    *"-enterprise-ltsc-eval" )
      default="${default%-enterprise-ltsc-eval}-ltsc" ;;
    *"-enterprise-iot-eval" )
      default="${default%-enterprise-iot-eval}-iot" ;;
    *"-eval" )
      default="${default%-eval}" ;;
  esac

  # Preserve a genuinely different DETECTED override.
  if [ -n "$current" ] && [[ "${current,,}" != "$default" ]]; then
    echo "$current"
    return 0
  fi

  # Select the answer-file identity for the source that actually succeeded.
  case "$source" in
    *"-enterprise-ltsc-eval" )
      detected="${source%-enterprise-ltsc-eval}-ltsc-eval" ;;
    *"-enterprise-iot-eval" )
      detected="${source%-enterprise-iot-eval}-iot-eval" ;;
    *"-eval" )
      detected="$source" ;;
    * )
      detected="${current:-$default}" ;;
  esac

  echo "$detected"
  return 0
}

downloadWindowsLtsc() {

  local id="$1"
  local lang="$2"
  local desc="$3"

  local alternate alternate_desc

  case "${id,,}" in
    "win11${PLATFORM,,}-enterprise-iot-eval" )
      alternate="win11${PLATFORM,,}-enterprise-ltsc-eval" ;;
    "win11${PLATFORM,,}-enterprise-ltsc-eval" )
      alternate="win11${PLATFORM,,}-enterprise-iot-eval" ;;
    * )
      error "Invalid VERSION specified, value \"$id\" is not recognized!"
      return 1 ;;
  esac

  # IoT and LTSC share related evaluation sources and may become unavailable
  # independently, so use the sibling edition as a compatibility fallback.
  if downloadWindowsEval "$id" "$lang" "$desc" > /dev/null 2>&1; then
    MIDO_SOURCE="$id"
    return 0
  fi

  alternate_desc=$(printEdition "$alternate" "$alternate" "Y")

  info "Primary download source failed, trying $alternate_desc instead..."

  if downloadWindowsEval "$alternate" "$lang" "$alternate_desc"; then
    MIDO_SOURCE="$alternate"
    warn "the requested $desc was unavailable, using $alternate_desc instead."
    return 0
  fi

  return 1
}

getWindows() {

  local version="$1"
  local lang="$2"
  local desc="$3"
  local web_desc="$4"

  local language edition

  MIDO_SOURCE=""
  MIDO_STATIC="N"

  language=$(getLanguage "$lang" "desc")
  edition=$(printEdition "$version" "$desc" "Y")

  local msg="Requesting $desc from the Microsoft servers..."
  local web_msg="Requesting $web_desc from the Microsoft servers..."
  info "$msg" && html "$web_msg"

  # These sources are only published in English, so avoid trying download
  # routes that cannot satisfy the requested language.
  case "${version,,}" in
    "win2008r2"* | \
    "win81${PLATFORM,,}"* | \
    "win10${PLATFORM,,}-enterprise"* | \
    "win11${PLATFORM,,}-enterprise-iot-eval" )
      if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then
        error "No download in the $language language available for $edition!"
        MIDO_URL=""
        return 1
      fi ;;
  esac

  # ARM64 downloads exist only for the explicitly supported Windows 11
  # routes; all other catalog entries remain x64-only.
  case "${version,,}" in
    "win10x64" ) ;;
    "win11${PLATFORM,,}" ) ;;
    "win11${PLATFORM,,}-enterprise"* ) ;;
    * )
      if [[ "${PLATFORM,,}" != "x64" ]]; then
        error "No download for the ${PLATFORM^^} platform available for $edition!"
        MIDO_URL=""
        return 1
      fi ;;
  esac

  # Prefer live Microsoft download routes. Unsupported or failed live routes
  # fall through to the configured static catalog below.
  case "${version,,}" in
    "win10x64" | "win11${PLATFORM,,}" )

      if downloadWindows "$version" "$lang" "$edition"; then
        MIDO_SOURCE="$version"
        return 0
      fi ;;

    "win11${PLATFORM,,}-enterprise-iot-eval" | \
    "win11${PLATFORM,,}-enterprise-ltsc-eval" )

      downloadWindowsLtsc "$version" "$lang" "$edition" && return 0 ;;

    "win11${PLATFORM,,}-enterprise"* )

      if downloadWindowsEval "$version" "$lang" "$edition"; then
        MIDO_SOURCE="$version"
        return 0
      fi ;;

    "win2025-eval" | "win2022-eval" | "win2019-eval" | \
    "win2019-hv" | "win2016-eval" | "win2012r2-eval" )

      if downloadWindowsEval "$version" "$lang" "$edition"; then
        MIDO_SOURCE="$version"
        return 0
      fi ;;

    "win2008r2"*| "win81${PLATFORM,,}"* | "win10${PLATFORM,,}-enterprise"* ) ;;

    * )
      error "Invalid VERSION specified, value \"$version\" is not recognized!"
      return 1 ;;
  esac

  # Static catalog URLs are the last resort after live Microsoft methods are
  # unavailable or have failed.
  MIDO_URL=$(getMido "$version" "$lang" "")
  [ -z "$MIDO_URL" ] && return 1

  MIDO_STATIC="Y"

  if [[ "${version,,}" == "win2008r2"* ]]; then
    MIDO_SOURCE="win2008r2-eval"
    return 0
  fi

  MIDO_SOURCE="$version"
  return 0
}

getBuild() {

  local id="$1"
  local ret="$2"
  local build="$3"

  local file="catalog.xml"
  local url="" name="" edition=""

  case "${id,,}" in
    "win11${PLATFORM,,}" )
      name="Windows 11 Pro"
      url="https://worproject.com/dldserv/esd/getcatalog.php?build=${build}&arch=${PLATFORM^^}&edition=Professional" ;;
    "win11${PLATFORM,,}-enterprise" | "win11${PLATFORM,,}-enterprise-eval")
      name="Windows 11 Enterprise"
      url="https://worproject.com/dldserv/esd/getcatalog.php?build=${build}&arch=${PLATFORM^^}&edition=Enterprise" ;;
  esac

  case "${ret,,}" in
    "url" ) echo "$url" ;;
    "file" ) echo "$file" ;;
    "name" ) echo "$name" ;;
    "edition" ) echo "$edition" ;;
    *) echo "";;
  esac

  return 0
}

getCatalog() {

  local id="$1"
  local ret="$2"

  local file="catalog.cab"
  local url="" name="" edition=""

  if [[ "${id,,}" == "win11"* ]] && ! isCompatible; then
    # ARMv8.0 cannot run Windows 11 builds 24H2 and up.
    getBuild "$1" "$2" "22631.2861" && return 0
  fi

  case "${id,,}" in
    "win11${PLATFORM,,}" )
      edition="Professional"
      name="Windows 11 Pro"
      url="https://go.microsoft.com/fwlink?linkid=2156292" ;;
    "win10${PLATFORM,,}" )
      edition="Professional"
      name="Windows 10 Pro"
      url="https://go.microsoft.com/fwlink/?LinkId=841361" ;;
    "win11${PLATFORM,,}-enterprise" | "win11${PLATFORM,,}-enterprise-eval")
      edition="Enterprise"
      name="Windows 11 Enterprise"
      url="https://go.microsoft.com/fwlink?linkid=2156292" ;;
    "win10${PLATFORM,,}-enterprise" | "win10${PLATFORM,,}-enterprise-eval" )
      edition="Enterprise"
      name="Windows 10 Enterprise"
      url="https://go.microsoft.com/fwlink/?LinkId=841361" ;;
  esac

  case "${ret,,}" in
    "url" ) echo "$url" ;;
    "file" ) echo "$file" ;;
    "name" ) echo "$name" ;;
    "edition" ) echo "$edition" ;;
    *) echo "";;
  esac

  return 0
}

parseESD() {

  local xml="$1"
  local version="$2"
  local lang="$3"
  local desc="$4"
  local edition="$5"
  local culture="$6"

  local xmlFile="${xml##*/}"  
  local file_path file_sum file_size file_edition
  local file_culture file_match=0 language_match=0
  local records architecture language separator=$'\x1f'

  ESD=""
  ESD_SUM=""
  ESD_SIZE=""

  # Microsoft catalogs have used different XML namespaces. Match elements by
  # local name and flatten the catalog once so selection needs no temporary XML.
  if ! records=$(xmlstarlet sel \
    -T -t \
    -m "//*[local-name()='File']" \
      -v "normalize-space(*[local-name()='Architecture'])" \
      -o "$separator" \
      -v "normalize-space(*[local-name()='Edition'])" \
      -o "$separator" \
      -v "normalize-space(*[local-name()='LanguageCode'])" \
      -o "$separator" \
      -v "normalize-space(*[local-name()='FilePath'])" \
      -o "$separator" \
      -v "normalize-space(*[local-name()='Sha1'])" \
      -o "$separator" \
      -v "normalize-space(*[local-name()='Size'])" \
      -n \
    "$xml" 2>/dev/null); then

    error "Failed to parse $xmlFile!"
    return 1
  fi

  # Track product/platform and language matches separately so failures can
  # distinguish an unavailable edition from an unavailable translation.
  while IFS="$separator" read -r \
    architecture file_edition file_culture \
    file_path file_sum file_size; do

    [ -n "$architecture$file_path$file_sum$file_size$file_culture$file_edition" ] || continue

    [ "${architecture,,}" = "${PLATFORM,,}" ] || continue

    if [ -n "$edition" ] &&
      [ "${file_edition,,}" != "${edition,,}" ]; then
      continue
    fi

    file_match=1

    [ "${file_culture,,}" = "${culture,,}" ] || continue

    language_match=1
    ESD="$file_path"
    ESD_SUM="$file_sum"
    ESD_SIZE="$file_size"
    break

  done <<< "$records"

  if (( ! file_match )); then
    desc=$(printEdition "$version" "$desc" "Y")
    error "No download link available for $desc!"
    return 1
  fi

  if (( ! language_match )); then
    desc=$(printEdition "$version" "$desc" "Y")
    language=$(getLanguage "$lang" "desc")
    error "No download in the $language language available for $desc!"
    return 1
  fi

  if [ -z "$ESD" ]; then
    error "Failed to find ESD URL in $xmlFile!"
    return 1
  fi

  if [ -z "$ESD_SUM" ]; then
    error "Failed to find ESD checksum in $xmlFile!"
    return 1
  fi

  if [ -z "$ESD_SIZE" ]; then
    error "Failed to find ESD filesize in $xmlFile!"
    return 1
  fi

  return 0
}

getESD() {

  local dir="$1"
  local version="$2"
  local lang="$3"
  local desc="$4"

  local file culture log
  local edition catalog rc=0
  local xmlFile="products.xml"

  file=$(getCatalog "$version" "file")
  catalog=$(getCatalog "$version" "url")
  culture=$(getLanguage "$lang" "culture")
  edition=$(getCatalog "$version" "edition")

  if [ -z "$file" ] || [ -z "$catalog" ]; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!"
    return 1
  fi

  local msg="Downloading catalog from the Microsoft servers..."
  info "$msg" && html "$msg"

  rm -rf "$dir"

  if ! makeDir "$dir"; then
    error "Failed to create directory \"$dir\" !"
    return 1
  fi

  if ! log=$(mktemp -p "$QEMU_DIR"); then
    error "Failed to create a temporary wget log."
    return 1
  fi

  # Preserve wget's status under errexit so its log can provide the actual
  # server or filesystem failure reason.
  {
    LC_ALL=C wget "$catalog" -O "$dir/$file" --no-verbose --timeout=30 \
      --no-http-keep-alive --output-file="$log"
    rc=$?
  } || :

  if (( rc != 0 )); then

    local reason
    reason=$(sed -n \
      -e 's/^wget: //p' \
      -e 's/^[0-9-]\{10\} [0-9:]\{8\} ERROR //p' \
      "$log" | tail -n 1)

    msg="Failed to download $catalog"

    if (( rc == 3 )); then
      error "$msg because the file could not be written (disk full?)."
    elif [ -n "$reason" ]; then
      error "$msg: ${reason%.}."
    else
      error "$msg with exit status $rc."
    fi

    rm -f "$log"
    return 1
  fi

  rm -f "$log"

  # Normal catalogs arrive as CAB archives, while pinned build catalogs are
  # already XML and only need the common filename.
  if [[ "$file" == *".xml" ]]; then

    if ! mv -f "$dir/$file" "$dir/$xmlFile"; then
      error "Failed to rename $file to $xmlFile."
      return 1
    fi

  else

    if ! (
      cd "$dir" || exit 1
      cabextract "$file" > /dev/null
    ); then
      error "Failed to extract $file!"
      return 1
    fi

  fi

  if [ ! -s "$dir/$xmlFile" ]; then
    error "Failed to find $xmlFile in $file!"
    return 1
  fi

  if ! parseESD \
    "$dir/$xmlFile" "$version" "$lang" "$desc" "$edition" "$culture"; then
    return 1
  fi

  rm -rf "$dir"
  return 0
}

isCompressed() {

  local url="${1%%\?*}"

  # The ReactOS latest-build endpoint returns an archive without a filename
  # extension, so recognize its path explicitly.
  case "${url,,}" in
    *.7z | *.zip | *.rar | *.tar | *.cab | *.cpio | \
    *.lzh | *.lha | *.xar | */latest-x86-gcc-lin-rel )
      return 0 ;;
  esac

  return 1
}

verifyFile() {

  local iso="$1"
  local size="$2"
  local total="$3"
  local check="$4"

  if [ -n "$size" ] && [[ "$total" != "$size" && "$size" != "0" ]]; then
    if enabled "$VERIFY" || enabled "$DEBUG"; then
      warn "The downloaded file has a different size ( $total bytes) than expected ( $size bytes). Please report this at $SUPPORT/issues"
    fi
  fi

  local algo="SHA256"
  local hash

  [ -z "$check" ] && return 0
  enabled "$VERIFY" || return 0

  # Microsoft ESD catalogs publish SHA1, while current mirror metadata normally
  # uses SHA256; the digest length identifies which algorithm is required.
  [[ "${#check}" == "40" ]] && algo="SHA1"

  local msg="Verifying downloaded ISO..."
  info "$msg" && html "$msg"

  if [[ "${algo,,}" != "sha256" ]]; then

    hash=$(sha1sum "$iso" | cut -f1 -d' ') || {
      local rc=$?

      if (( rc >= 129 )); then
        exit "$rc"
      fi

      error "Failed to calculate SHA1 checksum for $iso!"
      return 1
    }

  else

    hash=$(sha256sum "$iso" | cut -f1 -d' ') || {
      local rc=$?

      if (( rc >= 129 )); then
        exit "$rc"
      fi

      error "Failed to calculate SHA256 checksum for $iso!"
      return 1
    }

  fi

  if [[ "$hash" == "$check" ]]; then
    info "Successfully verified ISO!" && return 0
  fi

  error "The downloaded file has an unknown $algo checksum: $hash , as the expected value was: $check. Please report this at $SUPPORT/issues"
  return 1
}

downloadFile() {

  local iso="$1"
  local url="$2"
  local size="$3"
  local desc="$4"
  local web_desc="$5"
  local connections="${6:-1}"

  local domain dots
  local msg="Downloading $web_desc"
  local console_msg="Downloading $desc"

  # Keep mirror messages concise by reducing subdomains to the final two
  # labels, while Microsoft downloads retain the generic description.
  domain=$(echo "$url" | awk -F/ '{print $3}')
  dots=$(echo "$domain" | tr -cd '.' | wc -c)
  (( dots > 1 )) && domain=$(expr "$domain" : '.*\.\(.*\..*\)')

  if [ -n "$domain" ] && [[ "${domain,,}" != *"microsoft.com" ]]; then
    console_msg="Downloading $desc from $domain"
  fi

  info "$console_msg..."

  downloadToFile \
    "$url" \
    "$iso" \
    "$msg" \
    "${size:-0}" \
    "$connections" \
    "Y"
}

tryDownload() {

  local iso="$1"
  local url="$2"
  local sum="$3"
  local size="$4"
  local desc="$6"
  local seconds="$7"
  local web_desc="$8"

  local total minimum="104857600"

  # Compressed archives can legitimately be much smaller than the ISO they
  # contain, so use a lower sanity threshold until extraction.
  if isCompressed "$url"; then
    minimum="10485760"
  fi

  if downloadRetry \
      "$iso" \
      "${CONNECTIONS:-1}" \
      "$seconds" \
      "$desc" \
      "$minimum" \
      "$iso" \
      "$url" \
      "$size" \
      "$desc" \
      "$web_desc"; then
    local rc=0
  else
    local rc=$?
  fi

  (( rc == 0 )) || return "$rc"

  # The shared helper already inspected the file, so this should
  # only fail if the downloaded file was removed unexpectedly afterward.
  if ! total=$(stat -c%s -- "$iso" 2>/dev/null); then
    error "Failed to determine downloaded file size: $iso"
    return 1
  fi

  # Status 2 means the completed download failed deterministic validation.
  if ! verifyFile "$iso" "$size" "$total" "$sum"; then
    if ! rm -f -- "$iso" "$iso.aria2"; then
      warn "failed to remove invalid download \"$iso\"!"
    fi
    return 2
  fi

  # Extract the .iso from the compressed archive if needed.
  isCompressed "$url" && UNPACK="Y"

  return 0
}

fallbackEnglish() {

  local iso="$1"
  local version="$2"
  local lang="$3"
  local desc="$4"
  local web_desc="$5"

  local culture web_msg
  local msg="No working download method was found for $desc, falling back to English..."

  info "$msg"

  # Preserve the requested regional format and keyboard layout.
  culture=$(getLanguage "$lang" "culture")
  [ -z "$REGION" ] && REGION="$culture"
  [ -z "$KEYBOARD" ] && KEYBOARD="$culture"

  # Keep the original language-specific ISO filename so that restarts
  # still locate the same image, but use English installation media.
  LANGUAGE="en"

  if ! rm -f -- "$iso"; then
    error "Failed to remove ISO file \"$iso\" !"
    return 1
  fi

  downloadImage "$iso" "$version" "$LANGUAGE"
}

downloadImage() {

  local iso="$1"
  local version="$2"
  local lang="$3"

  local detected="$DETECTED"
  local requested="$version" switched=""  
  local tried="n" success="n" seconds="5"
  local i url sum size base language desc web_desc

  if [[ "${version,,}" == "http"* ]]; then

    base=$(basename "$iso")
    desc=$(fromFile "$base")
    web_desc="$desc"

    tryDownload "$iso" "$version" "" "" "" "$desc" "$seconds" "$web_desc" || return 1
    return 0
  fi

  if ! validVersion "$version" "en"; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!"
    return 1
  fi

  desc=$(printVariant "$version" "" "Y")
  web_desc=$(printVariant "$version" "")

  if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then

    language=$(getLanguage "$lang" "desc")

    if ! validVersion "$version" "$lang"; then

      desc=$(printEdition "$version" "$desc" "Y")
      web_desc=$(printEdition "$version" "$web_desc")
      desc+=" in $language"

      fallbackEnglish "$iso" "$version" "$lang" "$desc" "$web_desc" || return 1
      return 0

    fi

    desc+=" in $language"
  fi

  # Prefer a live Microsoft URL and retry link generation once before moving
  # on to ESD catalogs or mirrors.
  if isMido "$version" "$lang"; then

    tried="y"
    success="n"

    if getWindows "$version" "$lang" "$desc" "$web_desc"; then
      success="y"
    else
      delay "$seconds"
      getWindows "$version" "$lang" "$desc" "$web_desc" && success="y"
    fi

    if [[ "$success" == "y" ]]; then

      detected=$(getMidoDetected "$version" "$MIDO_SOURCE" "$DETECTED")
      url=$(getMido "$version" "$lang" "")

      sum=""
      size=""

      # Apply the metadata belonging to the configured static URL.
      if [[ "${MIDO_URL%%\?*}" == "${url%%\?*}" ]]; then
        size=$(getMido "$version" "$lang" "size")
        sum=$(getMido "$version" "$lang" "sum")
      fi

      local download_desc="$desc"
      if enabled "$MIDO_STATIC"; then
        download_desc+=" using a static link"
      fi

      if tryDownload "$iso" "$MIDO_URL" "$sum" "$size" "$lang" "$download_desc" "$seconds" "$web_desc"; then
        # Commit the candidate only after the image was downloaded and verified.
        DETECTED="$detected"
        return 0
      fi

    fi
  fi

  # If an evaluation version was requested, switch to the 
  # normal edition since none of our mirrors provide those.
  if switched=$(switchEdition "$version"); then

    version="$switched"

    if ! enabled "${DETECTED_ORG:-}"; then
      DETECTED="${SUGGEST:-$version}"
    fi

    desc=$(printVariant "$DETECTED" "" "Y")
    web_desc=$(printVariant "$DETECTED" "")

    if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then
      desc+=" in $language"
    fi

  fi

  if isESD "$version" "$lang"; then

    if [[ "$tried" != "n" ]]; then
      info "Failed to download $desc, will try a different method now..."
    fi

    tried="y"
    success="n"

    if getESD "$TMP/esd" "$version" "$lang" "$desc"; then
      success="y"
    else
      delay "$seconds"
      getESD "$TMP/esd" "$version" "$lang" "$desc" && success="y"
    fi

    if [[ "$success" == "y" ]]; then

      # Standalone ESD media requires a different extraction path, so expose
      # its real extension through the active ISO variable.
      ISO="${ISO%.*}.esd"

      if tryDownload "$ISO" "$ESD" "$ESD_SUM" "$ESD_SIZE" "$lang" "$desc" "$seconds" "$web_desc"; then
        return 0
      fi

      ISO="$iso"

    fi
  fi

  for ((i=1; i<=MIRRORS; i++)); do

    url=$(getLink "$i" "$version" "$lang")

    if [ -n "$url" ]; then

      if [[ "$tried" != "n" ]]; then
        info "Failed to download $desc, will try another mirror now..."
      fi

      tried="y"
      size=$(getSize "$i" "$version" "$lang")
      sum=$(getHash "$i" "$version" "$lang")

      tryDownload "$iso" "$url" "$sum" "$size" "$lang" "$desc" "$seconds" "$web_desc" && return 0

    fi

  done

  if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then
    fallbackEnglish "$iso" "$requested" "$lang" "$desc" "$web_desc" || return 1
    return 0
  fi

  if [[ "$tried" == "n" ]]; then
    error "No download method is available for $desc!"
  fi

  return 1
}

return 0
