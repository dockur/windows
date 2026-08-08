#!/usr/bin/env bash
set -Eeuo pipefail

handleCurlError() {

  local code="$1"
  local server="$2"
  local reason="${3:-}"

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

      local signal
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
    handleCurlError "$rc" "$server" "$reason" || :

    (( rc >= 129 )) && return "$rc"
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
    -- "$vlsUrl" || return

  # Complete Microsoft's ov-df challenge by retrieving a token and timing
  # value, then returning both with the current timestamp.

  local instance="560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175"
  local ovUrl="https://ov-df.microsoft.com/mdt.js?instanceId=$instance&PageId=si&session_id=$session"

  enabled "$DEBUG" && echo -n "Getting OV data: "

  ovData=$(curlRequest "Microsoft" "$agent" \
    --header "Accept:" \
    --max-filesize 1M \
    -- "$ovUrl") || return

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
    -- "$ovUrl" || return

  enabled "$DEBUG" && echo -n "Getting language SKU ID: "

  local skuUrl="https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$profile&ProductEditionId=$productId&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$session"

  skuJson=$(curlRequest "Microsoft" "$agent" \
    --referer "$url" \
    --header "Accept:" \
    --max-filesize 100K \
    -- "$skuUrl") || return

  skuId=$(printf '%s\n' "$skuJson" | jq --arg LANG "$language" -r 'first(.Skus[]? | select(.Language == $LANG) | .Id) // empty') 2>/dev/null || skuId=""

  if [ -z "$skuId" ] || [[ "${skuId,,}" == "null" ]]; then
    if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then
      language=$(getLanguage "$lang" "desc")
      error "No download in the $language language available for $desc!"
    else
      error "Microsoft server provided us no SKU ID in response to our request!"
      info "Response: $skuJson"
    fi
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
    -- "$linkUrl") || return

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

  link=$(printf '%s\n' "$linkJson" | jq --argjson TYPE "$type" -r 'first(.ProductDownloadOptions[]? | select(.DownloadType == $TYPE) | .Uri) // empty') 2>/dev/null || link=""

  if [ -z "$link" ] || [[ "${link,,}" == "null" ]]; then
    error "Microsoft server provided us no download link to our request for an automated download!"
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

  local agent language page rc
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
  else
    rc=$?
    (( rc == 1 )) || return "$rc"
  fi

  sleep 1 || return

  # Product edition IDs can change. If the configured ID fails, recover the
  # current value from Microsoft's public download page and retry once.
  local msg="retrying using a different method..."
  info "Microsoft download request failed, $msg"
  enabled "$DEBUG" && echo "Parsing download page: ${url}"

  page=$(curlRequest "Microsoft" "$agent" \
    --header "Accept:" \
    --max-filesize 1M \
    -- "$url") || return

  enabled "$DEBUG" && echo -n "Getting Product edition ID: "
  productId=$(printf '%s' "$page" |
    tr '\r\n' '  ' |
    grep -Eio "<option[^>]*value=[\"'][0-9]+[\"'][^>]*>[[:space:]]*Windows[^<]*" |
    sed -nE "s/.*value=[\"']([0-9]+)[\"'].*/\1/p" |
    sed -n '1p' |
    cut -c 1-16) || return
  enabled "$DEBUG" && echo "$productId"

  if [ -z "$productId" ]; then
    info "Failed to fetch the Product edition ID from the download page, $msg"
    return 1
  fi

  downloadWindowsLink "$productId" "$url" "$agent" "$language" "$lang" "$desc" "$type" || return

  return 0
}

downloadWindowsEval() {

  local id="$1"
  local lang="$2"
  local desc="$3"

  local compare compare_name link_name
  local agent culture language type winVer rc

  case "${id,,}" in
    "win11${PLATFORM,,}-enterprise-eval" )
      type="enterprise"
      winVer="windows-11-enterprise" ;;
    "win11${PLATFORM,,}-enterprise-iot-eval" )
      type="iot"
      winVer="windows-11-iot-enterprise-ltsc-eval" ;;
    "win11${PLATFORM,,}-enterprise-ltsc-eval" )
      if [[ "${PLATFORM,,}" == "arm64" ]]; then
        type="iot"
        winVer="windows-11-iot-enterprise-ltsc-eval"
      else
        type="ltsc"
        winVer="windows-11-enterprise"
      fi ;;
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

  local country="${culture##*-}"
  local -a culture_keys=() link_list=()
  local candidate culture_key key redirect redirect_key
  local link="" link_index=-1 links page matched all_links
  local url="https://www.microsoft.com/en-us/evalcenter/download-$winVer"

  enabled "$DEBUG" && echo "Parsing download page: ${url}"

  page=$(curlRequest "Microsoft" "$agent" \
    --location \
    --max-filesize 1M \
    -- "$url") || return

  if ! [ "$page" ]; then
    error "Evaluation Center download page gave us an empty response"
    return 1
  fi

  enabled "$DEBUG" && echo "Getting download link.."

  # Normalize HTML-encoded query separators before extracting fwlinks.
  page=${page//&amp;/\&}
  page=${page//&#38;/\&}

  all_links=$(printf '%s\n' "$page" |
    grep -Eio "https://go\.microsoft\.com/fwlink(/p)?/\?[^\"'<>[:space:]]+" |
    awk 'NF && !seen[$0]++') || {
    error "Evaluation Center download page gave us no download link!"
    return 1
  }

  # Older Evaluation Center pages identify the language directly in the
  # fwlink query. Keep that efficient path when those parameters are usable.
  links=$(printf '%s\n' "$all_links" |
    grep -Ei '(^|[?&])culture='"${culture,,}"'(&|$)' |
    grep -Ei '(^|[?&])country='"${country,,}"'(&|$)') || links=""

  if [ -z "$links" ]; then

    culture_key="${culture,,}"
    culture_key="${culture_key//[^[:alnum:]]/}"
    culture_keys=("$culture_key")

    case "$culture_key" in
      "jajp" ) culture_keys+=("jpjp") ;;
      "zhtw" ) culture_keys+=("cntw") ;;
    esac

    # Current Evaluation Center pages reuse en-US query parameters for every
    # language. Their first redirect target still carries the actual locale,
    # so inspect that target without following the complete download chain.
    while IFS= read -r candidate; do

      [ -n "$candidate" ] || continue

      redirect=$(curlRequest "Microsoft" "$agent" \
        --output /dev/null \
        --write-out "%{redirect_url}" \
        --head \
        -- "$candidate") || {
          rc=$?
          (( rc == 1 )) || return "$rc"
          continue
        }

      [ -n "$redirect" ] || continue

      # Match against the complete redirect URL so locale path segments are
      # recognized as well as locale markers in the target filename.
      redirect_key="${redirect%%[?#]*}"
      redirect_key="${redirect_key,,}"
      redirect_key="${redirect_key//[^[:alnum:]]/}"
      matched=""

      for key in "${culture_keys[@]}"; do
        [[ "$redirect_key" == *"$key"* ]] || continue
        matched="Y"
        break
      done

      [ -n "$matched" ] || continue

      [ -n "$links" ] && links+=$'\n'
      links+="$candidate"

    done <<< "$all_links"

  fi

  if [ -z "$links" ]; then
    # Distinguish a changed or missing English page from an unavailable
    # translation for an otherwise supported product.
    if [[ "${lang,,}" == "en" || "${lang,,}" == "en-"* ]]; then
      error "Evaluation Center download page gave us no download link!"
    else
      language=$(getLanguage "$lang" "desc")
      error "No download in the $language language available for $desc!"
    fi
    return 1
  fi

  mapfile -t link_list <<< "$links"

  # Evaluation pages currently expose several matching fwlinks in a known
  # product/platform order, so select the entry for the requested variant.
  case "$type" in
    "iot" )
      case "${PLATFORM,,}" in
        "x64" )
          link_index=0 ;;
        "arm64" )
          link_index=1 ;;
      esac ;;
    "ltsc" )
      case "${PLATFORM,,}" in
        "x64" )
          link_index=1 ;;
      esac ;;
    "enterprise" )
      case "${PLATFORM,,}" in
        "x64" )
          if [[ "$winVer" != "windows-10"* ]]; then
            link_index=0
          else
            link_index=1
          fi ;;
        "arm64" )
          link_index=1 ;;
      esac ;;
    "server" )
      case "${PLATFORM,,}" in
        "x64" )
          link_index=0 ;;
      esac ;;
    * )
      error "Invalid type specified, value \"$type\" is not recognized!" && return 1 ;;
  esac

  if (( link_index < 0 || link_index >= ${#link_list[@]} )); then
    error "Could not find the requested download link on the Evaluation Center page!"
    return 1
  fi

  link="${link_list[$link_index]}"

  # Resolve the fwlink now so later logging and platform validation use the
  # actual ISO URL rather than Microsoft's generic redirect.

  link=$(curlRequest "Microsoft" "$agent" \
    --location \
    --output /dev/null \
    --write-out "%{url_effective}" \
    --head \
    -- "$link") || return

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

getWindows() {

  local version="$1"
  local lang="$2"
  local desc="$3"
  local web_desc="$4"

  local language edition rc

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
    "win10${PLATFORM,,}-enterprise-ltsc-eval" | \
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
        return 0
      else
        rc=$?
      fi
      
      (( rc == 1 )) || return "$rc" ;;

    "win11${PLATFORM,,}-enterprise"* )

      if downloadWindowsEval "$version" "$lang" "$edition"; then
        return 0
      else
        rc=$?
      fi
      
      (( rc == 1 )) || return "$rc" ;;

    "win2025-eval" | "win2022-eval" | "win2019-eval" | \
    "win2019-hv" | "win2016-eval" | "win2012r2-eval" )

      if downloadWindowsEval "$version" "$lang" "$edition"; then
        return 0
      else
        rc=$?
      fi
      
      (( rc == 1 )) || return "$rc" ;;

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

  return 0
}

getCatalog() {

  local id="$1"
  local ret="$2"
  local source="${3:-microsoft}"

  local file="catalog.cab"
  local url="" name="" edition=""

  if [[ "${id,,}" == "win11"* ]] && ! isCompatible; then
    # ARMv8.0 cannot run Windows 11 builds 24H2 and up.
    getWorCatalog "$1" "$2" "22631.2861" && return 0
  fi

  if [[ "${source,,}" == "wor" ]]; then
    getWorCatalog "$1" "$2" && return 0
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

getWorCatalog() {

  local id="$1"
  local ret="$2"
  local build="${3:-}"

  local file="catalog.xml"
  local name="" filter="" url=""
  local version="" edition="" arch=""

  case "${PLATFORM,,}" in
    "x64" ) arch="x64" ;;
    "arm64" ) arch="ARM64" ;;
  esac

  case "${id,,}" in
    "win11${PLATFORM,,}" )
      version="11"
      filter="Professional"
      name="Windows 11 Pro" ;;
    "win10${PLATFORM,,}" )
      version="10"
      filter="Professional"
      name="Windows 10 Pro" ;;
    "win11${PLATFORM,,}-enterprise" | "win11${PLATFORM,,}-enterprise-eval")
      version="11"
      filter="Enterprise"
      name="Windows 11 Enterprise" ;;
    "win10${PLATFORM,,}-enterprise" | "win10${PLATFORM,,}-enterprise-eval" )
      version="10"
      filter="Enterprise"
      name="Windows 10 Enterprise" ;;
  esac

  if [ -n "$version" ] && [ -n "$arch" ]; then
    url="https://worproject.com/dldserv/esd/getcatalog.php?ver=${version}&arch=${arch}&edition=${filter}"
    [ -n "$build" ] && url+="&build=${build}"
  fi

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
  local file_size file_edition file_culture
  local file_path file_sum file_sha1 file_sha256
  local file_match=0 language_match=0
  local records architecture language separator=$'\x1f'
  local upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local lower="abcdefghijklmnopqrstuvwxyz"

  ESD=""
  ESD_SUM=""
  ESD_SIZE=""

  # Microsoft catalogs may use different XML namespaces, tag casing, and checksum
  # algorithms. Flatten the catalog once so all selection logic remains in Bash.
  local lname="translate(local-name(), '$upper', '$lower')"

  if ! records=$(xmlstarlet sel -T -t \
      -m "//*[$lname='file']" \
        -v "normalize-space(*[$lname='architecture'][1])" -o "$separator" \
        -v "normalize-space(*[$lname='edition'][1])" -o "$separator" \
        -v "normalize-space(*[$lname='languagecode'][1])" -o "$separator" \
        -v "normalize-space(*[$lname='filepath'][1])" -o "$separator" \
        -v "normalize-space(*[$lname='sha256'][1])" -o "$separator" \
        -v "normalize-space(*[$lname='sha1'][1])" -o "$separator" \
        -v "normalize-space(*[$lname='size'][1])" \
        -n \
      "$xml" 2>/dev/null); then

    error "Failed to parse $xmlFile!"
    return 1
  fi

  # Track product/platform and language matches separately so failures can
  # distinguish an unavailable edition from an unavailable translation.
  while IFS="$separator" read -r \
    architecture file_edition file_culture \
    file_path file_sha256 file_sha1 file_size; do

    [ -n "$architecture$file_path$file_sha256$file_sha1$file_size$file_culture$file_edition" ] || continue

    [ "${architecture,,}" = "${PLATFORM,,}" ] || continue

    if [ -n "$edition" ] &&
      [ "${file_edition,,}" != "${edition,,}" ]; then
      continue
    fi

    file_match=1

    [ "${file_culture,,}" = "${culture,,}" ] || continue

    language_match=1
    file_sum="${file_sha256:-$file_sha1}"

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

getCatalogError() {

  local file="$1"
  local result=""

  [ -s "$file" ] || return 0

  # Prefer leaf text when the response is parseable XML, separating adjacent
  # elements so HTML error pages remain readable. Fall back to the beginning
  # of a plain-text response when XML parsing fails.
  result=$(xmlstarlet sel -T -t \
    -m '//*[not(*) and normalize-space()]' \
      -v 'normalize-space(.)' -o ' ' \
    "$file" 2>/dev/null) || result=$(head -c 1024 -- "$file" 2>/dev/null || :)

  # Keep upstream error details useful without allowing control sequences,
  # multiline output, or a complete HTML error page into the application log.
  result=$(
    printf '%s' "$result" | \
      LC_ALL=C tr -cd '\11\12\15\40-\176' | \
      sed 's/<[^>]*>/ /g' | tr '\r\n\t' '   ' | \
      sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
  )

  if (( ${#result} > 500 )); then
    result="${result:0:500}..."
  fi

  printf '%s' "$result"
  return 0
}

validateESDCatalog() {

  local xml="$1"
  local provider="$2"

  local metadata root fileCount 
  local separator=$'\x1f' response
  local upper='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  local lower='abcdefghijklmnopqrstuvwxyz'

  if [ ! -s "$xml" ]; then
    error "$provider returned an empty ESD catalog!"
    return 1
  fi

  # Successful Microsoft and WoR responses contain an MCT document with at
  # least one File record. Reject API error tokens and unrelated XML before
  # parseESD can misreport them as a products.xml parsing failure.
  if metadata=$(xmlstarlet sel \
      -T -t \
      -v "translate(local-name(/*), '$upper', '$lower')" -o "$separator" \
      -v "count(/*[translate(local-name(), '$upper', '$lower')='mct']//*[translate(local-name(), '$upper', '$lower')='file'])" \
      "$xml" 2>/dev/null); then

    IFS="$separator" read -r root fileCount <<< "$metadata"

    if [ "$root" = "mct" ] &&
        [[ "$fileCount" =~ ^[0-9]+$ ]] &&
        (( fileCount > 0 )); then
      return 0
    fi

  fi

  response=$(getCatalogError "$xml") || response=""

  if [ -n "$response" ]; then
    error "$provider returned: $response"
  else
    error "$provider returned an invalid ESD catalog!"
  fi

  return 1
}

getESD() {

  local dir="$1"
  local version="$2"
  local lang="$3"
  local desc="$4"
  local source="${5:-microsoft}"

  local xmlFile="products.xml"
  local file culture provider
  local edition catalog log rc=0

  culture=$(getLanguage "$lang" "culture")
  file=$(getCatalog "$version" "file" "$source")
  catalog=$(getCatalog "$version" "url" "$source")
  edition=$(getCatalog "$version" "edition" "$source")

  if [ -z "$file" ] || [ -z "$catalog" ]; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!"
    return 1
  fi

  provider="Microsoft"
  [[ "${file,,}" == *.xml ]] && provider="WoR"

  local msg="Downloading ESD catalog..."
  info "$msg" && html "$msg"

  if ! rm -rf "$dir"; then
    error "Failed to remove directory \"$dir\" !"
    return 1
  fi

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

    (( rc >= 129 )) && return "$rc"
    return 1
  fi

  rm -f "$log"

  # Microsoft catalogs arrive as CAB archives. WoR catalogs are returned as
  # XML and must be validated before they are published as products.xml.
  if [[ "${file,,}" == *.xml ]]; then

    validateESDCatalog "$dir/$file" "$provider" || return 1

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

  # Validate extracted Microsoft catalogs as well, so parseESD only receives
  # the catalog format it expects.
  if [[ "${file,,}" != *.xml ]]; then
    validateESDCatalog "$dir/$xmlFile" "$provider" || return 1
  fi

  if ! parseESD "$dir/$xmlFile" "$version" "$lang" "$desc" "$edition" "$culture"; then
    return 1
  fi

  rm -rf "$dir"
  return 0
}

isCompressed() {

  local url="${1%%[\?#]*}"
  local file

  file=$(basename "$url")
  printf -v file '%b' "${file//%/\\x}"

  # The ReactOS latest-build endpoint returns an archive without a filename
  # extension, so recognize its path explicitly.
  case "${file,,}" in
    *.7z | *.zip | *.rar | *.tar | *.cab | *.cpio | \
    *.lzh | *.lha | *.xar )
      return 0 ;;
  esac

  case "${url,,}" in
    */latest-x86-gcc-lin-rel ) return 0 ;;
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

  local type="ISO" algo="SHA256" hash

  [ -z "$check" ] && return 0
  enabled "$VERIFY" || return 0

  # Microsoft ESD catalogs publish SHA1, while current mirror metadata normally
  # uses SHA256; the digest length identifies which algorithm is required.
  [[ "${#check}" == "40" ]] && algo="SHA1"
  [[ "${iso,,}" == *.esd ]] && type="ESD file"

  local msg="Verifying downloaded $type..."
  info "$msg" && html "$msg"

  if [[ "${algo,,}" != "sha256" ]]; then

    hash=$(sha1sum "$iso" | cut -f1 -d' ') || {
      local rc=$?
      error "Failed to calculate SHA1 checksum for $iso!"
      return "$rc"
    }

  else

    hash=$(sha256sum "$iso" | cut -f1 -d' ') || {
      local rc=$?
      error "Failed to calculate SHA256 checksum for $iso!"
      return "$rc"
    }

  fi

  if [[ "${hash,,}" == "${check,,}" ]]; then
    info "Successfully verified $type!" && return 0
  fi

  warn "the downloaded file has an unknown $algo checksum: $hash , as the expected value was: $check. Please report this at $SUPPORT/issues"
  return 1
}

downloadFile() {

  local iso="$1"
  local url="$2"
  local size="$3"
  local desc="$4"
  local web_desc="$5"
  local connections="${6:-1}"

  local domain parent
  local msg="Downloading $web_desc"
  local console_msg="Downloading $desc"

  # Keep mirror messages concise by reducing subdomains to the final two
  # labels, while Microsoft downloads retain the generic description.
  domain="${url#*://}"
  domain="${domain%%/*}"

  if [[ "$domain" == *.*.* ]]; then
    parent="${domain#*.}"
    [ -n "$parent" ] && domain="$parent"
  fi

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
  local desc="$5"
  local seconds="$6"
  local web_desc="$7"

  local total minimum="104857600"

  if [ -z "$iso" ] || [ -z "$url" ]; then
    error "Invalid download parameters!"
    return 1
  fi
  
  # Compressed archives can legitimately be much smaller than the ISO they
  # contain, so use a lower sanity threshold until extraction.
  if isCompressed "$url"; then
    minimum="10485760"
  fi

  downloadRetry \
    "$iso" \
    "${CONNECTIONS:-1}" \
    "$seconds" \
    "$desc" \
    "$minimum" \
    "$iso" \
    "$url" \
    "$size" \
    "$desc" \
    "$web_desc" || return

  # The shared helper already inspected the file, so this should
  # only fail if the downloaded file was removed unexpectedly afterward.
  if ! total=$(stat -c%s -- "$iso" 2>/dev/null); then
    error "Failed to determine downloaded file size: $iso"
    return 1
  fi

  # Status 2 means the completed download failed deterministic validation.
  verifyFile "$iso" "$size" "$total" "$sum" || {
    local rc=$?
    (( rc == 1 )) || return "$rc"

    if ! rm -f -- "$iso" "$iso.aria2"; then
      warn "failed to remove invalid download \"$iso\"!"
    fi

    return 2
  }

  # Extract the .iso from the compressed archive if needed.
  isCompressed "$url" && UNPACK="Y"

  return 0
}

fallbackEnglish() {

  local iso="$1"
  local version="$2"
  local lang="$3"
  local desc="$4"

  local culture
  local msg="No working download method was found for $desc, falling back to English..."

  info "$msg"

  # Preserve the requested regional format and keyboard layout.
  culture=$(getLanguage "$lang" "culture")
  [ -z "$REGION" ] && REGION="$culture"
  [ -z "$KEYBOARD" ] && KEYBOARD="$culture"

  # Keep the original language-specific ISO filename so that restarts
  # still locate the same image, but use English installation media.
  LANGUAGE="en"

  removeImage "$iso" || return

  downloadImage "$iso" "$version" "$LANGUAGE"
}

validDownload() {

  local version="$1"

  if [ -z "$version" ]; then
    error "Cannot download a Windows image without a version!"
    return 1
  fi

  if ! validVersion "$version" "en"; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!"
    return 1
  fi

  return 0
}

downloadImage() {

  local iso="$1"
  local version="$2"
  local lang="$3"

  local requested="$version"
  local tried="n" success="n" seconds="5"
  local i url sum size base language desc web_desc rc

  if [[ "${version,,}" == "http"* ]]; then

    base=$(basename "$iso")
    desc=$(fromFile "$base")
    web_desc="$desc"

    tryDownload "$iso" "$version" "" "" "$desc" "$seconds" "$web_desc" || {
      rc=$?
      error "Failed to download the Windows image from the specified URL!"
      return "$rc"
    }

    return 0
  fi

  validDownload "$version" || return 1

  desc=$(printVariant "$version" "" "Y")
  web_desc=$(printVariant "$version" "")

  if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then

    language=$(getLanguage "$lang" "desc")

    if ! validVersion "$version" "$lang"; then

      desc=$(printEdition "$version" "$desc" "Y")
      web_desc=$(printEdition "$version" "$web_desc")
      desc+=" in $language"

      fallbackEnglish "$iso" "$version" "$lang" "$desc" || return
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
      rc=$?
      (( rc == 1 )) || return "$rc"

      delay "$seconds" || return

      if getWindows "$version" "$lang" "$desc" "$web_desc"; then
        success="y"
      else
        rc=$?
        (( rc == 1 )) || return "$rc"
      fi
    fi

    if [[ "$success" == "y" ]]; then

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

      if tryDownload "$iso" "$MIDO_URL" "$sum" "$size" "$download_desc" "$seconds" "$web_desc"; then
        return 0
      else
        rc=$?
        (( rc == 1 || rc == 2 )) || return "$rc"
      fi

    fi
  fi

  # If an evaluation version was requested, switch to the 
  # normal edition since none of our mirrors provide those.
  if [[ "${version,,}" == *"-eval" ]]; then

    version="${version::-5}"
    validDownload "$version" || return 1

    [ -n "$DETECTED" ] || DETECTED="$version"

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
      rc=$?
      (( rc == 1 )) || return "$rc"

      if getESD "$TMP/esd" "$version" "$lang" "$desc" "wor"; then
        success="y"
      else
        rc=$?
        (( rc == 1 )) || return "$rc"
      fi
    fi

    if [[ "$success" == "y" ]]; then

      # Standalone ESD media requires a different extraction path, so expose
      # its real extension through the active ISO variable.
      ISO="${ISO%.*}.esd"

      if tryDownload "$ISO" "$ESD" "$ESD_SUM" "$ESD_SIZE" "$desc" "$seconds" "$web_desc"; then
        return 0
      else
        rc=$?
        (( rc == 1 || rc == 2 )) || return "$rc"
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

      if tryDownload "$iso" "$url" "$sum" "$size" "$desc" "$seconds" "$web_desc"; then
        return 0
      else
        rc=$?
        (( rc == 1 || rc == 2 )) || return "$rc"
      fi

    fi

  done

  if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then
    fallbackEnglish "$iso" "$requested" "$lang" "$desc" || return
    return 0
  fi

  if [[ "$tried" == "n" ]]; then
    error "No download method is available for $desc!"
  else
    error "All download methods failed for $desc!"
  fi

  return 1
}

return 0
