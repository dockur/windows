#!/usr/bin/env bash
set -Eeuo pipefail

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

findSetupScript() {

  local asset="$1"
  local dir name id normal candidate
  local candidates=()

  [ -z "${CUSTOM_XML:-}" ] || return 0
  [ -s "$asset" ] || return 0

  # Only migrated answer files receive a setup script. This allows the
  # remaining XML templates to keep using their existing embedded commands.
  grep -Fqi 'SetupComplete.cmd' "$asset" || return 0

  dir=$(dirname "$asset") || return 1
  name=$(basename "$asset") || return 1
  id="${name%.*}"
  normal="$id"

  candidates+=("$dir/$id.cmd")

  if [[ "${normal,,}" == *"-eval" ]]; then
    normal="${normal::-5}"
    candidates+=("$dir/$normal.cmd")
  fi

  # Generated edition-specific answer files inherit the script belonging to
  # their generic source template.
  case "${normal,,}" in
    "win7"* | "win8"* | "win10"* | "win11"* | "winvista"* | "win20"* )
      candidates+=("$dir/${normal%%-*}.cmd")
      ;;
  esac

  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate" ] && [ -s "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  error "Failed to find setup script for answer file: $asset"
  return 1
}

validateSetupScript() {

  local file="$1"
  local block begin_count end_count
  local blocks=(
    LOCAL_ACCOUNT
    PRODUCT_KEY
    SHARED_FOLDER
    OEM_SCRIPT
  )

  [ -s "$file" ] || return 1

  for block in "${blocks[@]}"; do
    begin_count=$(grep -Fxc -- "rem BEGIN $block" "$file" || true)
    end_count=$(grep -Fxc -- "rem END $block" "$file" || true)

    if [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
      error "Invalid $block markers in setup script: $file"
      return 1
    fi
  done

  return 0
}

stageSetupScript() {

  local asset="$1"
  local stage="$2"
  local result_name="$3"
  local source target

  printf -v "$result_name" '%s' ""

  source=$(findSetupScript "$asset") || return 1
  [ -n "$source" ] || return 0

  target="$stage/\$OEM\$/\$\$/Setup/Scripts/SetupComplete.cmd"

  if ! mkdir -p "$(dirname "$target")"; then
    error "Failed to create setup script directory!"
    return 1
  fi

  if ! cp -L -- "$source" "$target"; then
    error "Failed to stage setup script: $source"
    return 1
  fi

  # Work on a normalized copy so marker updates are independent of the line
  # endings stored in Git. The staged result is converted back to CRLF later.
  sed -i 's/\r$//' "$target" || return 1
  validateSetupScript "$target" || return 1

  printf -v "$result_name" '%s' "$target"
  return 0
}

installSetupScript() {

  local script="$1"
  local root="$2"
  local target

  [ -n "$script" ] || return 0
  [ -s "$script" ] || return 1

  target="$root/\$OEM\$/\$\$/Setup/Scripts/SetupComplete.cmd"

  if ! mkdir -p "$(dirname "$target")"; then
    error "Failed to create setup script directory!"
    return 1
  fi

  if ! cp -f -- "$script" "$target"; then
    error "Failed to add setup script to Windows image!"
    return 1
  fi

  return 0
}

escapeSetupSed() {

  local value="$1"

  value=${value//\\/\\\\}
  value=${value//&/\\&}
  value=${value//|/\\|}

  printf '%s' "$value"
  return 0
}

updateSetupVariable() {

  local file="$1"
  local block="$2"
  local variable="$3"
  local value="$4"
  local escaped count

  [ -s "$file" ] || return 1

  count=$(sed -n "/^rem BEGIN $block$/,/^rem END $block$/p" "$file" |
    grep -Ec "^set \"$variable=[^\"]*\"$" || true)

  if [ "$count" -ne 1 ]; then
    error "Failed to locate $variable in the $block block of setup script: $file"
    return 1
  fi

  escaped=$(escapeSetupSed "$value") || return 1

  if ! sed -i -E \
    "/^rem BEGIN $block$/,/^rem END $block$/ s|^set \"$variable=[^\"]*\"$|set \"$variable=$escaped\"|" \
    "$file"; then

    error "Failed to update $variable in setup script: $file"
    return 1
  fi

  return 0
}

removeSetupBlock() {

  local file="$1"
  local block="$2"

  [ -s "$file" ] || return 1

  if ! grep -Fqx -- "rem BEGIN $block" "$file" ||
    ! grep -Fqx -- "rem END $block" "$file"; then
    error "Failed to locate the $block block in setup script: $file"
    return 1
  fi

  if ! sed -i "/^rem BEGIN $block$/,/^rem END $block$/d" "$file"; then
    error "Failed to remove the $block block from setup script: $file"
    return 1
  fi

  return 0
}

finalizeSetupScript() {

  local file="$1"

  [ -n "$file" ] || return 0
  [ -s "$file" ] || return 1

  if ! unix2dos -q "$file"; then
    error "Failed to convert setup script to DOS format: $file"
    return 1
  fi

  return 0
}

stageAnswer() {

  local asset="$1"
  local language="$2"
  local stage="$3"
  local answer="$stage/Autounattend.xml"
  local script="" name

  if enabled "$MANUAL"; then
    removeGeneratedXML "$asset" || return 1
    return 0
  fi

  if [ ! -f "$asset" ] || [ ! -s "$asset" ]; then
    error "Failed to find answer file: $asset"
    return 1
  fi

  name=$(basename "$asset") || return 1
  info "Adding $name for automatic installation..."

  if ! cp -L -- "$asset" "$answer"; then
    error "Failed to stage answer file: $asset"
    return 1
  fi

  if [ -z "${CUSTOM_XML:-}" ]; then
    if ! stageSetupScript "$asset" "$stage" script; then
      error "Failed to stage setup script for answer file: $asset"
      return 1
    fi
  fi

  removeGeneratedXML "$asset" || return 1

  if [ -z "${CUSTOM_XML:-}" ]; then
    if ! updateXML "$answer" "$language" "$script"; then
      error "Failed to update answer file: $answer"
      return 1
    fi
  fi

  if ! updateDiskID "$answer" "${DISK_TYPE:-}"; then
    error "Failed to adjust the Windows installation disk!"
    return 1
  fi

  if ! setConfigurationXML "$answer"; then
    error "Failed to enable the Windows configuration set!"
    return 1
  fi

  validateGeneratedXML "$answer" || return 1

  return 0
}

markGeneratedXML() {

  local file="$1"
  local marker='<!-- generated-answer-file: do not reuse as a template -->'

  [ -s "$file" ] || return 1

  if head -n 1 "$file" | grep -q '^<?xml'; then
    sed -i "1a$marker" "$file" || return 1
  else
    sed -i "1i$marker" "$file" || return 1
  fi

  return 0
}

removeGeneratedXML() {

  local file="$1"

  [ -n "$file" ] || return 0
  [ -f "$file" ] || return 0

  head -n 5 "$file" |
    grep -Fqi 'generated-answer-file' || return 0

  if ! rm -f "$file"; then
    error "Failed to remove generated answer file: $file"
    return 1
  fi

  return 0
}

generateAnswerFile() {

  local id="$1"
  local source="$2"
  local target="$3"
  local index="$4"
  local type="$5"
  local remove_selector="$6"
  local tmp

  if [ -n "$index" ] && [[ ! "$index" =~ ^[1-9][0-9]*$ ]]; then
    error "Invalid $type image index: $index"
    return 1
  fi

  if ! tmp=$(mktemp -p /run/assets ".${id}.XXXXXX"); then
    error "Failed to create a temporary $type answer file!"
    return 1
  fi

  local expressions

  if [ "$type" = "evaluation" ]; then
    expressions=(
      -e '/<ProductKey>.*<\/ProductKey>/d'
      -e '/<ProductKey>/,/<\/ProductKey>/d'
    )
  else
    expressions=(
      -e '/<InstallFrom>.*<\/InstallFrom>/d'
      -e '/<ProductKey>.*<\/ProductKey>/d'
      -e '/<InstallFrom>/,/<\/InstallFrom>/d'
      -e '/<ProductKey>/,/<\/ProductKey>/d'
    )
  fi

  if ! sed "${expressions[@]}" "$source" > "$tmp"; then
    rm -f "$tmp"
    error "Failed to generate $type answer file from $source!"
    return 1
  fi

  if [ "$type" = "evaluation" ] && [ "$remove_selector" = "Y" ]; then
    if ! sed -i \
      -e '/<InstallFrom>.*<\/InstallFrom>/d' \
      -e '/<InstallFrom>/,/<\/InstallFrom>/d' \
      "$tmp"; then
      rm -f "$tmp"
      error "Failed to replace evaluation image selector!"
      return 1
    fi
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
      error "Failed to select $type image index $index!"
      return 1
    fi
  fi

  if ! markGeneratedXML "$tmp"; then
    rm -f "$tmp"
    error "Failed to mark generated $type answer file!"
    return 1
  fi

  if ! validateGeneratedXML "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  if ! chmod 644 "$tmp" || ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    error "Failed to create $type answer file: $target"
    return 1
  fi

  return 0
}

generateEvalXML() {

  # Evaluation templates are generated from their normal counterpart so
  # both variants remain identical except for evaluation-specific selectors.

  local id="$1"
  local detected_index="${2:-}"

  [[ "${id,,}" == *"-eval" ]] || return 1

  local normal="${id::-5}"
  local source="/run/assets/$normal.xml"
  local target="/run/assets/$id.xml"
  local index="$detected_index"
  local remove_selector="N"

  removeGeneratedXML "$source" || return 1

  if [ ! -s "$source" ]; then
    source="/run/assets/${normal%%-*}.xml"
    removeGeneratedXML "$source" || return 1
  fi

  [ -s "$source" ] || return 1

  if [ -n "$detected_index" ]; then
    remove_selector="Y"
  else
    # No WIM was inspected, so retain the known defaults for download routes.
    case "${id,,}" in
      *"-ltsc-eval" ) index="1" ;;
      *"-iot-eval" )  index="2" ;;
    esac
  fi

  generateAnswerFile \
    "$id" "$source" "$target" "$index" "evaluation" "$remove_selector" || return 1

  return 0
}

generateFallbackXML() {

  # Fallback templates are generated from the generic version so unsupported
  # editions can use the detected WIM index without inheriting a product key.

  local id="$1"
  local index="${2:-}"
  local source="/run/assets/${id%%-*}.xml"
  local target="/run/assets/$id.xml"

  [ "$source" != "$target" ] || return 1

  removeGeneratedXML "$source" || return 1
  [ -s "$source" ] || return 1

  generateAnswerFile \
    "$id" "$source" "$target" "$index" "fallback" "Y" || return 1

  return 0
}

setXML() {

  local file="$1"
  local index="${2:-}"
  local target="/run/assets/$DETECTED.xml"

  local custom_files=(
    "/custom.xml"
    "$STORAGE/custom.xml"
    "/run/assets/custom.xml"
  )

  CUSTOM_XML=""

  removeGeneratedXML "$target" || return 1

  if [ -d "${custom_files[0]}" ]; then
    error "The bind ${custom_files[0]} maps to a file that does not exist!"
    exit 67
  fi

  for file in "${custom_files[@]}"; do
    if [ -f "$file" ] && [ -s "$file" ]; then
      CUSTOM_XML="Y"
      XML="$file"
      return 0
    fi
  done

  file="$1"

  if [[ "${DETECTED,,}" == *"-eval" ]] &&
    { [ ! -f "$file" ] || [ ! -s "$file" ]; }; then

    generateEvalXML "$DETECTED" "$index" || return 1
    file="$target"

  elif [ ! -f "$file" ] || [ ! -s "$file" ]; then

    file="$target"

  elif [[ "$file" != "$target" ]]; then

    generateFallbackXML "$DETECTED" "$index" || return 1
    file="$target"

  fi

  [ -f "$file" ] && [ -s "$file" ] || return 1

  XML="$file"
  return 0
}

updateXML() {

  local asset="$1"
  local language="$2"
  local script="${3:-}"
  local domain="${DOMAIN:-}"
  local workgroup="${WORKGROUP:-}"
  local account=""
  local auth=""

  [ -z "${WIDTH:-}" ] && WIDTH="1280"
  [ -z "${HEIGHT:-}" ] && HEIGHT="720"

  validateXMLSettings || return 1
  updateDisplayXML "$asset" || return 1
  updateLocaleXML "$asset" "$language" || return 1

  if [ -n "$domain" ]; then
    prepareDomainAccount "$domain" account auth || return 1
  else
    updateLocalAccountXML "$asset" "$script" || return 1
  fi

  sed -i -E \
    "s|<PlainText>[^<]*</PlainText>|<PlainText>false</PlainText>|g" \
    "$asset" || return 1

  updateMembershipXML \
    "$asset" \
    "$domain" \
    "$workgroup" \
    "$account" \
    "$auth" \
    "$script" || return 1

  updateAutologinXML "$asset" || return 1
  enableLog "$asset" "$script" || return 1
  updateEditionXML "$asset" || return 1
  updateProductKey "$script" || return 1
  removeSharedFolderXML "$asset" "$script" || return 1
  finalizeSetupScript "$script" || return 1
  validateGeneratedXML "$asset" || return 1

  return 0
}

validateGeneratedXML() {

  local asset="$1"

  if ! xmllint --nonet --noout "$asset"; then
    error "The generated answer file is not valid XML!"
    return 1
  fi

  return 0
}

validateXMLSettings() {

  validateResolution "WIDTH" "$WIDTH" 320 || return 1
  validateResolution "HEIGHT" "$HEIGHT" 200 || return 1
  validateMembership || return 1
  validateComputerName "${HOST:-}" || return 1
  validateProductKey "${KEY:-}" || return 1
  validatePassword "${PASSWORD:-}" || return 1

  return 0
}

validateResolution() {

  local name="$1"
  local value="$2"
  local minimum="$3"

  if [[ ! "$value" =~ ^[0-9]+$ ]] || [ "${#value}" -gt 5 ]; then
    error "The $name variable must be between $minimum and 16384!"
    return 1
  fi

  local number=$((10#$value))

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
  local safe

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

validateUsername() {

  local value="$1"
  local type="$2"
  local maximum length_suffix invalid_message

  case "$type" in
    "local" )
      [ -z "$value" ] && return 0

      maximum=20
      length_suffix=""
      invalid_message="The USERNAME variable contains characters that are not supported by Windows local accounts!"
      ;;

    "domain" )
      if [ -z "$value" ]; then
        error "The USERNAME variable does not contain a valid domain account name!"
        return 1
      fi

      maximum=256
      length_suffix=" for a domain account"
      invalid_message="The domain account name contains characters that are not supported by Windows unattended setup!"
      ;;

    * )
      return 1
      ;;
  esac

  if [ "${#value}" -gt "$maximum" ]; then
    error "The USERNAME variable cannot contain more than $maximum characters$length_suffix!"
    return 1
  fi

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    error "The USERNAME variable cannot contain control characters!"
    return 1
  fi

  case "$value" in
    *'"'* | *'/'* | *\\* | *'['* | *']'* | *':'* | *';'* | *'|'* | *'='* | *','* | *'+'* | *'*'* | *'?'* | *'<'* | *'>'* | *'%'* | *'@'* )
      error "$invalid_message"
      return 1
      ;;
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
      return 1
      ;;

    "ADMINISTRATOR" | "GUEST" | "DEFAULTACCOUNT" | "WDAGUTILITYACCOUNT" | "WSIACCOUNT" )
      [[ "$type" == "domain" ]] && return 0

      error "The USERNAME value \"$value\" is reserved for a built-in Windows account!"
      return 1
      ;;
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

updateWorkgroup() {

  local asset="$1"
  local workgroup arch tmp

  workgroup=$(escapeXML "$2") || return 1
  arch=$(getXMLArchitecture "$asset") || return 1

  grep -q 'Microsoft-Windows-UnattendedJoin' "$asset" && return 1

  tmp=$(mktemp -d) || return 1
  local result="$tmp/answer.xml"

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

updateDomain() {

  local asset="$1"
  local domain account auth pass
  local ou arch tmp

  domain=$(escapeXML "$2") || return 1
  account=$(escapeXML "$3") || return 1
  auth=$(escapeXML "$4") || return 1
  pass=$(escapeXML "$5") || return 1
  ou=$(escapeXML "$6") || return 1
  arch=$(getXMLArchitecture "$asset") || return 1

  local cred_domain="$domain"

  case "$4" in
    *@* ) cred_domain="" ;;
  esac

  grep -Eq 'Microsoft-Windows-UnattendedJoin|<DomainAccounts([[:space:]/>])' "$asset" && return 1

  tmp=$(mktemp -d) || return 1
  local result="$tmp/answer.xml"

  if ! DOMAIN_XML="$domain" ACCOUNT_XML="$account" \
    AUTH_XML="$auth" PASS_XML="$pass" \
    CRED_DOMAIN="$cred_domain" OU_XML="$ou" \
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
        print "          <Value>" ENVIRON["PASS_XML"] "</Value>"
        password_added = 1
        next
      }

      section == "oobeSystem" && in_autologon &&
        /^[[:space:]]*<PlainText([[:space:]/>])/ {
        print "          <PlainText>true</PlainText>"
        plaintext_added = 1
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

      END { exit !(join_added && accounts_added && autologon_added && password_added && plaintext_added) }
    ' "$asset" > "$result" ||
    ! mv -f "$result" "$asset"; then

    rm -rf "$tmp" || true
    return 1
  fi

  rm -rf "$tmp" || return 1
  return 0
}

prepareDomainAccount() {

  local domain="$1"
  local -n account_ref="$2"
  local -n auth_ref="$3"
  local qualifier=""

  auth_ref="${USERNAME:-}"
  account_ref=""

  if [ -z "$auth_ref" ]; then
    error "The USERNAME variable must be specified when joining a domain!"
    return 1
  fi

  if [ -z "${PASSWORD:-}" ]; then
    error "The PASSWORD variable must be specified when joining a domain!"
    return 1
  fi

  validateDomainName "$domain" || return 1

  if [[ "$auth_ref" == *\\* ]]; then
    error "The USERNAME variable must use either \"user\" or \"user@domain\" format!"
    return 1
  fi

  case "$auth_ref" in
    *@* )
      account_ref="${auth_ref%%@*}"
      qualifier="${auth_ref#*@}"

      if [ -z "$account_ref" ] ||
        [ -z "$qualifier" ] ||
        [[ "$qualifier" == *@* ]]; then

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
      account_ref="$auth_ref"
      ;;
  esac

  validateUsername "$account_ref" "domain" || return 1

  if [[ "${account_ref,,}" == "docker" ]]; then
    error "The USERNAME variable must be changed from its default value when joining a domain!"
    return 1
  fi

  if [[ "$PASSWORD" == "admin" ]]; then
    error "The PASSWORD variable must be changed from its default value when joining a domain!"
    return 1
  fi

  return 0
}

updateDisplayXML() {

  local asset="$1"
  local app host

  app=$(escapeXMLSed "$APP for $ENGINE") || return 1

  sed -i "s|>Windows for Docker<|>$app<|g" "$asset" || return 1
  sed -i -E "s|<VerticalResolution>[^<]*</VerticalResolution>|<VerticalResolution>$HEIGHT</VerticalResolution>|g" "$asset" || return 1
  sed -i -E "s|<HorizontalResolution>[^<]*</HorizontalResolution>|<HorizontalResolution>$WIDTH</HorizontalResolution>|g" "$asset" || return 1

  [ -n "${HOST:-}" ] || return 0

  host=$(escapeXMLSed "$HOST") || return 1
  sed -i -E "s|<ComputerName>[^<]*</ComputerName>|<ComputerName>$host</ComputerName>|g" "$asset" || return 1

  return 0
}

updateLocaleXML() {

  local asset="$1"
  local language="$2"
  local culture region keyboard value

  culture=$(getLanguage "$language" "culture") || return 1

  if [ -n "$culture" ] && [[ "${culture,,}" != "en-us" ]]; then
    value=$(escapeXMLSed "$culture") || return 1
    sed -i "s|<UILanguage>en-US</UILanguage>|<UILanguage>$value</UILanguage>|g" "$asset" || return 1
  fi

  region="${REGION:-$culture}"

  if [ -n "$region" ] && [[ "${region,,}" != "en-us" ]]; then
    value=$(escapeXMLSed "$region") || return 1
    sed -i "s|<UserLocale>en-US</UserLocale>|<UserLocale>$value</UserLocale>|g" "$asset" || return 1
    sed -i "s|<SystemLocale>en-US</SystemLocale>|<SystemLocale>$value</SystemLocale>|g" "$asset" || return 1
  fi

  keyboard="${KEYBOARD:-$culture}"

  if [ -n "$keyboard" ] && [[ "${keyboard,,}" != "en-us" ]]; then
    value=$(escapeXMLSed "$keyboard") || return 1
    sed -i "s|<InputLocale>en-US</InputLocale>|<InputLocale>$value</InputLocale>|g" "$asset" || return 1
    sed -i "s|<InputLocale>0409:00000409</InputLocale>|<InputLocale>$value</InputLocale>|g" "$asset" || return 1
  fi

  return 0
}

updateLocalAccountXML() {

  local asset="$1"
  local script="${2:-}"
  local user="${USERNAME:-}"
  local pass="${PASSWORD:-admin}"
  local user_xml pw admin

  validateUsername "$user" "local" || return 1

  if [ -n "$user" ]; then
    user_xml=$(escapeXMLSed "$user") || return 1
    if [ -n "$script" ]; then
      updateSetupVariable "$script" "LOCAL_ACCOUNT" "LOCAL_USER" "$user" || return 1
    else
      sed -i "s|-name \"Docker\"|-name \"\$env:USERNAME\"|g" "$asset" || return 1
      sed -i 's|where name="Docker"|where name="%USERNAME%"|g' "$asset" || return 1
    fi
    sed -i "s|<Name>Docker</Name>|<Name>$user_xml</Name>|g" "$asset" || return 1
    sed -i "s|<FullName>Docker</FullName>|<FullName>$user_xml</FullName>|g" "$asset" || return 1
    sed -i "s|<Username>Docker</Username>|<Username>$user_xml</Username>|g" "$asset" || return 1
  fi

  pw=$(printf '%s' "${pass}Password" |
    iconv -f utf-8 -t utf-16le |
    base64 -w 0) || return 1

  admin=$(printf '%s' "${pass}AdministratorPassword" |
    iconv -f utf-8 -t utf-16le |
    base64 -w 0) || return 1

  sed -i -z -E \
    "s#(<Password>[[:space:]]*<Value)([[:space:]]*/>|>[^<]*</Value>)#\1>$pw</Value>#g" \
    "$asset" || return 1

  sed -i -z -E \
    "s#(<AdministratorPassword>[[:space:]]*<Value)([[:space:]]*/>|>[^<]*</Value>)#\1>$admin</Value>#g" \
    "$asset" || return 1

  return 0
}

updateMembershipXML() {

  local asset="$1"
  local domain="$2"
  local workgroup="$3"
  local account="$4"
  local auth="$5"
  local script="${6:-}"

  if [ -n "$domain" ]; then

    if ! updateDomain \
      "$asset" \
      "$domain" \
      "$account" \
      "$auth" \
      "$PASSWORD" \
      "${DOMAIN_OU:-}"; then

      warn "failed to add domain configuration to answer file!"
      return 0
    fi

    removeLocalAccountXML "$asset" "$script" || return 1
    return 0
  fi

  [ -n "$workgroup" ] || return 0

  if ! updateWorkgroup "$asset" "$workgroup"; then
    warn "failed to add workgroup configuration to answer file!"
  fi

  return 0
}

updateAutologinXML() {

  local asset="$1"

  disabled "${AUTOLOGIN:-}" || return 0

  sed -i -E \
    '/^[[:space:]]*<AutoLogon([[:space:]>])/,/^[[:space:]]*<\/AutoLogon>[[:space:]]*$/d' \
    "$asset" || return 1

  return 0
}

updateEditionXML() {

  local asset="$1"
  local edition

  [ -n "${EDITION:-}" ] || return 0

  edition=$(normalizeServerEdition "$EDITION") || return 1
  edition="${edition//-/}"
  edition="${edition^^}"
  edition=$(escapeXMLSed "$edition") || return 1

  sed -i \
    "s|SERVERSTANDARD</Value>|SERVER$edition</Value>|g" \
    "$asset" || return 1

  return 0
}

updateProductKey() {

  local script="$1"

  if [ -n "$script" ]; then
    updateSetupVariable "$script" "PRODUCT_KEY" "PRODUCT_KEY" "${KEY:-}" || return 1
    return 0
  fi

  # Product-key migration for the remaining XML-only templates is handled
  # when each template receives its own setup script.
  return 0
}

updateDiskID() {

  local asset="$1"
  local disk_type="${2,,}"

  case "$disk_type" in
    "" | "scsi" | "virtio-scsi" | "blk" | "virtio-blk" ) ;;
    * ) return 0 ;;
  esac

  [ -s "$asset" ] || return 1

  # Only adjust files that explicitly target Disk 0.
  grep -Fq '<DiskID>0</DiskID>' "$asset" || return 0

  # Leave multi-disk configurations untouched.
  if grep -Eq '<DiskID>[[:space:]]*[1-9][0-9]*[[:space:]]*</DiskID>' "$asset"; then
    return 0
  fi

  sed -i 's#<DiskID>0</DiskID>#<DiskID>1</DiskID>#g' "$asset" || return 1

  return 0
}

getXMLArchitecture() {

  local asset="$1"
  local arch

  arch=$(sed -n -E \
    '0,/processorArchitecture="/s/.*processorArchitecture="([^"]+)".*/\1/p' \
    "$asset") || return 1

  [ -n "$arch" ] || return 1

  printf '%s' "$arch"
  return 0
}

setConfigurationXML() {

  local asset="$1"
  local section

  [ -s "$asset" ] || return 1

  section=$(sed -n -E '
    /<settings[^>]*pass="windowsPE"[^>]*>/,/<\/settings>/ {
      /<component[^>]*name="Microsoft-Windows-Setup"[^>]*>/,/<\/component>/p
    }
  ' "$asset") || return 1

  [ -n "$section" ] || return 1

  if grep -Fq '<UseConfigurationSet>' <<< "$section"; then

    sed -i -E '
      /<settings[^>]*pass="windowsPE"[^>]*>/,/<\/settings>/ {
        /<component[^>]*name="Microsoft-Windows-Setup"[^>]*>/,/<\/component>/ {
          s#<UseConfigurationSet>[^<]*</UseConfigurationSet>#<UseConfigurationSet>true</UseConfigurationSet>#g
        }
      }
    ' "$asset" || return 1

    return 0
  fi

  if ! grep -Fq '<UserData>' <<< "$section"; then
    return 1
  fi

  sed -i -E '
    /<settings[^>]*pass="windowsPE"[^>]*>/,/<\/settings>/ {
      /<component[^>]*name="Microsoft-Windows-Setup"[^>]*>/,/<\/component>/ {
        s#^([[:space:]]*)<UserData>#\1<UseConfigurationSet>true</UseConfigurationSet>\n\1<UserData>#
      }
    }
  ' "$asset" || return 1

  return 0
}

removeSharedFolderXML() {

  local asset="$1"
  local script="${2:-}"

  if ! disabled "${SHORTCUT:-}" &&
    ! disabled "${SAMBA:-}"; then
    return 0
  fi

  if [ -n "$script" ]; then
    removeSetupBlock "$script" "SHARED_FOLDER" || return 1
    return 0
  fi

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

  return 0
}

removeLocalAccountXML() {

  local asset="$1"
  local script="${2:-}"

  if ! sed -i -E \
    -e '/^[[:space:]]*<LocalAccounts([[:space:]>])/,/^[[:space:]]*<\/LocalAccounts>[[:space:]]*$/d' \
    -e '/^[[:space:]]*<AdministratorPassword([[:space:]>])/,/^[[:space:]]*<\/AdministratorPassword>[[:space:]]*$/d' \
    "$asset"; then

    error "Failed to remove local account configuration from answer file!"
    return 1
  fi

  if [ -n "$script" ]; then
    removeSetupBlock "$script" "LOCAL_ACCOUNT" || return 1
    return 0
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

  return 0
}

enableLog() {

  local file="$1"
  local script="${2:-}"
  local old='C:\OEM\install.bat"</CommandLine>'
  local msg="failed to enable install logging in the answer file!"

  enabled "${LOG:-}" || return 0

  if [ -n "$script" ]; then
    updateSetupVariable \
      "$script" \
      "OEM_SCRIPT" \
      "OEM_REDIRECT" \
      " > C:\OEM\install.log 2>&1" || return 1

    return 0
  fi

  [ -f "$file" ] || return 1

  if ! grep -Fq "$old" "$file"; then
    enabled "$DEBUG" && warn "$msg"
    return 0
  fi

  if ! sed -i \
    's|C:\\OEM\\install\.bat"</CommandLine>|C:\\OEM\\install.bat \&gt; C:\\OEM\\install.log 2\&gt;\&amp;1"</CommandLine>|' \
    "$file"; then

    warn "$msg"
  fi

  return 0
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
    *'"'* | *'/'* | *\\* | *'['* | *']'* | *':'* | *';'* | *'|'* | *'='* | \
    *','* | *'+'* | *'*'* | *'?'* | *'<'* | *'>'* | *'%'* )
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

  case "${value^^}" in
    "NONE" )
      error "The USERNAME value \"NONE\" is reserved by Windows$suffix!"
      return 1 ;;
    "ADMINISTRATOR" | "GUEST" | "DEFAULTACCOUNT" | "WDAGUTILITYACCOUNT" | "WSIACCOUNT" )
      error "The USERNAME value \"$value\" is reserved for a built-in Windows account$suffix!"
      return 1 ;;
  esac

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

extractDrivers() {

  local drivers="$1"

  rm -rf "$drivers" || return 1
  mkdir -p "$drivers" || return 1

  if ! bsdtar -xf /var/drivers.txz -C "$drivers"; then
    error "Failed to extract drivers!"
    return 1
  fi

  return 0
}

copyStorageDriver() {

  local dir="$1"
  local target="$2"
  local driver="$3"
  local arch="$4"
  local drivers="$5"
  local destination="$dir/\$OEM\$/\$1/Drivers/viostor"

  if [ ! -f "$drivers/viostor/$driver/$arch/viostor.sys" ]; then
    error "Failed to locate required storage drivers!"
    return 1
  fi

  cp -L "$drivers/viostor/$driver/$arch/viostor.sys" "$target" || return 1

  mkdir -p "$destination" || return 1
  cp -L "$drivers/viostor/$driver/$arch/viostor.cat" "$destination" || return 1
  cp -L "$drivers/viostor/$driver/$arch/viostor.inf" "$destination" || return 1
  cp -L "$drivers/viostor/$driver/$arch/viostor.sys" "$destination" || return 1

  return 0
}

addNetworkDriver() {

  local dir="$1"
  local driver="$2"
  local arch="$3"
  local drivers="$4"
  local destination="$dir/\$OEM\$/\$1/Drivers/NetKVM"

  if [ ! -f "$drivers/NetKVM/$driver/$arch/netkvm.sys" ]; then
    error "Failed to locate required network drivers!"
    return 1
  fi

  mkdir -p "$destination" || return 1
  cp -L "$drivers/NetKVM/$driver/$arch/netkvm.cat" "$destination" || return 1
  cp -L "$drivers/NetKVM/$driver/$arch/netkvm.inf" "$destination" || return 1
  cp -L "$drivers/NetKVM/$driver/$arch/netkvm.sys" "$destination" || return 1

  return 0
}

patchStorageDriver() {

  local file="$1"
  local arch="$2"

  sed -i '/^\[SCSI.Load\]/s/$/\nviostor=viostor.sys,4/' "$file" || return 1
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\nviostor.sys=1,,,,,,4_,4,1,,,1,4/' "$file" || return 1
  sed -i '/^\[SCSI\]/s/$/\nviostor=\"Red Hat VirtIO SCSI Disk Device\"/' "$file" || return 1
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00000000=\"viostor\"/' "$file" || return 1
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00020000=\"viostor\"/' "$file" || return 1
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00021AF4=\"viostor\"/' "$file" || return 1

  return 0
}

addSataDriver() {

  local dir="$1"
  local target="$2"
  local arch="$3"
  local drivers="$4"
  local file="$5"
  local destination="$dir/\$OEM\$/\$1/Drivers/sata"

  if [ ! -d "$drivers/sata/xp/$arch" ]; then
    error "Failed to locate required SATA drivers!"
    return 1
  fi

  mkdir -p "$destination" || return 1
  cp -Lr "$drivers/sata/xp/$arch/." "$destination" || return 1
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

  return 0
}

addLegacyDrivers() {

  local dir="$1"
  local target="$2"
  local driver="$3"
  local arch="$4"
  local drivers="$5"
  local file
  local msg="Adding drivers to image..."

  info "$msg" && html "$msg"

  extractDrivers "$drivers" || return 1
  copyStorageDriver "$dir" "$target" "$driver" "$arch" "$drivers" || return 1
  addNetworkDriver "$dir" "$driver" "$arch" "$drivers" || return 1

  file=$(find "$target" -maxdepth 1 -type f -iname TXTSETUP.SIF -print -quit) || return 1

  if [ -z "$file" ]; then
    error "The file TXTSETUP.SIF could not be found!"
    return 1
  fi

  patchStorageDriver "$file" "$arch" || return 1
  addSataDriver "$dir" "$target" "$arch" "$drivers" "$file" || return 1

  rm -rf "$drivers" || return 1

  return 0
}

setLegacyKey() {

  local target="$1"
  local driver="$2"
  local arch="$3"
  local desc="$4"
  local setup pid key file

  setup=$(find "$target" -maxdepth 1 -type f -iname setupp.ini -print -quit) || return 1

  [[ -n "$setup" ]] || return 0
  [[ -z "$KEY" ]] || return 0

  pid=$(<"$setup") || return 1
  pid="${pid%$'\r'}"

  if [[ "$driver" == "2k" ]]; then
    echo "${pid::-3}270" > "$setup" || return 1
    return 0
  fi

  if [[ "$pid" == *"270" ]]; then
    warn "this version of $desc requires a volume license key (VLK), it will ask for one during installation."
    return 0
  fi

  file=$(find "$target" -maxdepth 1 -type f -iname PID.INF -print -quit) || return 1

  if [[ -n "$file" ]]; then

    if [[ "$driver" == "2k3" ]]; then
      key=$(grep -i -A 2 "StagingKey" "$file" | tail -n 2 | head -n 1) || key=""
    else

      key="${pid: -8:5}"

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

  [[ -n "$KEY" ]] && return 0

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

  echo "${pid::-3}000" > "$setup" || return 1

  return 0
}

writeCommand() {

  local install="$1"

  [ -f "$install" ] || return 0

  if enabled "${LOG:-}"; then
    printf '%s' "\"Script\"=\"cmd /C start \\\"Install\\\" \\\"cmd /C C:\\\\OEM\\\\install.bat > C:\\\\OEM\\\\install.log 2>&1\\\"\""
  else
    printf '%s' "\"Script\"=\"cmd /C start \\\"Install\\\" \\\"cmd /C C:\\\\OEM\\\\install.bat\\\"\""
  fi

  return 0
}

writeSIF() {

  local target="$1"
  local driver="$2"
  local product="$3"
  local sifHost="$4"
  local sifUsername="$5"
  local sifPassword="$6"
  local sifOrganization="$7"
  local sifWorkgroup="$8"

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

  return 0
}

writeRegistry() {

  local dir="$1"
  local shortcut="$2"
  local oem="$3"
  local regUsername="$4"
  local regPassword="$5"

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

  return 0
}

appendRegistry() {

  local dir="$1"
  local driver="$2"

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

  return 0
}

writeVBS() {

  local dir="$1"
  local username="$2"
  local shortcut="$3"

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

disableAutoReboot() {

  local target="$1"
  local file

  file=$(find \
    "$target" \
    -maxdepth 1 \
    -type f \
    -iname HIVESYS.INF \
    -print -quit
  ) || return 1

  if [ -z "$file" ]; then
    error "The file HIVESYS.INF could not be found!"
    return 1
  fi

  if grep -Fqi \
    'HKLM,"SYSTEM\CurrentControlSet\Control\CrashControl","AutoReboot"' \
    "$file"; then

    sed -i -E \
      's|^(HKLM,"SYSTEM\\CurrentControlSet\\Control\\CrashControl","AutoReboot",[^,]*,)[^[:space:]]*|\1 0|I' \
      "$file" || return 1

  else

    printf '%s\n' \
      'HKLM,"SYSTEM\CurrentControlSet\Control\CrashControl","AutoReboot",0x00010001,0' |
      unix2dos >> "$file" || return 1

  fi

  return 0
}

legacyInstall() {

  local dir="$2"
  local desc="$3"
  local driver="$4"
  local shortcut="Y"
  local drivers="/tmp/drivers"

  if disabled "$SHORTCUT" || disabled "${SAMBA:-Y}"; then
    shortcut="N"
  fi

  if [ -n "$DOMAIN" ]; then
    error "The DOMAIN variable is not supported for $desc!"
    return 1
  fi

  ETFS="[BOOT]/Boot-NoEmul.img"

  if [ ! -f "$dir/$ETFS" ] || [ ! -s "$dir/$ETFS" ]; then
    error "Failed to locate file \"$ETFS\" in $desc ISO image!"
    return 1
  fi

  local arch="amd64"
  [ ! -d "$dir/AMD64" ] && arch="x86"

  local target="$dir/AMD64"
  [[ "${arch,,}" == "x86" ]] && target="$dir/I386"

  if [ ! -d "$target" ]; then
    error "Failed to locate directory \"$target\" in $desc ISO image!"
    return 1
  fi

  if [[ "${driver,,}" == "xp" || "${driver,,}" == "2k3" ]]; then
    addLegacyDrivers "$dir" "$target" "$driver" "$arch" "$drivers" || return 1
  fi

  disableAutoReboot "$target" || return 1
  setLegacyKey "$target" "$driver" "$arch" "$desc" || return 1
  validateProductKey "$KEY" || return 1

  local product=""
  [ -n "$KEY" ] && product="ProductID=$KEY"

  mkdir -p "$dir/\$OEM\$" || return 1

  if ! addFolder "$dir"; then
    error "Failed to add OEM folder to image!"
    return 1
  fi

  local oem=""
  local install=""
  local oem_dir="$dir/\$OEM\$/\$1/OEM"

  if [ -d "$oem_dir" ]; then
    install=$(find \
      "$oem_dir" \
      -maxdepth 1 \
      -type f \
      -iname install.bat \
      -print -quit
    ) || return 1
  fi

  oem=$(writeCommand "$install") || return 1

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

  writeSIF \
    "$target" \
    "$driver" \
    "$product" \
    "$sifHost" \
    "$sifUsername" \
    "$sifPassword" \
    "$sifOrganization" \
    "$sifWorkgroup" || return 1

  writeRegistry \
    "$dir" \
    "$shortcut" \
    "$oem" \
    "$regUsername" \
    "$regPassword" || return 1

  appendRegistry "$dir" "$driver" || return 1
  writeVBS "$dir" "$username" "$shortcut" || return 1

  return 0
}

return 0
