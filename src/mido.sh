#!/usr/bin/env bash
set -Eeuo pipefail

handleCurlError() {

  local code="$1"
  local server="$2"
  local reason="${3:-}"
  local signal=""

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
      esac
      ;;
  esac

  return 1
}

curlRequest() {

  local output="$1"
  local server="$2"
  local agent="$3"
  shift 3

  local log reason 
  local rc=0 response=""

  if ! log=$(mktemp -p "$QEMU_DIR"); then
    error "Failed to create a temporary curl log."
    return 1
  fi

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
    rc=$?
  } || :

  if (( rc != 0 )); then

    reason=$(sed -nE 's/^curl: \([0-9]+\) //p' "$log" | tail -n 1)

    rm -f "$log"
    handleCurlError "$rc" "$server" "$reason"

    return 1
  fi

  rm -f "$log"

  if [ -n "$output" ]; then
    printf -v "$output" '%s' "$response"
  fi

  return 0
}

downloadWindows() {

  local id="$1"
  local lang="$2"
  local desc="$3"

  local ovToken="" ovTicks="" ovTime=""
  local skuId="" skuUrl="" skuJson=""
  local linkUrl="" linkJson="" link=""
  local language="" orgId="" ovData=""
  local instance="" vlsUrl="" ovUrl=""
  local session="" agent="" type=""
  local winVer="" page="" productId=""
  local rc=0 profile="606624d44113"

  agent=$(getAgent)
  language=$(getLanguage "$lang" "name")

  case "${id,,}" in
    "win11x64" ) winVer="11" && type="1" ;;
    "win11arm64" ) winVer="11arm64" && type="2" ;;
    * ) error "Invalid VERSION specified, value \"$id\" is not recognized!" && return 1 ;;
  esac

  local url="https://www.microsoft.com/en-us/software-download/windows$winVer"

  # uuidgen: For MacOS (installed by default) and other systems (e.g. with no /proc) that don't have a kernel interface for generating random UUIDs
  if ! session=$(cat /proc/sys/kernel/random/uuid 2> /dev/null || uuidgen --random); then
    error "Failed to generate session ID!"
    return 1
  fi

  session="${session//[![:print:]]/}"

  if [ -z "$session" ]; then
    error "Failed to generate session ID!"
    return 1
  fi

  # Get product edition ID for latest release of given Windows version
  # Product edition ID: This specifies both the Windows release (e.g. 22H2) and edition ("multi-edition" is default, either Home/Pro/Edu/etc., we select "Pro" in the answer files) in one number
  # This is the *only* request we make that Fido doesn't. Fido manually maintains a list of all the Windows release/edition product edition IDs in its script (see: $WindowsVersions array). This is helpful for downloading older releases (e.g. Windows 10 1909, 21H1, etc.) but we always want to get the newest release which is why we get this value dynamically
  # Also, keeping a "$WindowsVersions" array like Fido does would be way too much of a maintenance burden
  # Remove "Accept" header that curl sends by default
  enabled "$DEBUG" && echo "Parsing download page: ${url}"

  curlRequest page "Microsoft" "$agent" \
    --header "Accept:" \
    --max-filesize 1M \
    -- "$url" || return 1

  enabled "$DEBUG" && echo -n "Getting Product edition ID: "
  productId=$(echo "$page" | grep -Eo '<option value="[0-9]+">Windows' | cut -d '"' -f 2 | head -n 1 | tr -cd '0-9' | head -c 16)
  enabled "$DEBUG" && echo "$productId"

  if [ -z "$productId" ]; then
    error "Product edition ID not found!"
    return 1
  fi

  # Microsoft download "protection" requires the sessionId to be whitelisted through vlscppe.microsoft.com/tags

  orgId="y6jn8c31"
  vlsUrl="https://vlscppe.microsoft.com/tags?org_id=$orgId&session_id=$session"

  enabled "$DEBUG" && echo "Getting Session ID: $session"

  # Permit Session ID
  curlRequest "" "Microsoft" "$agent" \
    --output /dev/null \
    --header "Accept:" \
    --max-filesize 100K \
    -- "$vlsUrl" || return 1

  # Microsoft download "protection" also requires an ov-df.microsoft.com request/reply
  # 1) Request mdt.js to get w and rticks. InstanceId is (currently) constant.

  instance="560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175"
  ovUrl="https://ov-df.microsoft.com/mdt.js?instanceId=$instance&PageId=si&session_id=$session"

  enabled "$DEBUG" && echo -n "Getting OV data: "

  curlRequest ovData "Microsoft" "$agent" \
    --header "Accept:" \
    --max-filesize 1M \
    -- "$ovUrl" || return 1

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

  # 2) Send a reply with session ID, current epoch and previously retrieved w and rticks

  ovTime=$(date +%s%3N)
  ovUrl="https://ov-df.microsoft.com/?session_id=$session&CustomerId=$instance&PageId=si&w=$ovToken&mdt=$ovTime&rticks=$ovTicks"

  enabled "$DEBUG" && echo "Sending OV reply: $instance"

  curlRequest "" "Microsoft" "$agent" \
    --output /dev/null \
    --header "Accept:" \
    --max-filesize 100K \
    -- "$ovUrl" || return 1

  enabled "$DEBUG" && echo -n "Getting language SKU ID: "

  skuUrl="https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$profile&ProductEditionId=$productId&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$session"

  curlRequest skuJson "Microsoft" "$agent" \
    --referer "$url" \
    --header "Accept:" \
    --max-filesize 100K \
    -- "$skuUrl" || return 1

  { skuId=$(echo "$skuJson" | jq --arg LANG "$language" -r '.Skus[] | select(.Language==$LANG).Id') 2>/dev/null; rc=$?; } || :

  if [ -z "$skuId" ] || [[ "${skuId,,}" == "null" ]] || (( rc != 0 )); then
    language=$(getLanguage "$lang" "desc")
    error "No download in the $language language available for $desc!"
    return 1
  fi

  enabled "$DEBUG" && echo "$skuId"
  enabled "$DEBUG" && echo "Getting ISO download link..."

  # Get ISO download link
  # If any request is going to be blocked by Microsoft it's always this last one (the previous requests always seem to succeed)

  linkUrl="https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=$profile&ProductEditionId=undefined&SKU=$skuId&friendlyFileName=undefined&Locale=en-US&sessionID=$session"

  curlRequest linkJson "Microsoft" "$agent" \
    --referer "$url" \
    --header "Accept:" \
    --max-filesize 100K \
    -- "$linkUrl" || return 1

  if ! [ "$linkJson" ]; then
    # This should only happen if there's been some change to how this API works
    error "Microsoft servers gave us an empty response to our request for an automated download."
    return 1
  fi

  if echo "$linkJson" | grep -q "Sentinel marked this request as rejected."; then
    error "Microsoft blocked the automated download request based on your IP address."
    return 1
  fi

  if echo "$linkJson" | grep -q "We are unable to complete your request at this time."; then
    error "Microsoft blocked the automated download request."
    return 1
  fi

  { link=$(echo "$linkJson" | jq --argjson TYPE "$type" -r '.ProductDownloadOptions[] | select(.DownloadType==$TYPE).Uri') 2>/dev/null; rc=$?; } || :

  if [ -z "$link" ] || [[ "${link,,}" == "null" ]] || (( rc != 0 )); then
    error "Microsoft server gave us no download link to our request for an automated download!"
    info "Response: $linkJson"
    return 1
  fi

  MIDO_URL="$link"
  return 0
}

downloadWindowsEval() {

  local id="$1"
  local lang="$2"
  local desc="$3"
  local filter="" culture="" compare="" language=""
  local agent="" type="" winVer=""

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
  local link=""
  local links=""
  local page=""
  local url="https://www.microsoft.com/en-us/evalcenter/download-$winVer"

  enabled "$DEBUG" && echo "Parsing download page: ${url}"

  curlRequest page "Microsoft" "$agent" \
    --location \
    --max-filesize 1M \
    -- "$url" || return 1

  if ! [ "$page" ]; then
    # This should only happen if there's been some change to where this download page is located
    error "Windows server download page gave us an empty response"
    return 1
  fi

  enabled "$DEBUG" && echo "Getting download link.."

  filter="https://go.microsoft.com/fwlink/?linkid=[0-9]\+&clcid=0x[0-9a-z]\+&culture=${culture,,}&country=${country,,}"

  if ! echo "$page" | grep -io "$filter" > /dev/null; then
    filter="https://go.microsoft.com/fwlink/p/?linkid=[0-9]\+&clcid=0x[0-9a-z]\+&culture=${culture,,}&country=${country,,}"
  fi

  links=$(echo "$page" | grep -io "$filter") || {
    # This should only happen if there's been some change to the download endpoint web address
    if [[ "${lang,,}" == "en" || "${lang,,}" == "en-"* ]]; then
      error "Windows server download page gave us no download link!"
    else
      language=$(getLanguage "$lang" "desc")
      error "No download in the $language language available for $desc!"
    fi
    return 1
  }

  case "$type" in
    "iot" )
      case "${PLATFORM,,}" in
        "x64" )
          link=$(echo "$links" | head -n 1) ;;
        "arm64" )
          link=$(echo "$links" | head -n 2 | tail -n 1) ;;
      esac ;;
    "ltsc" )
      case "${PLATFORM,,}" in
        "x64" )
          link=$(echo "$links" | head -n 2 | tail -n 1) ;;
      esac ;;
    "enterprise" )
      case "${PLATFORM,,}" in
        "x64" )
          if [[ "$winVer" != "windows-10"* ]]; then
            link=$(echo "$links" | head -n 1)
          else
            link=$(echo "$links" | head -n 2 | tail -n 1)
          fi ;;
        "arm64" )
          link=$(echo "$links" | head -n 2 | tail -n 1) ;;
      esac ;;
    "server" )
      case "${PLATFORM,,}" in
        "x64" )
          link=$(echo "$links" | head -n 1) ;;
      esac ;;
    * )
      error "Invalid type specified, value \"$type\" is not recognized!" && return 1 ;;
  esac

  [ -z "$link" ] && error "Could not parse download link from page!" && return 1

  # Follow redirect so proceeding log message is useful
  # This is a request we make that Fido doesn't

  curlRequest link "Microsoft" "$agent" \
    --location \
    --output /dev/null \
    --write-out "%{url_effective}" \
    --head \
    -- "$link" || return 1

  case "${PLATFORM,,}" in
    "x64" )
      if [[ "${link,,}" != *"x64"* ]]; then
        echo "Found download link: $link"
        error "Download link is for the wrong platform? Please report this at $SUPPORT/issues"
        return 1
      fi ;;
    "arm64" )
      if [[ "${link,,}" != *"a64"* && "${link,,}" != *"arm64"* ]]; then
        if enabled "$DEBUG"; then
          echo "Found download link: $link"
          echo "Link for ARM platform currently not available!"
        fi
        return 1
      fi ;;
  esac

  if enabled "$DEBUG" && enabled "$VERIFY" && [[ "${lang,,}" == "en"* ]]; then
    compare=$(getMido "$id" "$lang" "")
    if [ -n "$compare" ] && [[ "${link,,}" != "${compare,,}" ]]; then
      echo "Retrieved link does not match the fixed link: $compare"
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
      default="${default%-enterprise-ltsc-eval}-ltsc"
      ;;
    *"-enterprise-iot-eval" )
      default="${default%-enterprise-iot-eval}-iot"
      ;;
    *"-eval" )
      default="${default%-eval}"
      ;;
  esac

  # Preserve a genuinely different DETECTED override.
  if [ -n "$current" ] && [[ "${current,,}" != "$default" ]]; then
    echo "$current"
    return 0
  fi

  # Select the answer-file identity for the source that actually succeeded.
  case "$source" in
    *"-enterprise-ltsc-eval" )
      detected="${source%-enterprise-ltsc-eval}-ltsc-eval"
      ;;
    *"-enterprise-iot-eval" )
      detected="${source%-enterprise-iot-eval}-iot"
      ;;
    *"-eval" )
      detected="$source"
      ;;
    * )
      detected="${current:-$default}"
      ;;
  esac

  echo "$detected"
  return 0
}

downloadWindowsLtsc() {

  local id="$1"
  local lang="$2"
  local desc="$3"
  local alternate=""
  local alternate_desc=""

  case "${id,,}" in
    "win11${PLATFORM,,}-enterprise-iot-eval" )
      alternate="win11${PLATFORM,,}-enterprise-ltsc-eval"
      ;;
    "win11${PLATFORM,,}-enterprise-ltsc-eval" )
      alternate="win11${PLATFORM,,}-enterprise-iot-eval"
      ;;
    * )
      error "Invalid VERSION specified, value \"$id\" is not recognized!"
      return 1
      ;;
  esac

  if downloadWindowsEval "$id" "$lang" "$desc" > /dev/null 2>&1; then
    MIDO_SOURCE="$id"
    return 0
  fi

  alternate_desc=$(printEdition "$alternate" "$alternate")

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
  local language edition

  MIDO_SOURCE=""
  language=$(getLanguage "$lang" "desc")
  edition=$(printEdition "$version" "$desc")

  local msg="Requesting $desc from the Microsoft servers..."
  info "$msg" && html "$msg"

  case "${version,,}" in
    "win2008r2" | "win2008r2-eval" | \
    "win81${PLATFORM,,}"* | "win10${PLATFORM,,}-enterprise"* )
      if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then
        error "No download in the $language language available for $edition!"
        MIDO_URL=""
        return 1
      fi ;;
  esac

  case "${version,,}" in
    "win11${PLATFORM,,}" ) ;;
    "win11${PLATFORM,,}-enterprise"* ) ;;
    * )
      if [[ "${PLATFORM,,}" != "x64" ]]; then
        error "No download for the ${PLATFORM^^} platform available for $edition!"
        MIDO_URL=""
        return 1
      fi ;;
  esac

  case "${version,,}" in
    "win11${PLATFORM,,}" )

      if downloadWindows "$version" "$lang" "$edition"; then
        MIDO_SOURCE="$version"
        return 0
      fi ;;

    "win11${PLATFORM,,}-enterprise-iot-eval" | \
    "win11${PLATFORM,,}-enterprise-ltsc-eval" )

      downloadWindowsLtsc "$version" "$lang" "$edition" && return 0
      ;;

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

    "win2008r2" | "win2008r2-eval" | \
    "win81${PLATFORM,,}"* | "win10${PLATFORM,,}-enterprise"* ) ;;

    * )
      error "Invalid VERSION specified, value \"$version\" is not recognized!"
      return 1
      ;;
  esac

  MIDO_URL=$(getMido "$version" "$lang" "")
  [ -z "$MIDO_URL" ] && return 1

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
  local url=""
  local name=""
  local build="$3"
  local edition=""
  local file="catalog.xml"

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
  local url=""
  local name=""
  local edition=""
  local file="catalog.cab"

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
    "edition" ) echo '[Edition="'"${edition}"'"]' ;;
    *) echo "";;
  esac

  return 0
}

getXmlTag() {

  local tag="$1"
  local file="$2"

  xmllint --nonet --xpath "//$tag" "$file" 2>/dev/null | sed -E -e "s/<[\/]?$tag>//g" || true

  return 0
}

getESD() {

  local dir="$1"
  local version="$2"
  local lang="$3"
  local desc="$4"
  local file result culture
  local language edition catalog
  local xmlFile="products.xml"
  local esdFile="esd_edition.xml"
  local filterFile="products_filter.xml"
  local log query rc=0 reason=""

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

  {
    LC_ALL=C wget "$catalog" -O "$dir/$file" --no-verbose --timeout=30 \
      --no-http-keep-alive --output-file="$log"
    rc=$?
  } || :

  if (( rc != 0 )); then

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

  query='//File[Architecture="'${PLATFORM,,}'"]'"${edition}"''
  result=$(xmllint --nonet --xpath "${query}" "$dir/$xmlFile" 2>/dev/null || true)

  if [ -z "$result" ]; then

    query='//File[Architecture="'${PLATFORM^^}'"]'"${edition}"''
    result=$(xmllint --nonet --xpath "${query}" "$dir/$xmlFile" 2>/dev/null || true)

    if [ -z "$result" ]; then
      desc=$(printEdition "$version" "$desc")
      language=$(getLanguage "$lang" "desc")
      error "No download link available for $desc!"
      return 1
    fi

  fi

  echo -e '<Catalog>' > "$dir/$filterFile"
  echo "$result" >> "$dir/$filterFile"
  echo -e '</Catalog>'>> "$dir/$filterFile"

  result=$(xmllint --nonet --xpath "//File[LanguageCode=\"${culture,,}\"]" "$dir/$filterFile" 2>/dev/null || true)

  if [ -z "$result" ]; then
    desc=$(printEdition "$version" "$desc")
    language=$(getLanguage "$lang" "desc")
    error "No download in the $language language available for $desc!"
    return 1
  fi

  echo "$result" > "$dir/$esdFile"

  ESD=$(getXmlTag "FilePath" "$dir/$esdFile")

  if [ -z "$ESD" ]; then
    error "Failed to find ESD URL in $esdFile!"
    return 1
  fi

  ESD_SUM=$(getXmlTag "Sha1" "$dir/$esdFile")

  if [ -z "$ESD_SUM" ]; then
    error "Failed to find ESD checksum in $esdFile!"
    return 1
  fi

  ESD_SIZE=$(getXmlTag "Size" "$dir/$esdFile")

  if [ -z "$ESD_SIZE" ]; then
    error "Failed to find ESD filesize in $esdFile!"
    return 1
  fi

  rm -rf "$dir"
  return 0
}

isCompressed() {

  local file="$1"

  case "${file,,}" in
    *".7z" | *".zip" | *".rar" | *".lzma" | *".bz" | *".bz2" )
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

  local hash=""
  local algo="SHA256"

  [ -z "$check" ] && return 0
  ! enabled "$VERIFY" && return 0
  [[ "${#check}" == "40" ]] && algo="SHA1"

  local msg="Verifying downloaded ISO..."
  info "$msg" && html "$msg"

  if [[ "${algo,,}" != "sha256" ]]; then
    if ! hash=$(sha1sum "$iso" | cut -f1 -d' '); then
      error "Failed to calculate SHA1 checksum for $iso!"
      return 1
    fi
  else
    if ! hash=$(sha256sum "$iso" | cut -f1 -d' '); then
      error "Failed to calculate SHA256 checksum for $iso!"
      return 1
    fi
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
  local connections="${5:-1}"
  local msg="Downloading $desc"
  local console_msg="$msg"
  local domain dots

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
  local total rc=0

  if downloadRetry \
      "$iso" \
      "${CONNECTIONS:-1}" \
      "$seconds" \
      "$desc" \
      "100000000" \
      "$iso" \
      "$url" \
      "$size" \
      "$desc"; then
    rc=0
  else
    rc=$?
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
  local culture msg

  msg="No working download method was found for $desc, falling back to English..."
  info "$msg" && html "$msg"

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
  local tried="n"
  local success="n"
  local seconds="5"
  local detected="$DETECTED"
  local url sum size base desc language i

  if [[ "${version,,}" == "http"* ]]; then

    base=$(basename "$iso")
    desc=$(fromFile "$base")

    tryDownload "$iso" "$version" "" "" "" "$desc" "$seconds" && return 0
    return 1
  fi

  if ! validVersion "$version" "en"; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!"
    return 1
  fi

  desc=$(printVariant "$version" "")

  if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then

    language=$(getLanguage "$lang" "desc")

    if ! validVersion "$version" "$lang"; then
      desc=$(printEdition "$version" "$desc")
      desc+=" in $language"

      fallbackEnglish "$iso" "$version" "$lang" "$desc" && return 0
      return 1
    fi

    desc+=" in $language"
  fi

  if isMido "$version" "$lang"; then

    tried="y"
    success="n"

    if getWindows "$version" "$lang" "$desc"; then
      success="y"
    else
      delay "$seconds"
      getWindows "$version" "$lang" "$desc" && success="y"
    fi

    if [[ "$success" == "y" ]]; then

      detected=$(getMidoDetected "$version" "$MIDO_SOURCE" "$DETECTED")
      url=$(getMido "$version" "$lang" "")

      sum=""
      size=""

      # Skip verification if the retrieved URL differs from the static URL.
      if [[ "${MIDO_URL%%\?*}" == "${url%%\?*}" ]]; then
        size=$(getMido "$version" "$lang" "size")
        sum=$(getMido "$version" "$lang" "sum")
      fi

      if tryDownload "$iso" "$MIDO_URL" "$sum" "$size" "$lang" "$desc" "$seconds"; then
        # Commit the candidate only after the image was downloaded and verified.
        DETECTED="$detected"
        return 0
      fi

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

      ISO="${ISO%.*}.esd"

      if tryDownload "$ISO" "$ESD" "$ESD_SUM" "$ESD_SIZE" "$lang" "$desc" "$seconds"; then
        return 0
      fi

      ISO="$iso"

    fi
  fi

  for ((i=1;i<=MIRRORS;i++)); do

    url=$(getLink "$i" "$version" "$lang")

    if [ -n "$url" ]; then

      if [[ "$tried" != "n" ]]; then
        info "Failed to download $desc, will try another mirror now..."
      fi

      tried="y"
      size=$(getSize "$i" "$version" "$lang")
      sum=$(getHash "$i" "$version" "$lang")

      tryDownload "$iso" "$url" "$sum" "$size" "$lang" "$desc" "$seconds" && return 0

    fi
  done

  if [[ "${lang,,}" != "en" && "${lang,,}" != "en-"* ]]; then
    if fallbackEnglish "$iso" "$version" "$lang" "$desc"; then
      return 0
    fi
  fi

  return 1
}

return 0
