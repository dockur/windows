#!/usr/bin/env bash
set -Eeuo pipefail

validateResolution() {

  local name="$1"
  local value="$2"
  local minimum="$3"
  local number

  if [[ ! "$value" =~ ^[0-9]+$ ]] || [ "${#value}" -gt 5 ]; then
    error "The $name variable must be between $minimum and 16384!"
    return 1
  fi

  number=$((10#$value))

  if [ "$number" -lt "$minimum" ] || [ "$number" -gt 16384 ]; then
    error "The $name variable must be between $minimum and 16384!"
    return 1
  fi

  return 0
}

validateProductKey() {

  local value="$1"

  [ -z "$value" ] && return 0

  if [[ ! "$value" =~ ^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$ ]]; then
    error "The KEY variable must contain a valid 25-character product key!"
    return 1
  fi

  return 0
}

validateComputerName() {

  local value="$1"

  [ -z "$value" ] && return 0

  if [ "${#value}" -gt 15 ]; then
    error "The HOST variable cannot contain more than 15 characters!"
    return 1
  fi

  if [[ ! "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
    error "The HOST variable may only contain letters, digits, and hyphens, and cannot start or end with a hyphen!"
    return 1
  fi

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    error "The HOST variable cannot contain only digits!"
    return 1
  fi

  return 0
}

validateWorkgroup() {

  local value="$1"
  local safe=""

  [ -z "$value" ] && return 0

  if [ "${#value}" -gt 15 ]; then
    error "The WORKGROUP variable cannot contain more than 15 characters!"
    return 1
  fi

  safe=$(printf '%s' "$value" | tr -d '"/\\[]:;|=,+*?<>') || return 1

  if [[ "$safe" != "$value" ]]; then
    error "The WORKGROUP variable contains characters that are not valid in a NetBIOS name!"
    return 1
  fi

  if [[ "$value" =~ ^[.[:space:]]+$ ]]; then
    error "The WORKGROUP variable cannot consist only of spaces or periods!"
    return 1
  fi

  return 0
}

validateMembership() {

  if [ -n "$DOMAIN" ] && [ -n "$WORKGROUP" ]; then
    error "The DOMAIN and WORKGROUP variables cannot be used together!"
    return 1
  fi

  if [ -n "$DOMAIN_OU" ] && [ -z "$DOMAIN" ]; then
    error "The DOMAIN_OU variable requires DOMAIN to be specified!"
    return 1
  fi

  validateWorkgroup "$WORKGROUP" || return 1
  return 0
}

validatePassword() {

  local value="$1"
  local desc="${2:-}"
  local suffix=""

  [ -n "$desc" ] && suffix=" for $desc"

  if [ "${#value}" -gt 127 ]; then
    error "The PASSWORD variable cannot contain more than 127 characters$suffix!"
    return 1
  fi

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    error "The PASSWORD variable cannot contain control characters$suffix!"
    return 1
  fi

  return 0
}

escapeXMLSed() {

  local s

  s=$(escapeXML "$1") || return 1
  s=${s//\\/\\\\}
  s=${s//&/\\&}
  s=${s//|/\\|}

  printf '%s' "$s"
  return 0
}

validateUsername() {

  local value="$1"
  local type="$2"
  local maximum

  case "$type" in
    "local" )
      maximum=20
      [ -z "$value" ] && return 0
      ;;
    "domain" )
      maximum=256

      if [ -z "$value" ]; then
        error "The USERNAME variable does not contain a valid domain account name!"
        return 1
      fi ;;
    * )
      return 1 ;;
  esac

  if [ "${#value}" -gt "$maximum" ]; then
    if [[ "$type" == "domain" ]]; then
      error "The USERNAME variable cannot contain more than $maximum characters for a domain account!"
    else
      error "The USERNAME variable cannot contain more than $maximum characters!"
    fi
    return 1
  fi

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    error "The USERNAME variable cannot contain control characters!"
    return 1
  fi

  case "$value" in
    *'"'* | *'/'* | *\\* | *'['* | *']'* | *':'* | *';'* | *'|'* | *'='* | *','* | *'+'* | *'*'* | *'?'* | *'<'* | *'>'* | *'%'* | *'@'* )
      if [[ "$type" == "domain" ]]; then
        error "The domain account name contains characters that are not supported by Windows unattended setup!"
      else
        error "The USERNAME variable contains characters that are not supported by Windows local accounts!"
      fi
      return 1 ;;
  esac

  if [[ "$value" == *"." ]]; then
    error "The USERNAME variable cannot end with a period!"
    return 1
  fi

  if [[ "$value" =~ ^[.[:space:]]+$ ]]; then
    error "The USERNAME variable cannot consist only of spaces or periods!"
    return 1
  fi

  case "${value^^}" in
    "NONE" )
      error "The USERNAME value \"NONE\" is reserved by Windows!"
      return 1 ;;
    "ADMINISTRATOR" | "GUEST" | "DEFAULTACCOUNT" | "WDAGUTILITYACCOUNT" | "WSIACCOUNT" )
      if [[ "$type" == "local" ]]; then
        error "The USERNAME value \"$value\" is reserved for a built-in Windows account!"
        return 1
      fi ;;
  esac

  return 0
}

validateDomainName() {

  local value="$1"
  local name="${2:-DOMAIN}"

  if [ -z "$value" ]; then
    error "The $name variable must contain a valid domain name!"
    return 1
  fi

  if [[ "$value" == *"://"* ]]; then
    error "The $name variable must contain a domain name, not a URL!"
    return 1
  fi

  if [ "${#value}" -gt 255 ] ||
    [[ "$value" =~ [[:cntrl:]] ]] ||
    [[ "$value" =~ [[:space:]] ]] ||
    [[ ! "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]; then

    error "The $name variable does not contain a valid domain name!"
    return 1
  fi

  return 0
}

generateEvalXML() {

  # Evaluation templates are generated from their normal counterpart so
  # both variants remain identical except for evaluation-specific selectors.

  local id="$1"
  local detected_index="${2:-}"
  local source="/run/assets/${id::-5}.xml"
  local target="/run/assets/$id.xml"
  local index="$detected_index" tmp

  [[ "${id,,}" == *"-eval" ]] || return 1
  [ -s "$target" ] && [ -z "$detected_index" ] && return 0
  [ -s "$source" ] || return 1

  if [ -n "$index" ] && [[ ! "$index" =~ ^[1-9][0-9]*$ ]]; then
    error "Invalid evaluation image index: $index"
    return 1
  fi

  if ! tmp=$(mktemp -p /run/assets ".${id}.XXXXXX"); then
    error "Failed to create a temporary evaluation answer file!"
    return 1
  fi

  if ! sed \
      -e '/<ProductKey>.*<\/ProductKey>/d' \
      -e '/<ProductKey>/,/<\/ProductKey>/d' \
      "$source" > "$tmp"; then
    rm -f "$tmp"
    error "Failed to generate evaluation answer file from $source!"
    return 1
  fi

  if [ -n "$detected_index" ]; then

    # A WIM index was detected, so replace any selector inherited from
    # the normal template with the exact index from the ISO image.
    if ! sed -i \
      -e '/<InstallFrom>.*<\/InstallFrom>/d' \
      -e '/<InstallFrom>/,/<\/InstallFrom>/d' \
      "$tmp"; then
      rm -f "$tmp"
      error "Failed to replace evaluation image selector!"
      return 1
    fi

  else

    # No WIM was inspected, so retain the known defaults for download routes.
    case "${id,,}" in
      *"-ltsc-eval" ) index="1" ;;
      *"-iot-eval" )  index="2" ;;
    esac

  fi

  if [ -n "$index" ] && ! grep -q '<InstallFrom>' "$tmp"; then
    if ! sed -i \
      '0,/<InstallTo>/{ /<InstallTo>/i\
          <InstallFrom>\
            <MetaData wcm:action="add">\
              <Key>/IMAGE/INDEX</Key>\
              <Value>'"$index"'</Value>\
            </MetaData>\
          </InstallFrom>
      }' "$tmp"; then
      rm -f "$tmp"
      error "Failed to select evaluation image index $index!"
      return 1
    fi
  fi

  if ! xmllint --nonet --noout "$tmp"; then
    rm -f "$tmp"
    error "Generated evaluation answer file is invalid!"
    return 1
  fi

  if ! chmod 644 "$tmp" || ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    error "Failed to create evaluation answer file: $target"
    return 1
  fi

  return 0
}

setXML() {

  local file="/custom.xml"
  local index="${2:-}"

  CUSTOM_XML=""

  if [ -d "$file" ]; then
    error "The bind $file maps to a file that does not exist!" && exit 67
  fi

  [ ! -f "$file" ] || [ ! -s "$file" ] && file="$STORAGE/custom.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && file="/run/assets/custom.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && file="$1"

  if [[ "${DETECTED,,}" == *"-eval" ]]; then
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
      generateEvalXML "$DETECTED" "$index" || return 1
    fi
  fi

  [ ! -f "$file" ] || [ ! -s "$file" ] && file="/run/assets/$DETECTED.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && return 1

  case "$file" in
    "/custom.xml" | "$STORAGE/custom.xml" ) CUSTOM_XML="Y" ;;
  esac

  XML="$file"
  return 0
}

updateDomain() {

  local asset="$1"
  local domain account auth pass pw
  local cred_domain ou arch tmp result

  domain=$(escapeXML "$2") || return 1
  account=$(escapeXML "$3") || return 1
  auth=$(escapeXML "$4") || return 1
  pass=$(escapeXML "$5") || return 1
  pw="$6"
  ou=$(escapeXML "$7") || return 1

  arch=$(sed -n -E \
    '0,/processorArchitecture="/s/.*processorArchitecture="([^"]+)".*/\1/p' \
    "$asset") || return 1

  [ -z "$arch" ] && return 1

  cred_domain="$domain"

  case "$4" in
    *@* ) cred_domain="" ;;
  esac

  grep -Eq 'Microsoft-Windows-UnattendedJoin|<DomainAccounts([[:space:]/>])' "$asset" && return 1

  tmp=$(mktemp -d) || return 1
  result="$tmp/answer.xml"

  if ! DOMAIN_XML="$domain" ACCOUNT_XML="$account" \
    AUTH_XML="$auth" PASS_XML="$pass" \
    CRED_DOMAIN="$cred_domain" PW="$pw" OU_XML="$ou" \
    ARCH_XML="$arch" \
    awk '
      /<settings[^>]*pass="specialize"[^>]*>/ { section = "specialize" }
      /<settings[^>]*pass="oobeSystem"[^>]*>/ { section = "oobeSystem" }
      section == "oobeSystem" && /<UserAccounts([[:space:]>])/ { in_accounts = 1 }
      section == "oobeSystem" && /<AutoLogon([[:space:]>])/ { in_autologon = 1 }

      section == "oobeSystem" && in_accounts && !accounts_added &&
        /<AdministratorPassword([[:space:]>])/ {
        print "        <DomainAccounts>\n" \
              "          <DomainAccountList wcm:action=\"add\">\n" \
              "            <DomainAccount wcm:action=\"add\">\n" \
              "              <Name>" ENVIRON["ACCOUNT_XML"] "</Name>\n" \
              "              <Group>Administrators</Group>\n" \
              "            </DomainAccount>\n" \
              "            <Domain>" ENVIRON["DOMAIN_XML"] "</Domain>\n" \
              "          </DomainAccountList>\n" \
              "        </DomainAccounts>"
        accounts_added = 1
      }

      section == "oobeSystem" && in_autologon &&
        /^[[:space:]]*<Username>.*<\/Username>[[:space:]]*$/ {
        print "        <Username>" ENVIRON["ACCOUNT_XML"] "</Username>\n" \
              "        <Domain>" ENVIRON["DOMAIN_XML"] "</Domain>"
        autologon_added = 1
        next
      }

      section == "oobeSystem" && in_autologon &&
        /^[[:space:]]*<Domain([[:space:]/>])/ { next }

      section == "oobeSystem" && in_autologon &&
        /^[[:space:]]*<Value>.*<\/Value>[[:space:]]*$/ {
        print "          <Value>" ENVIRON["PW"] "</Value>"
        password_added = 1
        next
      }

      section == "specialize" && !join_added &&
        /^[[:space:]]*<\/settings>[[:space:]]*$/ {
        print "    <component name=\"Microsoft-Windows-UnattendedJoin\" processorArchitecture=\"" ENVIRON["ARCH_XML"] "\" publicKeyToken=\"31bf3856ad364e35\" language=\"neutral\" versionScope=\"nonSxS\">\n" \
              "      <Identification>\n" \
              "        <Credentials>"

        if (ENVIRON["CRED_DOMAIN"] != "") {
          print "          <Domain>" ENVIRON["CRED_DOMAIN"] "</Domain>"
        }

        print "          <Username>" ENVIRON["AUTH_XML"] "</Username>\n" \
              "          <Password>" ENVIRON["PASS_XML"] "</Password>\n" \
              "        </Credentials>\n" \
              "        <JoinDomain>" ENVIRON["DOMAIN_XML"] "</JoinDomain>"

        if (ENVIRON["OU_XML"] != "") {
          print "        <MachineObjectOU>" ENVIRON["OU_XML"] "</MachineObjectOU>"
        }

        print "      </Identification>\n" \
              "    </component>"

        join_added = 1
      }

      { print }

      section == "oobeSystem" && /<\/AutoLogon>/ { in_autologon = 0 }
      section == "oobeSystem" && /<\/UserAccounts>/ { in_accounts = 0 }
      /^[[:space:]]*<\/settings>[[:space:]]*$/ { section = "" }

      END { exit !(join_added && accounts_added && autologon_added && password_added) }
    ' "$asset" > "$result" ||
    ! mv -f "$result" "$asset"; then

    rm -rf "$tmp" || true
    return 1
  fi

  rm -rf "$tmp" || return 1
  return 0
}

updateWorkgroup() {

  local asset="$1"
  local workgroup arch tmp result

  workgroup=$(escapeXML "$2") || return 1
  arch=$(sed -n -E '0,/processorArchitecture="/s/.*processorArchitecture="([^"]+)".*/\1/p' "$asset") || return 1
  [ -z "$arch" ] && return 1

  grep -q 'Microsoft-Windows-UnattendedJoin' "$asset" && return 1

  tmp=$(mktemp -d) || return 1
  result="$tmp/answer.xml"

  if ! WORKGROUP_XML="$workgroup" ARCH_XML="$arch" awk '
      /<settings[^>]*pass="specialize"[^>]*>/ { section = "specialize" }

      section == "specialize" && !workgroup_added &&
        /^[[:space:]]*<\/settings>[[:space:]]*$/ {
        print "    <component name=\"Microsoft-Windows-UnattendedJoin\" processorArchitecture=\"" ENVIRON["ARCH_XML"] "\" publicKeyToken=\"31bf3856ad364e35\" language=\"neutral\" versionScope=\"nonSxS\">\n" \
              "      <Identification>\n" \
              "        <JoinWorkgroup>" ENVIRON["WORKGROUP_XML"] "</JoinWorkgroup>\n" \
              "      </Identification>\n" \
              "    </component>"
        workgroup_added = 1
      }

      { print }

      /^[[:space:]]*<\/settings>[[:space:]]*$/ { section = "" }
      END { exit !workgroup_added }
    ' "$asset" > "$result" ||
    ! mv -f "$result" "$asset"; then

    rm -rf "$tmp" || true
    return 1
  fi

  rm -rf "$tmp" || return 1
  return 0
}

updateXML() {

  local asset="$1"
  local language="$2"
  local app value culture region keyboard edition
  local user user_xml auth_user admin pass pw
  local domain qualifier host workgroup key

  [ -z "${WIDTH:-}" ] && WIDTH="1280"
  [ -z "${HEIGHT:-}" ] && HEIGHT="720"

  validateResolution "WIDTH" "$WIDTH" 320 || return 1
  validateResolution "HEIGHT" "$HEIGHT" 200 || return 1
  validateMembership || return 1
  validateComputerName "${HOST:-}" || return 1
  validateProductKey "${KEY:-}" || return 1
  validatePassword "${PASSWORD:-}" || return 1

  app=$(escapeXMLSed "$APP for $ENGINE") || return 1

  sed -i "s|>Windows for Docker<|>$app<|g" "$asset" || return 1
  sed -i -E "s|<VerticalResolution>[^<]*</VerticalResolution>|<VerticalResolution>$HEIGHT</VerticalResolution>|g" "$asset" || return 1
  sed -i -E "s|<HorizontalResolution>[^<]*</HorizontalResolution>|<HorizontalResolution>$WIDTH</HorizontalResolution>|g" "$asset" || return 1

  if [ -n "${HOST:-}" ]; then
    host=$(escapeXMLSed "$HOST") || return 1
    sed -i -E "s|<ComputerName>[^<]*</ComputerName>|<ComputerName>$host</ComputerName>|g" "$asset" || return 1
  fi

  culture=$(getLanguage "$language" "culture") || return 1

  if [ -n "$culture" ] && [[ "${culture,,}" != "en-us" ]]; then
    value=$(escapeXMLSed "$culture") || return 1
    sed -i "s|<UILanguage>en-US</UILanguage>|<UILanguage>$value</UILanguage>|g" "$asset" || return 1
  fi

  region="${REGION:-}"
  [ -z "$region" ] && region="$culture"

  if [ -n "$region" ] && [[ "${region,,}" != "en-us" ]]; then
    value=$(escapeXMLSed "$region") || return 1
    sed -i "s|<UserLocale>en-US</UserLocale>|<UserLocale>$value</UserLocale>|g" "$asset" || return 1
    sed -i "s|<SystemLocale>en-US</SystemLocale>|<SystemLocale>$value</SystemLocale>|g" "$asset" || return 1
  fi

  keyboard="${KEYBOARD:-}"
  [ -z "$keyboard" ] && keyboard="$culture"

  if [ -n "$keyboard" ] && [[ "${keyboard,,}" != "en-us" ]]; then
    value=$(escapeXMLSed "$keyboard") || return 1
    sed -i "s|<InputLocale>en-US</InputLocale>|<InputLocale>$value</InputLocale>|g" "$asset" || return 1
    sed -i "s|<InputLocale>0409:00000409</InputLocale>|<InputLocale>$value</InputLocale>|g" "$asset" || return 1
  fi

  domain="${DOMAIN:-}"
  workgroup="${WORKGROUP:-}"

  if [ -n "$domain" ]; then

    if [ -z "${USERNAME:-}" ]; then
      error "The USERNAME variable must be specified when joining a domain!"
      return 1
    fi

    if [ -z "${PASSWORD:-}" ]; then
      error "The PASSWORD variable must be specified when joining a domain!"
      return 1
    fi

    validateDomainName "$domain" || return 1

    auth_user="$USERNAME"
    qualifier=""

    if [[ "$auth_user" == *\\* ]]; then
      error "The USERNAME variable must use either \"user\" or \"user@domain\" format!"
      return 1
    fi

    case "$auth_user" in
      *@* )
        user="${auth_user%%@*}"
        qualifier="${auth_user#*@}"

        if [ -z "$user" ] || [ -z "$qualifier" ] || [[ "$qualifier" == *@* ]]; then
          error "The USERNAME variable does not contain a valid domain account name!"
          return 1
        fi

        validateDomainName "$qualifier" "USERNAME" || return 1

        if [[ "${qualifier,,}" != "${domain,,}" ]]; then
          error "The domain in the USERNAME variable must match the DOMAIN variable!"
          return 1
        fi
        ;;
      * )
        user="$auth_user"
        ;;
    esac

    validateUsername "$user" "domain" || return 1

    if [[ "${user,,}" == "docker" ]]; then
      error "The USERNAME variable must be changed from its default value when joining a domain!"
      return 1
    fi

    if [[ "$PASSWORD" == "admin" ]]; then
      error "The PASSWORD variable must be changed from its default value when joining a domain!"
      return 1
    fi

  else

    user="${USERNAME:-}"
    validateUsername "$user" "local" || return 1

    if [ -n "$user" ]; then
      user_xml=$(escapeXMLSed "$user") || return 1

      sed -i "s|-name \"Docker\"|-name \"\$env:USERNAME\"|g" "$asset" || return 1
      sed -i 's|where name="Docker"|where name="%USERNAME%"|g' "$asset" || return 1
      sed -i "s|<Name>Docker</Name>|<Name>$user_xml</Name>|g" "$asset" || return 1
      sed -i "s|<FullName>Docker</FullName>|<FullName>$user_xml</FullName>|g" "$asset" || return 1
      sed -i "s|<Username>Docker</Username>|<Username>$user_xml</Username>|g" "$asset" || return 1
    fi

    [ -n "${PASSWORD:-}" ] && pass="$PASSWORD" || pass="admin"

    pw=$(printf '%s' "${pass}Password" | iconv -f utf-8 -t utf-16le | base64 -w 0) || return 1
    admin=$(printf '%s' "${pass}AdministratorPassword" | iconv -f utf-8 -t utf-16le | base64 -w 0) || return 1

    sed -i -z -E "s#(<Password>[[:space:]]*<Value)([[:space:]]*/>|>[^<]*</Value>)#\1>$pw</Value>#g" "$asset" || return 1
    sed -i -z -E "s#(<AdministratorPassword>[[:space:]]*<Value)([[:space:]]*/>|>[^<]*</Value>)#\1>$admin</Value>#g" "$asset" || return 1

  fi

  sed -i -E "s|<PlainText>[^<]*</PlainText>|<PlainText>false</PlainText>|g" "$asset" || return 1

  if [ -n "$domain" ]; then

    pw=$(printf '%s' "${PASSWORD}Password" | iconv -f utf-8 -t utf-16le | base64 -w 0) || return 1

    if ! updateDomain "$asset" "$domain" "$user" \
      "$auth_user" "$PASSWORD" "$pw" "$DOMAIN_OU"; then
      error "Failed to add domain configuration to answer file!"
      return 1
    fi

    if ! sed -i -E \
      -e '/^[[:space:]]*<LocalAccounts([[:space:]>])/,/^[[:space:]]*<\/LocalAccounts>[[:space:]]*$/d' \
      -e '/^[[:space:]]*<AdministratorPassword([[:space:]>])/,/^[[:space:]]*<\/AdministratorPassword>[[:space:]]*$/d' \
      "$asset"; then
      error "Failed to remove local account configuration from answer file!"
      return 1
    fi

    if ! sed -i -E '
      /<SynchronousCommand([[:space:]>])/ {
        :command
        N
        /<\/SynchronousCommand>/!b command
        /<Description>Password Never Expires<\/Description>/d
      }
    ' "$asset"; then
      error "Failed to remove local account commands from answer file!"
      return 1
    fi

  elif [ -n "$workgroup" ]; then

    if ! updateWorkgroup "$asset" "$workgroup"; then
      error "Failed to add workgroup configuration to answer file!"
      return 1
    fi

  fi

  if disabled "${AUTOLOGIN:-}"; then
    sed -i -E '/^[[:space:]]*<AutoLogon([[:space:]>])/,/^[[:space:]]*<\/AutoLogon>[[:space:]]*$/d' "$asset" || return 1
  fi

  if [ -n "${EDITION:-}" ]; then
    case "${EDITION,,}" in
      "core" ) edition="STANDARDCORE" ;;
      * ) edition="${EDITION^^}" ;;
    esac

    edition=$(escapeXMLSed "$edition") || return 1
    sed -i "s|SERVERSTANDARD</Value>|SERVER$edition</Value>|g" "$asset" || return 1
  fi

  if [ -n "${KEY:-}" ]; then
    key=$(escapeXMLSed "$KEY") || return 1
    sed -i -E '/^[[:space:]]*<ProductKey>[[:space:]]*$/,/^[[:space:]]*<\/ProductKey>[[:space:]]*$/d' "$asset" || return 1
    sed -i -E "s|<ProductKey>[^<]*</ProductKey>|<ProductKey>$key</ProductKey>|g" "$asset" || return 1
    sed -i "s|</UserData>|  <ProductKey>\n          <Key>$key</Key>\n          <WillShowUI>OnError</WillShowUI>\n        </ProductKey>\n      </UserData>|g" "$asset" || return 1
  fi

  if disabled "${SHORTCUT:-}" || disabled "${SAMBA:-}"; then
    if ! sed -i -E '
      /<SynchronousCommand([[:space:]>])/ {
        :command
        N
        /<\/SynchronousCommand>/!b command
        /<Description>Create desktop shortcut to shared folder<\/Description>/d
        /<Description>Map shared folder<\/Description>/d
      }
    ' "$asset"; then
      error "Failed to remove shared folder shortcuts from answer file!"
      return 1
    fi
  fi

  if ! xmllint --nonet --noout "$asset"; then
    error "The generated answer file is not valid XML!"
    return 1
  fi

  return 0
}

escapeSIFValue() {

  local s="$1"

  s=${s//%/%%}
  s=${s//\"/\"\"}

  printf '%s' "$s"
  return 0
}

escapeRegistryValue() {

  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

validateLegacyText() {

  local name="$1"
  local value="$2"
  local desc="${3:-}"
  local suffix=""

  [ -n "$desc" ] && suffix=" for $desc"

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    error "The $name variable cannot contain control characters$suffix!"
    return 1
  fi

  if [[ "$value" == *'"'* ]]; then
    error "The $name variable cannot contain double quotes$suffix!"
    return 1
  fi

  return 0
}

validateLegacyUsername() {

  local value="$1"
  local desc="${2:-}"
  local suffix=""

  [ -n "$desc" ] && suffix=" for $desc"

  if [ -z "$value" ]; then
    error "The USERNAME variable cannot be empty$suffix!"
    return 1
  fi

  if [ "${#value}" -gt 20 ]; then
    error "The USERNAME variable cannot contain more than 20 characters$suffix!"
    return 1
  fi

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    error "The USERNAME variable cannot contain control characters$suffix!"
    return 1
  fi

  case "$value" in
    *'"'* | *'/'* | *\\* | *'['* | *']'* | *':'* | *';'* | *'|'* | *'='* | *','* | *'+'* | *'*'* | *'?'* | *'<'* | *'>'* )
      error "The USERNAME variable contains unsupported characters$suffix!"
      return 1 ;;
  esac

  if [[ "$value" == *"." ]]; then
    error "The USERNAME variable cannot end with a period$suffix!"
    return 1
  fi

  if [[ "$value" =~ ^[.[:space:]]+$ ]]; then
    error "The USERNAME variable cannot consist only of spaces or periods$suffix!"
    return 1
  fi

  if [[ "${value^^}" == "GUEST" ]]; then
    error "The USERNAME value \"$value\" is reserved for a built-in Windows account$suffix!"
    return 1
  fi

  return 0
}

legacyInstall() {

  local pid=""
  local file=""
  local dir="$2"
  local desc="$3"
  local driver="$4"
  local drivers="/tmp/drivers"
  local shortcut="Y"

  if disabled "$SHORTCUT" || disabled "${SAMBA:-Y}"; then
    shortcut="N"
  fi

  if [ -n "$DOMAIN" ]; then
    error "The DOMAIN variable is not supported for $desc!"
    return 1
  fi

  ETFS="[BOOT]/Boot-NoEmul.img"

  if [ ! -f "$dir/$ETFS" ] || [ ! -s "$dir/$ETFS" ]; then
    error "Failed to locate file \"$ETFS\" in $desc ISO image!" && return 1
  fi

  local arch target
  [ -d "$dir/AMD64" ] && arch="amd64" || arch="x86"
  [[ "${arch,,}" == "x86" ]] && target="$dir/I386" || target="$dir/AMD64"

  if [ ! -d "$target" ]; then
    error "Failed to locate directory \"$target\" in $desc ISO image!" && return 1
  fi

  if [[ "${driver,,}" == "xp" || "${driver,,}" == "2k3" ]]; then

    local msg="Adding drivers to image..."
    info "$msg" && html "$msg"

    rm -rf "$drivers" || return 1
    mkdir -p "$drivers" || return 1

    if ! bsdtar -xf /var/drivers.txz -C "$drivers"; then
      error "Failed to extract drivers!" && return 1
    fi

    if [ ! -f "$drivers/viostor/$driver/$arch/viostor.sys" ]; then
      error "Failed to locate required storage drivers!" && return 1
    fi

    cp -L "$drivers/viostor/$driver/$arch/viostor.sys" "$target" || return 1

    mkdir -p "$dir/\$OEM\$/\$1/Drivers/viostor" || return 1
    cp -L "$drivers/viostor/$driver/$arch/viostor.cat" "$dir/\$OEM\$/\$1/Drivers/viostor" || return 1
    cp -L "$drivers/viostor/$driver/$arch/viostor.inf" "$dir/\$OEM\$/\$1/Drivers/viostor" || return 1
    cp -L "$drivers/viostor/$driver/$arch/viostor.sys" "$dir/\$OEM\$/\$1/Drivers/viostor" || return 1

    if [ ! -f "$drivers/NetKVM/$driver/$arch/netkvm.sys" ]; then
      error "Failed to locate required network drivers!" && return 1
    fi

    mkdir -p "$dir/\$OEM\$/\$1/Drivers/NetKVM" || return 1
    cp -L "$drivers/NetKVM/$driver/$arch/netkvm.cat" "$dir/\$OEM\$/\$1/Drivers/NetKVM" || return 1
    cp -L "$drivers/NetKVM/$driver/$arch/netkvm.inf" "$dir/\$OEM\$/\$1/Drivers/NetKVM" || return 1
    cp -L "$drivers/NetKVM/$driver/$arch/netkvm.sys" "$dir/\$OEM\$/\$1/Drivers/NetKVM" || return 1

    file=$(find "$target" -maxdepth 1 -type f -iname TXTSETUP.SIF -print -quit) || return 1

    if [ -z "$file" ]; then
      error "The file TXTSETUP.SIF could not be found!" && return 1
    fi

    sed -i '/^\[SCSI.Load\]/s/$/\nviostor=viostor.sys,4/' "$file" || return 1
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\nviostor.sys=1,,,,,,4_,4,1,,,1,4/' "$file" || return 1
    sed -i '/^\[SCSI\]/s/$/\nviostor=\"Red Hat VirtIO SCSI Disk Device\"/' "$file" || return 1
    sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00000000=\"viostor\"/' "$file" || return 1
    sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00020000=\"viostor\"/' "$file" || return 1
    sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00021AF4=\"viostor\"/' "$file" || return 1

    if [ ! -d "$drivers/sata/xp/$arch" ]; then
      error "Failed to locate required SATA drivers!" && return 1
    fi

    mkdir -p "$dir/\$OEM\$/\$1/Drivers/sata" || return 1
    cp -Lr "$drivers/sata/xp/$arch/." "$dir/\$OEM\$/\$1/Drivers/sata" || return 1
    cp -Lr "$drivers/sata/xp/$arch/." "$target" || return 1

    sed -i '/^\[SCSI.Load\]/s/$/\niaStor=iaStor.sys,4/' "$file" || return 1
    sed -i '/^\[FileFlags\]/s/$/\niaStor.sys = 16/' "$file" || return 1
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.cat = 1,,,,,,,1,0,0/' "$file" || return 1
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.inf = 1,,,,,,,1,0,0/' "$file" || return 1
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.sys = 1,,,,,,4_,4,1,,,1,4/' "$file" || return 1
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.sys = 1,,,,,,,1,0,0/' "$file" || return 1
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaahci.cat = 1,,,,,,,1,0,0/' "$file" || return 1
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaAHCI.inf = 1,,,,,,,1,0,0/' "$file" || return 1
    sed -i '/^\[SCSI\]/s/$/\niaStor=\"Intel\(R\) SATA RAID\/AHCI Controller\"/' "$file" || return 1
    sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_8086\&DEV_2922\&CC_0106=\"iaStor\"/' "$file" || return 1

    rm -rf "$drivers" || return 1

  fi

  local key setup
  setup=$(find "$target" -maxdepth 1 -type f -iname setupp.ini -print -quit) || return 1

  if [ -n "$setup" ] && [ -z "$KEY" ]; then

    pid=$(<"$setup") || return 1
    pid="${pid%$'\r'}"

    if [[ "$driver" == "2k" ]]; then

      echo "${pid:0:$((${#pid})) - 3}270" > "$setup" || return 1

    else

      if [[ "$pid" == *"270" ]]; then

        warn "this version of $desc requires a volume license key (VLK), it will ask for one during installation."

      else

        file=$(find "$target" -maxdepth 1 -type f -iname PID.INF -print -quit) || return 1

        if [ -n "$file" ]; then

          if [[ "$driver" == "2k3" ]]; then

            key=$(grep -i -A 2 "StagingKey" "$file" | tail -n 2 | head -n 1) || key=""

          else

            key="${pid:$((${#pid})) - 8:5}"

            if [[ "${pid^^}" == *"OEM" ]]; then
              key=$(grep -i -A 2 "$key" "$file" | tail -n 2 | head -n 1) || key=""
            else
              key=$(grep -i -m 1 -A 2 "$key" "$file" | tail -n 2 | head -n 1) || key=""
            fi

            key="${key#*= }"

          fi

          key="${key%$'\r'}"
          [[ "${#key}" == "29" ]] && KEY="$key"

        fi

        if [ -z "$KEY" ]; then

          # These are NOT pirated keys, they come from official MS documentation.

          case "${driver,,}" in
            "xp" )

              if [[ "${arch,,}" == "x86" ]]; then
                # Windows XP Professional x86 generic trial key (no activation)
                KEY="DR8GV-C8V6J-BYXHG-7PYJR-DB66Y"
              else
                # Windows XP Professional x64 generic trial key (no activation)
                KEY="B2RBK-7KPT9-4JP6X-QQFWM-PJD6G"
              fi
              ;;

            "2k3" )

              if [[ "${arch,,}" == "x86" ]]; then
                # Windows Server 2003 Standard x86 generic trial key (no activation)
                KEY="QKDCQ-TP2JM-G4MDG-VR6F2-P9C48"
              else
                # Windows Server 2003 Standard x64 generic trial key (no activation)
                KEY="P4WJG-WK3W7-3HM8W-RWHCK-8JTRY"
              fi
              ;;

          esac

          echo "${pid:0:$((${#pid})) - 3}000" > "$setup" || return 1

        fi

      fi

    fi

  fi

  validateProductKey "$KEY" || return 1

  local product=""
  [ -n "$KEY" ] && product="ProductID=$KEY"

  mkdir -p "$dir/\$OEM\$" || return 1

  if ! addFolder "$dir"; then
    error "Failed to add OEM folder to image!" && return 1
  fi

  local oem=""
  local install="$dir/\$OEM\$/\$1/OEM/install.bat"
  [ -f "$install" ] && oem="\"Script\"=\"cmd /C start \\\"Install\\\" \\\"cmd /C C:\\\\OEM\\\\install.bat\\\"\""

  [ -z "$WIDTH" ] && WIDTH="1280"
  [ -z "$HEIGHT" ] && HEIGHT="720"

  validateResolution "WIDTH" "$WIDTH" 320 || return 1
  validateResolution "HEIGHT" "$HEIGHT" 200 || return 1
  validateMembership || return 1
  validateComputerName "$HOST" || return 1
  validateLegacyText "APP" "$APP" "$desc" || return 1
  validateLegacyText "ENGINE" "$ENGINE" "$desc" || return 1

  XHEX=$(printf '%08x\n' "$((10#$WIDTH))") || return 1
  YHEX=$(printf '%08x\n' "$((10#$HEIGHT))") || return 1

  local username="${USERNAME:-Docker}"
  local password="${PASSWORD:-admin}"
  local workgroup="${WORKGROUP:-WORKGROUP}"

  local sifHost sifUsername sifPassword sifOrganization sifWorkgroup
  local regUsername regPassword

  validateLegacyUsername "$username" "$desc" || return 1
  validatePassword "$password" "$desc" || return 1

  sifHost=$(escapeSIFValue "${HOST:-*}") || return 1
  sifUsername=$(escapeSIFValue "$username") || return 1
  sifPassword=$(escapeSIFValue "$password") || return 1
  sifOrganization=$(escapeSIFValue "$APP for $ENGINE") || return 1
  sifWorkgroup=$(escapeSIFValue "$workgroup") || return 1
  regUsername=$(escapeRegistryValue "$username") || return 1
  regPassword=$(escapeRegistryValue "$password") || return 1

  find "$target" -maxdepth 1 -type f -iname winnt.sif -delete || return 1

  {
    printf '%s\n' \
      '[Data]' \
      '    AutoPartition=1' \
      '    MsDosInitiated="0"' \
      '    UnattendedInstall="Yes"' \
      '    AutomaticUpdates="Yes"' \
      '' \
      '[Unattended]' \
      '    UnattendSwitch=Yes' \
      '    UnattendMode=FullUnattended' \
      '    FileSystem=NTFS' \
      '    OemSkipEula=Yes' \
      '    OemPreinstall=Yes' \
      '    Repartition=Yes' \
      '    WaitForReboot="No"' \
      '    DriverSigningPolicy="Ignore"' \
      '    NonDriverSigningPolicy="Ignore"' \
      '    OemPnPDriversPath="Drivers\viostor;Drivers\NetKVM;Drivers\sata"' \
      '    NoWaitAfterTextMode=1' \
      '    NoWaitAfterGUIMode=1' \
      '    FileSystem=ConvertNTFS' \
      '    ExtendOemPartition=0' \
      '    Hibernation="No"' \
      '' \
      '[GuiUnattended]' \
      '    OEMSkipRegional=1' \
      '    OemSkipWelcome=1' \
      "    AdminPassword=\"$sifPassword\"" \
      '    TimeZone=0'

    if disabled "$AUTOLOGIN"; then
      printf '%s\n' '    AutoLogon=No'
    else
      printf '%s\n' \
        '    AutoLogon=Yes' \
        '    AutoLogonCount=65432'
    fi

    printf '%s\n' \
      '' \
      '[UserData]' \
      "    FullName=\"$sifUsername\"" \
      "    ComputerName=\"$sifHost\"" \
      "    OrgName=\"$sifOrganization\"" \
      "    $product" \
      '' \
      '[Identification]' \
      "    JoinWorkgroup = \"$sifWorkgroup\"" \
      '' \
      '[Display]' \
      '    BitsPerPel=32' \
      "    XResolution=$WIDTH" \
      "    YResolution=$HEIGHT" \
      '' \
      '[Networking]' \
      '    InstallDefaultComponents=Yes' \
      '' \
      '[Branding]' \
      '    BrandIEUsingUnattended=Yes' \
      '' \
      '[URL]' \
      '    Home_Page = http://www.google.com' \
      '    Search_Page = http://www.google.com' \
      '' \
      '[TerminalServices]' \
      '    AllowConnections=1' \
      ''
  } | unix2dos > "$target/WINNT.SIF" || return 1

  if [[ "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[Components]' \
        '    TerminalServer=On' \
        '' \
        '[LicenseFilePrintData]' \
        '    AutoMode=PerServer' \
        '    AutoUsers=5' \
        ''
    } | unix2dos >> "$target/WINNT.SIF" || return 1
  fi

  {
    printf '%s\n' \
      'Windows Registry Editor Version 5.00' \
      '' \
      '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Security]' \
      '"FirstRunDisabled"=dword:00000001' \
      '"UpdatesDisableNotify"=dword:00000001' \
      '"FirewallDisableNotify"=dword:00000001' \
      '"AntiVirusDisableNotify"=dword:00000001' \
      '' \
      '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\wscsvc]' \
      '"Start"=dword:00000004' \
      '' \
      '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile\GloballyOpenPorts\List]' \
      '"3389:TCP"="3389:TCP:*:Enabled:@xpsp2res.dll,-22009"' \
      '' \
      '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Applets\Tour]' \
      '"RunCount"=dword:00000000' \
      '' \
      '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]' \
      '"HideFileExt"=dword:00000000' \
      '' \
      '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer]' \
      '"NoWelcomeScreen"="1"' \
      '' \
      '[HKEY_CURRENT_USER\Software\Microsoft\Internet Connection Wizard]' \
      '"Completed"="1"' \
      '"Desktopchanged"="1"' \
      '' \
      '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]'

    if disabled "$AUTOLOGIN"; then
      printf '%s\n' '"AutoAdminLogon"="0"'
    else
      printf '%s\n' \
        '"AutoAdminLogon"="1"' \
        "\"DefaultUserName\"=\"$regUsername\"" \
        "\"DefaultPassword\"=\"$regPassword\""
    fi

    printf '%s\n' \
      '' \
      '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Video\{23A77BF7-ED96-40EC-AF06-9B1F4867732A}\0000]' \
      '"DefaultSettings.BitsPerPel"=dword:00000020' \
      "\"DefaultSettings.XResolution\"=dword:$XHEX" \
      "\"DefaultSettings.YResolution\"=dword:$YHEX" \
      '' \
      '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Control\VIDEO\{23A77BF7-ED96-40EC-AF06-9B1F4867732A}\0000]' \
      '"DefaultSettings.BitsPerPel"=dword:00000020' \
      "\"DefaultSettings.XResolution\"=dword:$XHEX" \
      "\"DefaultSettings.YResolution\"=dword:$YHEX" \
      '' \
      '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce]' \
      '"ScreenSaver"="reg add \"HKCU\\Control Panel\\Desktop\" /f /v \"SCRNSAVE.EXE\" /t REG_SZ /d \"off\""' \
      '"ScreenSaverOff"="reg add \"HKCU\\Control Panel\\Desktop\" /f /v \"ScreenSaveActive\" /t REG_SZ /d \"0\""'

    if enabled "$shortcut"; then
      printf '%s\n' '"SharedDrive"="cmd /C net use Z: \\\\host.lan\\Data /persistent:yes"'
    fi

    printf '%s\n' "$oem" ''
  } | unix2dos > "$dir/\$OEM\$/install.reg" || return 1

  if [[ "$driver" == "2k" ]]; then
    {
      printf '%s\n' \
        '[HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Runonce]' \
        '"^SetupICWDesktop"=-' \
        ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  if [[ "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\srvWiz]' \
        '@=dword:00000000' \
        '' \
        '[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\ServerOOBE\SecurityOOBE]' \
        '"DontLaunchSecurityOOBE"=dword:00000000' \
        ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  {
    printf '%s\n' \
      'Set WshShell = WScript.CreateObject("WScript.Shell")' \
      'Set WshNetwork = WScript.CreateObject("WScript.Network")' \
      'Set Domain = GetObject("WinNT://" & WshNetwork.ComputerName)' \
      '' \
      'Function DecodeSID(binSID)' \
      '  ReDim o(LenB(binSID))' \
      '' \
      '  For i = 1 To LenB(binSID)' \
      '    o(i-1) = AscB(MidB(binSID, i, 1))' \
      '  Next' \
      '' \
      '  sid = "S-" & CStr(o(0)) & "-" & OctetArrayToString _' \
      '        (Array(o(2), o(3), o(4), o(5), o(6), o(7)))' \
      '  For i = 8 To (4 * o(1) + 4) Step 4' \
      '    sid = sid & "-" & OctetArrayToString _' \
      '          (Array(o(i+3), o(i+2), o(i+1), o(i)))' \
      '  Next' \
      '' \
      '  DecodeSID = sid' \
      'End Function' \
      '' \
      'Function OctetArrayToString(arr)' \
      '  v = 0' \
      '  For i = 0 To UBound(arr)' \
      '    v = v * 256 + arr(i)' \
      '  Next' \
      '' \
      '  OctetArrayToString = CStr(v)' \
      'End Function' \
      '' \
      'For Each DomainItem in Domain' \
      '  If DomainItem.Class = "User" Then' \
      '    sid = DecodeSID(DomainItem.Get("objectSID"))' \
      '    If Left(sid, 9) = "S-1-5-21-" And Right(sid, 4) = "-500" Then' \
      '      LocalAdminADsPath = DomainItem.ADsPath' \
      '      Exit For' \
      '    End If' \
      '  End If' \
      'Next' \
      '' \
      "Call Domain.MoveHere(LocalAdminADsPath, \"$username\")" \
      ''

    if enabled "$shortcut"; then
      printf '%s\n' \
        'Set oLink = WshShell.CreateShortcut(WshShell.SpecialFolders("Desktop") & "\Shared.lnk")' \
        'With oLink' \
        '  .TargetPath = "\\host.lan\Data"' \
        '  .Save' \
        'End With' \
        'Set oLink = Nothing' \
        ''
    fi
  } | unix2dos > "$dir/\$OEM\$/install.vbs" || return 1

  {
    printf '%s\n' \
      '[COMMANDS]' \
      '"REGEDIT /s install.reg"' \
      '"Wscript install.vbs"' \
      ''
  } | unix2dos > "$dir/\$OEM\$/cmdlines.txt" || return 1

  return 0
}

legacyPrepare() {

  local iso="$1"
  local dir="$2"
  local desc="$3"

  local tmp="$TMP/boot-images"
  local image="$tmp/eltorito_img1_bios.img"

  ETFS="boot.img"

  [ -s "$dir/$ETFS" ] && return 0
  rm -f "$dir/$ETFS" || return 1
  rm -rf "$tmp" || return 1

  if ! LC_ALL=C xorriso \
      -no_rc \
      -osirrox on \
      -indev "$iso" \
      -extract_boot_images "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp" || true
    error "Failed to extract boot image from $desc ISO!"
    return 1
  fi

  if [ ! -s "$image" ]; then
    rm -rf "$tmp" || true
    error "Failed to locate BIOS boot image in $desc ISO!"
    return 1
  fi

  if ! mv -f "$image" "$dir/$ETFS"; then
    rm -rf "$tmp" || true
    error "Failed to save boot image from $desc ISO!"
    return 1
  fi

  rm -rf "$tmp" || return 1
  return 0
}

return 0
