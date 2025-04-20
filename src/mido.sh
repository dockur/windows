#!/usr/bin/env bash
set -Eeuo pipefail

handle_curl_error() {

  local error_code="$1"
  local server_name="$2"

  case "$error_code" in
    1) error "Unsupported protocol!" ;;
    2) error "Failed to initialize curl!" ;;
    3) error "The URL format is malformed!" ;;
    5) error "Failed to resolve address of proxy host!" ;;
    6) error "Failed to resolve $server_name servers! Is there an Internet connection?" ;;
    7) error "Failed to contact $server_name servers! Is there an Internet connection or is the server down?" ;;
    8) error "$server_name servers returned a malformed HTTP response!" ;;
    16) error "A problem was detected in the HTTP2 framing layer!" ;;
    22) error "$server_name servers returned a failing HTTP status code!" ;;
    23) error "Failed at writing Windows media to disk! Out of disk space or permission error?" ;;
    26) error "Failed to read Windows media from disk!" ;;
    27) error "Ran out of memory during download!" ;;
    28) error "Connection timed out to $server_name server!" ;;
    35) error "SSL connection error from $server_name server!" ;;
    36) error "Failed to continue earlier download!" ;;
    52) error "Received no data from the $server_name server!" ;;
    63) error "$server_name servers returned an unexpectedly large response!" ;;
    # POSIX defines exit statuses 1-125 as usable by us
    # https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_08_02
    $((error_code <= 125)))
      # Must be some other server or network error (possibly with this specific request/file)
      # This is when accounting for all possible errors in the curl manual assuming a correctly formed curl command and an HTTP(S) request, using only the curl features we're using, and a sane build
      error "Miscellaneous server or network error, reason: $error_code"
      ;;
    126 | 127 ) error "Curl command not found!" ;;
    # Exit statuses are undefined by POSIX beyond this point
    *)
      case "$(kill -l "$error_code")" in
        # Signals defined to exist by POSIX:
        # https://pubs.opengroup.org/onlinepubs/009695399/basedefs/signal.h.html
        INT) error "Curl was interrupted!" ;;
        # There could be other signals but these are most common
        SEGV | ABRT ) error "Curl crashed! Please report any core dumps to curl developers." ;;
        *) error "Curl terminated due to fatal signal $error_code !" ;;
      esac
  esac

  return 1
}

get_agent() {

  local user_agent

  # Determine approximate latest Firefox release
  browser_version="$((124 + ($(date +%s) - 1710892800) / 2419200))"
  echo "Mozilla/5.0 (X11; Linux x86_64; rv:${browser_version}.0) Gecko/20100101 Firefox/${browser_version}.0"

  return 0
}

download_windows() {

  local id="$1"
  local lang="$2"
  local desc="$3"
  local sku_id=""
  local sku_url=""
  local iso_url=""
  local iso_json=""
  local language=""
  local session_id=""
  local user_agent=""
  local download_type=""
  local windows_version=""
  local iso_download_link=""
  local download_page_html=""
  local product_edition_id=""
  local language_skuid_json=""
  local profile="606624d44113"

  user_agent=$(get_agent)
  language=$(getLanguage "$lang" "name")

  case "${id,,}" in
    "win11x64" ) windows_version="11" && download_type="1" ;;
    "win10x64" ) windows_version="10" && download_type="1" ;;
    "win11arm64" ) windows_version="11arm64" && download_type="2" ;;
    * ) error "Invalid VERSION specified, value \"$id\" is not recognized!" && return 1 ;;
  esac

  local url="https://www.microsoft.com/en-us/software-download/windows$windows_version"
  [[ "${id,,}" == "win10"* ]] && url+="ISO"

  # uuidgen: For MacOS (installed by default) and other systems (e.g. with no /proc) that don't have a kernel interface for generating random UUIDs
  session_id=$(cat /proc/sys/kernel/random/uuid 2> /dev/null || uuidgen --random)
  session_id="${session_id//[![:print:]]/}"

  # Get product edition ID for latest release of given Windows version
  # Product edition ID: This specifies both the Windows release (e.g. 22H2) and edition ("multi-edition" is default, either Home/Pro/Edu/etc., we select "Pro" in the answer files) in one number
  # This is the *only* request we make that Fido doesn't. Fido manually maintains a list of all the Windows release/edition product edition IDs in its script (see: $WindowsVersions array). This is helpful for downloading older releases (e.g. Windows 10 1909, 21H1, etc.) but we always want to get the newest release which is why we get this value dynamically
  # Also, keeping a "$WindowsVersions" array like Fido does would be way too much of a maintenance burden
  # Remove "Accept" header that curl sends by default
  [[ "$DEBUG" == [Yy1]* ]] && echo "Parsing download page: ${url}"
  download_page_html=$(curl --silent --max-time 30 --user-agent "$user_agent" --header "Accept:" --max-filesize 1M --fail --proto =https --tlsv1.2 --http1.1 -- "$url") || {
    handle_curl_error "$?" "Microsoft"
    return $?
  }

  [[ "$DEBUG" == [Yy1]* ]] && echo -n "Getting Product edition ID: "
  product_edition_id=$(echo "$download_page_html" | grep -Eo '<option value="[0-9]+">Windows' | cut -d '"' -f 2 | head -n 1 | tr -cd '0-9' | head -c 16)
  [[ "$DEBUG" == [Yy1]* ]] && echo "$product_edition_id"

  if [ -z "$product_edition_id" ]; then
    error "Product edition ID not found!"
    return 1
  fi

  [[ "$DEBUG" == [Yy1]* ]] && echo "Permit Session ID: $session_id"
  # Permit Session ID
  curl --silent --max-time 30 --output /dev/null --user-agent "$user_agent" --header "Accept:" --max-filesize 100K --fail --proto =https --tlsv1.2 --http1.1 -- "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$session_id" || {
    # This should only happen if there's been some change to how this API works
    handle_curl_error "$?" "Microsoft"
    return $?
  }

  [[ "$DEBUG" == [Yy1]* ]] && echo -n "Getting language SKU ID: "
  sku_url="https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$profile&ProductEditionId=$product_edition_id&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$session_id"
  language_skuid_json=$(curl --silent --max-time 30 --request GET --user-agent "$user_agent" --referer "$url" --header "Accept:" --max-filesize 100K --fail --proto =https --tlsv1.2 --http1.1 -- "$sku_url") || {
    handle_curl_error "$?" "Microsoft"
    return $?
  }

  { sku_id=$(echo "$language_skuid_json" | jq --arg LANG "$language" -r '.Skus[] | select(.Language==$LANG).Id') 2>/dev/null; rc=$?; } || :

  if [ -z "$sku_id" ] || [[ "${sku_id,,}" == "null" ]] || (( rc != 0 )); then
    language=$(getLanguage "$lang" "desc")
    error "No download in the $language language available for $desc!"
    return 1
  fi

  [[ "$DEBUG" == [Yy1]* ]] && echo "$sku_id"
  [[ "$DEBUG" == [Yy1]* ]] && echo "Getting ISO download link..."

  # Get ISO download link
  # If any request is going to be blocked by Microsoft it's always this last one (the previous requests always seem to succeed)

  iso_url="https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=$profile&ProductEditionId=undefined&SKU=$sku_id&friendlyFileName=undefined&Locale=en-US&sessionID=$session_id"
  iso_json=$(curl --silent --max-time 30 --request GET --user-agent "$user_agent" --referer "$url" --header "Accept:" --max-filesize 100K --fail --proto =https --tlsv1.2 --http1.1 -- "$iso_url")

  if ! [ "$iso_json" ]; then
    # This should only happen if there's been some change to how this API works
    error "Microsoft servers gave us an empty response to our request for an automated download."
    return 1
  fi

  if echo "$iso_json" | grep -q "Sentinel marked this request as rejected."; then
    error "Microsoft blocked the automated download request based on your IP address."
    return 1
  fi

  if echo "$iso_json" | grep -q "We are unable to complete your request at this time."; then
    error "Microsoft blocked the automated download request based on your IP address."
    return 1
  fi

  { iso_download_link=$(echo "$iso_json" | jq --argjson TYPE "$download_type" -r '.ProductDownloadOptions[] | select(.DownloadType==$TYPE).Uri') 2>/dev/null; rc=$?; } || :

  if [ -z "$iso_download_link" ] || [[ "${iso_download_link,,}" == "null" ]] || (( rc != 0 )); then
    error "Microsoft servers gave us no download link to our request for an automated download!"
    info "Response: $iso_json"
    return 1
  fi

  MIDO_URL="$iso_download_link"
  return 0
}

download_windows_eval() {

  local id="$1"
  local lang="$2"
  local desc="$3"
  local filter=""
  local culture=""
  local language=""
  local user_agent=""
  local enterprise_type=""
  local windows_version=""

  case "${id,,}" in
    "win11${PLATFORM,,}-enterprise-eval" )
      enterprise_type="enterprise"
      windows_version="windows-11-enterprise" ;;
    "win11${PLATFORM,,}-enterprise-iot-eval" )
      enterprise_type="iot"
      windows_version="windows-11-iot-enterprise-ltsc-eval" ;;
    "win11${PLATFORM,,}-enterprise-ltsc-eval" )
      enterprise_type="iot"
      windows_version="windows-11-iot-enterprise-ltsc-eval" ;;
    "win10${PLATFORM,,}-enterprise-eval" )
      enterprise_type="enterprise"
      windows_version="windows-10-enterprise" ;;
    "win10${PLATFORM,,}-enterprise-ltsc-eval" )
      enterprise_type="ltsc"
      windows_version="windows-10-enterprise" ;;
    "win2025-eval" )
      enterprise_type="server"
      windows_version="windows-server-2025" ;;
    "win2022-eval" )
      enterprise_type="server"
      windows_version="windows-server-2022" ;;
    "win2019-hv" )
      enterprise_type="server"
      windows_version="hyper-v-server-2019" ;;
    "win2019-eval" )
      enterprise_type="server"
      windows_version="windows-server-2019" ;;
    "win2016-eval" )
      enterprise_type="server"
      windows_version="windows-server-2016" ;;
    "win2012r2-eval" )
      enterprise_type="server"
      windows_version="windows-server-2012-r2" ;;
    * )
      error "Invalid VERSION specified, value \"$id\" is not recognized!" && return 1 ;;
  esac

  user_agent=$(get_agent)
  culture=$(getLanguage "$lang" "culture")

  local country="${culture#*-}"
  local iso_download_page_html=""
  local url="https://www.microsoft.com/en-us/evalcenter/download-$windows_version"

  [[ "$DEBUG" == [Yy1]* ]] && echo "Parsing download page: ${url}"
  iso_download_page_html=$(curl --silent --max-time 30 --user-agent "$user_agent" --location --max-filesize 1M --fail --proto =https --tlsv1.2 --http1.1 -- "$url") || {
    handle_curl_error "$?" "Microsoft"
    return $?
  }

  if ! [ "$iso_download_page_html" ]; then
    # This should only happen if there's been some change to where this download page is located
    error "Windows server download page gave us an empty response"
    return 1
  fi

  [[ "$DEBUG" == [Yy1]* ]] && echo "Getting download link.."

  filter="https://go.microsoft.com/fwlink/?linkid=[0-9]\+&clcid=0x[0-9a-z]\+&culture=${culture,,}&country=${country,,}"

  if ! echo "$iso_download_page_html" | grep -io "$filter" > /dev/null; then
    filter="https://go.microsoft.com/fwlink/p/?linkid=[0-9]\+&clcid=0x[0-9a-z]\+&culture=${culture,,}&country=${country,,}"
  fi

  iso_download_links=$(echo "$iso_download_page_html" | grep -io "$filter") || {
    # This should only happen if there's been some change to the download endpoint web address
    if [[ "${lang,,}" == "en" ]] || [[ "${lang,,}" == "en-"* ]]; then
      error "Windows server download page gave us no download link!"
    else
      language=$(getLanguage "$lang" "desc")
      error "No download in the $language language available for $desc!"
    fi
    return 1
  }

  case "$enterprise_type" in
    "enterprise" )
      iso_download_link=$(echo "$iso_download_links" | head -n 2 | tail -n 1)
      ;;
    "iot" )
      if [[ "${PLATFORM,,}" == "x64" ]]; then
        iso_download_link=$(echo "$iso_download_links" | head -n 1)
      fi
      if [[ "${PLATFORM,,}" == "arm64" ]]; then
        iso_download_link=$(echo "$iso_download_links" | head -n 2 | tail -n 1)
      fi
      ;;
    "ltsc" )
      iso_download_link=$(echo "$iso_download_links" | head -n 4 | tail -n 1)
      ;;
    "server" )
      iso_download_link=$(echo "$iso_download_links" | head -n 1)
      ;;
    * )
      error "Invalid type specified, value \"$enterprise_type\" is not recognized!" && return 1 ;;
  esac

  [[ "$DEBUG" == [Yy1]* ]] && echo "Found download link: $iso_download_link"

  # Follow redirect so proceeding log message is useful
  # This is a request we make that Fido doesn't

  iso_download_link=$(curl --silent --max-time 30 --user-agent "$user_agent" --location --output /dev/null --silent --write-out "%{url_effective}" --head --fail --proto =https --tlsv1.2 --http1.1 -- "$iso_download_link") || {
    # This should only happen if the Microsoft servers are down
    handle_curl_error "$?" "Microsoft"
    return $?
  }

  MIDO_URL="$iso_download_link"
  return 0
}

getWindows() {

  local version="$1"
  local lang="$2"
  local desc="$3"

  local language edition
  language=$(getLanguage "$lang" "desc")
  edition=$(printEdition "$version" "$desc")

  local msg="Requesting $desc from the Microsoft servers..."
  info "$msg" && html "$msg"

  case "${version,,}" in
    "win2008r2" | "win81${PLATFORM,,}"* | "win11${PLATFORM,,}-enterprise-iot"* | "win11${PLATFORM,,}-enterprise-ltsc"* )
      if [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-"* ]]; then
        error "No download in the $language language available for $edition!"
        MIDO_URL="" && return 1
      fi ;;
  esac

  case "${version,,}" in
    "win11${PLATFORM,,}" ) ;;
    "win11${PLATFORM,,}-enterprise-iot"* ) ;;
    "win11${PLATFORM,,}-enterprise-ltsc"* ) ;;
    * )
      if [[ "${PLATFORM,,}" != "x64" ]]; then
        error "No download for the ${PLATFORM^^} platform available for $edition!"
        MIDO_URL="" && return 1
      fi ;;
  esac

  case "${version,,}" in
    "win10${PLATFORM,,}" | "win11${PLATFORM,,}" )
      download_windows "$version" "$lang" "$edition" && return 0
      ;;
    "win11${PLATFORM,,}-enterprise"* | "win10${PLATFORM,,}-enterprise"* )
      download_windows_eval "$version" "$lang" "$edition" && return 0
      ;;
    "win2025-eval" | "win2022-eval" | "win2019-eval" | "win2019-hv" | "win2016-eval" | "win2012r2-eval" )
      download_windows_eval "$version" "$lang" "$edition" && return 0
      ;;
    "win81${PLATFORM,,}-enterprise"* | "win2008r2" )
      ;;
    * ) error "Invalid VERSION specified, value \"$version\" is not recognized!" ;;
  esac

  MIDO_URL=$(getMido "$version" "$lang" "")
  [ -z "$MIDO_URL" ] && return 1

  return 0
}

getCatalog() {

  local id="$1"
  local ret="$2"
  local url=""
  local name=""
  local edition=""

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
    "name" ) echo "$name" ;;
    "edition" ) echo "$edition" ;;
    *) echo "";;
  esac

  return 0
}

getESD() {

  local dir="$1"
  local version="$2"
  local lang="$3"
  local desc="$4"
  local culture
  local language
  local editionName
  local winCatalog size

  culture=$(getLanguage "$lang" "culture")
  winCatalog=$(getCatalog "$version" "url")
  editionName=$(getCatalog "$version" "edition")

  if [ -z "$winCatalog" ] || [ -z "$editionName" ]; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!" && return 1
  fi

  local msg="Downloading product information from Microsoft server..."
  info "$msg" && html "$msg"

  rm -rf "$dir"
  mkdir -p "$dir"

  local wFile="catalog.cab"
  local xFile="products.xml"
  local eFile="esd_edition.xml"
  local fFile="products_filter.xml"

  { wget "$winCatalog" -O "$dir/$wFile" -q --timeout=30 --no-http-keep-alive; rc=$?; } || :

  msg="Failed to download $winCatalog"
  (( rc == 3 )) && error "$msg , cannot write file (disk full?)" && return 1
  (( rc == 4 )) && error "$msg , network failure!" && return 1
  (( rc == 8 )) && error "$msg , server issued an error response!" && return 1
  (( rc != 0 )) && error "$msg , reason: $rc" && return 1

  cd "$dir"

  if ! cabextract "$wFile" > /dev/null; then
    cd /run
    error "Failed to extract $wFile!" && return 1
  fi

  cd /run

  if [ ! -s "$dir/$xFile" ]; then
    error "Failed to find $xFile in $wFile!" && return 1
  fi

  local edQuery='//File[Architecture="'${PLATFORM}'"][Edition="'${editionName}'"]'

  echo -e '<Catalog>' > "$dir/$fFile"
  xmllint --nonet --xpath "${edQuery}" "$dir/$xFile" >> "$dir/$fFile" 2>/dev/null
  echo -e '</Catalog>'>> "$dir/$fFile"

  xmllint --nonet --xpath "//File[LanguageCode=\"${culture,,}\"]" "$dir/$fFile" >"$dir/$eFile"

  size=$(stat -c%s "$dir/$eFile")
  if ((size<20)); then
    desc=$(printEdition "$version" "$desc")
    language=$(getLanguage "$lang" "desc")
    error "No download in the $language language available for $desc!" && return 1
  fi

  local tag="FilePath"
  ESD=$(xmllint --nonet --xpath "//$tag" "$dir/$eFile" | sed -E -e "s/<[\/]?$tag>//g")

  if [ -z "$ESD" ]; then
    error "Failed to find ESD URL in $eFile!" && return 1
  fi

  tag="Sha1"
  ESD_SUM=$(xmllint --nonet --xpath "//$tag" "$dir/$eFile" | sed -E -e "s/<[\/]?$tag>//g")
  tag="Size"
  ESD_SIZE=$(xmllint --nonet --xpath "//$tag" "$dir/$eFile" | sed -E -e "s/<[\/]?$tag>//g")

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

  if [ -n "$size" ] && [[ "$total" != "$size" ]] && [[ "$size" != "0" ]]; then
    if [[ "$VERIFY" == [Yy1]* ]] || [[ "$DEBUG" == [Yy1]* ]]; then
      warn "The downloaded file has a different size ( $total bytes) than expected ( $size bytes). Please report this at $SUPPORT/issues"
    fi
  fi

  local hash=""
  local algo="SHA256"

  [ -z "$check" ] && return 0
  [[ "$VERIFY" != [Yy1]* ]] && return 0
  [[ "${#check}" == "40" ]] && algo="SHA1"

  local msg="Verifying downloaded ISO..."
  info "$msg" && html "$msg"

  if [[ "${algo,,}" != "sha256" ]]; then
    hash=$(sha1sum "$iso" | cut -f1 -d' ')
  else
    hash=$(sha256sum "$iso" | cut -f1 -d' ')
  fi

  if [[ "$hash" == "$check" ]]; then
    info "Succesfully verified ISO!" && return 0
  fi

  error "The downloaded file has an unknown $algo checksum: $hash , as the expected value was: $check. Please report this at $SUPPORT/issues"
  return 1
}

downloadFile() {

  local iso="$1"
  local url="$2"
  local sum="$3"
  local size="$4"
  local lang="$5"
  local desc="$6"
  local msg="Downloading $desc"
  local rc total total_gb progress domain dots agent space folder

  rm -f "$iso"
  agent=$(get_agent)

  if [ -n "$size" ] && [[ "$size" != "0" ]]; then
    folder=$(dirname -- "$iso")
    space=$(df --output=avail -B 1 "$folder" | tail -n 1)
    total_gb=$(formatBytes "$space")
    (( size > space )) && error "Not enough free space to download file, only $total_gb left!" && return 1
  fi

  # Check if running with interactive TTY or redirected to docker log
  if [ -t 1 ]; then
    progress="--progress=bar:noscroll"
  else
    progress="--progress=dot:giga"
  fi

  html "$msg..."
  /run/progress.sh "$iso" "$size" "$msg ([P])..." &

  domain=$(echo "$url" | awk -F/ '{print $3}')
  dots=$(echo "$domain" | tr -cd '.' | wc -c)
  (( dots > 1 )) && domain=$(expr "$domain" : '.*\.\(.*\..*\)')

  if [ -n "$domain" ] && [[ "${domain,,}" != *"microsoft.com" ]]; then
    msg="Downloading $desc from $domain"
  fi

  info "$msg..."

  { wget "$url" -O "$iso" -q --timeout=30 --no-http-keep-alive --user-agent "$agent" --show-progress "$progress"; rc=$?; } || :

  fKill "progress.sh"

  if (( rc == 0 )) && [ -f "$iso" ]; then
    total=$(stat -c%s "$iso")
    total_gb=$(formatBytes "$total")
    if [ "$total" -lt 100000000 ]; then
      error "Invalid download link: $url (is only $total_gb ?). Please report this at $SUPPORT/issues" && return 1
    fi
    verifyFile "$iso" "$size" "$total" "$sum" || return 1
    isCompressed "$url" && UNPACK="Y"
    html "Download finished successfully..." && return 0
  fi

  msg="Failed to download $url"
  (( rc == 3 )) && error "$msg , cannot write file (disk full?)" && return 1
  (( rc == 4 )) && error "$msg , network failure!" && return 1
  (( rc == 8 )) && error "$msg , server issued an error response! Please report this at $SUPPORT/issues" && return 1

  error "$msg , reason: $rc"
  return 1
}

downloadImage() {

  local iso="$1"
  local version="$2"
  local lang="$3"
  local delay=5
  local tried="n"
  local success="n"
  local url sum size base desc language
  local msg="Will retry after $delay seconds..."

  if [[ "${version,,}" == "http"* ]]; then

    base=$(basename "$iso")
    desc=$(fromFile "$base")
    downloadFile "$iso" "$version" "" "" "" "$desc" && return 0
    info "$msg" && html "$msg" && sleep "$delay"
    downloadFile "$iso" "$version" "" "" "" "$desc" && return 0
    rm -f "$iso"

    return 1
  fi

  if ! validVersion "$version" "en"; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!" && return 1
  fi

  desc=$(printVersion "$version" "")

  if [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-"* ]]; then
    language=$(getLanguage "$lang" "desc")
    if ! validVersion "$version" "$lang"; then
      desc=$(printEdition "$version" "$desc")
      error "The $language language version of $desc is not available, please switch to English." && return 1
    fi
    desc+=" in $language"
  fi

  if isMido "$version" "$lang"; then

    tried="y"
    success="n"

    if getWindows "$version" "$lang" "$desc"; then
      success="y"
    else
      info "$msg" && html "$msg" && sleep "$delay"
      getWindows "$version" "$lang" "$desc" && success="y"
    fi

    if [[ "$success" == "y" ]]; then
      size=$(getMido "$version" "$lang" "size" )
      sum=$(getMido "$version" "$lang" "sum")
      downloadFile "$iso" "$MIDO_URL" "$sum" "$size" "$lang" "$desc" && return 0
      info "$msg" && html "$msg" && sleep "$delay"
      downloadFile "$iso" "$MIDO_URL" "$sum" "$size" "$lang" "$desc" && return 0
      rm -f "$iso"
    fi
  fi

  switchEdition "$version"

  if isESD "$version" "$lang"; then

    if [[ "$tried" != "n" ]]; then
      info "Failed to download $desc, will try a diferent method now..."
    fi

    tried="y"
    success="n"

    if getESD "$TMP/esd" "$version" "$lang" "$desc"; then
      success="y"
    else
      info "$msg" && html "$msg" && sleep "$delay"
      getESD "$TMP/esd" "$version" "$lang" "$desc" && success="y"
    fi

    if [[ "$success" == "y" ]]; then
      ISO="${ISO%.*}.esd"
      downloadFile "$ISO" "$ESD" "$ESD_SUM" "$ESD_SIZE" "$lang" "$desc" && return 0
      info "$msg" && html "$msg" && sleep "$delay"
      downloadFile "$ISO" "$ESD" "$ESD_SUM" "$ESD_SIZE" "$lang" "$desc" && return 0
      rm -f "$ISO"
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
      downloadFile "$iso" "$url" "$sum" "$size" "$lang" "$desc" && return 0
      info "$msg" && html "$msg" && sleep "$delay"
      downloadFile "$iso" "$url" "$sum" "$size" "$lang" "$desc" && return 0
      rm -f "$iso"
    fi

  done

  return 1
}

return 0
