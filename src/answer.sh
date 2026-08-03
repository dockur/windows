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

  removeGeneratedXML "$asset" || return 1

  if [ -z "${CUSTOM_XML:-}" ]; then
    if ! updateXML "$answer" "$language"; then
      error "Failed to update answer file: $answer"
      return 1
    fi
  fi

  if ! updateDiskID "$answer" "${DISK_TYPE:-}" "setup"; then
    error "Failed to adjust the Windows installation disk!"
    exit 85
  fi

  if ! setConfigurationXML "$answer"; then
    error "Failed to enable the Windows configuration set!"
    return 1
  fi

  validateGeneratedXML "$answer" || return 1

  if [ -z "${CUSTOM_XML:-}" ]; then
    prepareSetupScript "$asset" "$stage" script || exit 84
  fi

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
  local ns="urn:schemas-microsoft-com:unattend"
  local wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
  local setup='/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]'
  local os_image="$setup/u:ImageInstall/u:OSImage"
  local install_from="$os_image/u:InstallFrom"
  local install_to="$os_image/u:InstallTo"
  local directory install_count install_to_count tmp

  if [ -n "$index" ] && [[ ! "$index" =~ ^[1-9][0-9]*$ ]]; then
    error "Invalid $type image index: $index"
    return 1
  fi

  directory=$(dirname "$target") || return 1

  if ! tmp=$(mktemp -p "$directory" ".${id}.XXXXXX"); then
    error "Failed to create a temporary $type answer file!"
    return 1
  fi

  if ! cp -L -- "$source" "$tmp"; then
    rm -f "$tmp"
    error "Failed to generate $type answer file from $source!"
    return 1
  fi

  local -a args=(
    -L
    -N "u=$ns"
    # Product keys can appear in more than one unattend component.
    # Generated fallback and evaluation files must not retain any of them.
    -d '//u:ProductKey'
  )

  if [ "$type" != "evaluation" ] || [ "$remove_selector" = "Y" ]; then
    args+=( -d "$install_from" )
  fi

  if ! xmlstarlet ed "${args[@]}" "$tmp"; then
    rm -f "$tmp"
    error "Failed to generate $type answer file from $source!"
    return 1
  fi

  if [ -n "$index" ]; then
    install_count=$(xmlstarlet sel \
      -N "u=$ns" \
      -T -t \
      -v "count($install_from)" \
      "$tmp") || {
      rm -f "$tmp"
      return 1
    }

    if (( install_count > 1 )); then
      rm -f "$tmp"
      error "Multiple $type image selectors were found!"
      return 1
    fi

    if [ "$install_count" = "0" ]; then
      install_to_count=$(xmlstarlet sel \
        -N "u=$ns" \
        -T -t \
        -v "count($install_to)" \
        "$tmp") || {
        rm -f "$tmp"
        return 1
      }

      if [ "$install_to_count" != "1" ]; then
        rm -f "$tmp"
        error "Failed to find a unique $type installation target!"
        return 1
      fi

      if ! xmlstarlet ed -L \
        -N "u=$ns" \
        -N "wcm=$wcm" \
        -i "($install_to)[1]" \
          -t elem -n 'InstallFrom' \
        -s "$os_image/*[local-name()='InstallFrom']" \
          -t elem -n 'MetaData' \
        -i "$os_image/*[local-name()='InstallFrom']/*[local-name()='MetaData']" \
          -t attr -n 'wcm:action' -v 'add' \
        -s "$os_image/*[local-name()='InstallFrom']/*[local-name()='MetaData']" \
          -t elem -n 'Key' -v '/IMAGE/INDEX' \
        -s "$os_image/*[local-name()='InstallFrom']/*[local-name()='MetaData']" \
          -t elem -n 'Value' -v "$index" \
        "$tmp"; then

        rm -f "$tmp"
        error "Failed to select $type image index $index!"
        return 1
      fi
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
    updateLocalAccount "$asset" || return 1
  fi


  updateMembership \
    "$asset" \
    "$domain" \
    "$workgroup" \
    "$account" \
    "$auth" || return 1

  updateAutologinXML "$asset" || return 1
  updateEditionXML "$asset" || return 1
  validateGeneratedXML "$asset" || return 1

  return 0
}

prepareSetupScript() {

  local asset="$1"
  local stage="$2"
  local result_name="$3"
  local staged=""

  printf -v "$result_name" '%s' ""

  stageSetupScript "$asset" "$stage" staged || return 1
  [ -n "$staged" ] || return 0

  updateSetupScript "$staged" "$asset" || return 1
  finalizeSetupScript "$staged" || return 1

  printf -v "$result_name" '%s' "$staged"
  return 0
}

updateSetupScript() {

  local script="$1"
  local asset="$2"
  local domain="${DOMAIN:-}"
  local user="${USERNAME:-}"
  local content id

  if [ ! -s "$script" ]; then
    error "Failed to find staged setup script: $script"
    return 1
  fi

  if [ -n "$domain" ]; then
    removeSetupBlock "$script" "LOCAL_ACCOUNT" || return 1
  elif [ -n "$user" ]; then
    validateUsername "$user" "local" || return 1

    id=$(basename "$asset") || return 1
    id="${id%.*}"

    case "${id,,}" in
      "win10"* | "win11"* | \
      "win2016"* | "win2019"* | "win2022"* | "win2025"* )
        printf -v content '%s\n%s' \
          'rem Prevent the local user password from expiring.' \
          "powershell.exe -ExecutionPolicy Unrestricted -NoLogo -NoProfile -NonInteractive Set-LocalUser -Name \"$user\" -PasswordNeverExpires 1"
        ;;
      * )
        printf -v content '%s\n%s' \
          'rem Prevent the local user password from expiring.' \
          "wmic useraccount where name=\"$user\" set PasswordExpires=false"
        ;;
    esac

    replaceSetupBlock "$script" "LOCAL_ACCOUNT" "$content" || return 1
  fi

  enableLog "$script" || return 1
  updateProductKey "$script" || return 1
  removeSharedFolder "$script" || return 1

  return 0
}

findSetupScript() {

  local asset="$1"
  local dir name id normal candidate
  local candidates=()

  [ -z "${CUSTOM_XML:-}" ] || return 0
  [ -n "$asset" ] || return 1

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
  if ! sed -i 's/\r$//' "$target"; then
    error "Failed to normalize setup script: $target"
    return 1
  fi

  validateSetupScript "$target" || return 1

  printf -v "$result_name" '%s' "$target"
  return 0
}

installSetupScript() {

  local script="$1"
  local root="$2"
  local target

  [ -n "$script" ] || return 0

  if [ ! -s "$script" ]; then
    error "Failed to find staged setup script: $script"
    return 1
  fi

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

replaceSetupBlock() {

  local file="$1"
  local block="$2"
  local content="$3"
  local begin="rem BEGIN $block"
  local end="rem END $block"
  local line inside=0 tmp

  validateSetupBlock "$file" "$block" || return 1

  if ! tmp=$(mktemp "${file}.XXXXXX"); then
    error "Failed to create temporary setup script!"
    return 1
  fi

  while IFS= read -r line || [ -n "$line" ]; do

    if [ "$line" = "$begin" ]; then
      if ! printf '%s\n' "$line" >> "$tmp" ||
        ! printf '%s\n' "$content" >> "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
      inside=1
      continue
    fi

    if [ "$line" = "$end" ]; then
      inside=0
      if ! printf '%s\n' "$line" >> "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
      continue
    fi

    if (( ! inside )); then
      if ! printf '%s\n' "$line" >> "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
    fi

  done < "$file"

  if ! chmod --reference="$file" "$tmp" ||
    ! mv -f -- "$tmp" "$file"; then
    rm -f "$tmp"
    error "Failed to replace the $block block in setup script: $file"
    return 1
  fi

  return 0
}

removeSetupBlock() {

  local file="$1"
  local block="$2"
  local begin="rem BEGIN $block"
  local end="rem END $block"
  local line inside=0 tmp

  validateSetupBlock "$file" "$block" || return 1

  if ! tmp=$(mktemp "${file}.XXXXXX"); then
    error "Failed to create temporary setup script!"
    return 1
  fi

  while IFS= read -r line || [ -n "$line" ]; do

    if [ "$line" = "$begin" ]; then
      inside=1
      continue
    fi

    if [ "$line" = "$end" ]; then
      inside=0
      continue
    fi

    if (( ! inside )); then
      if ! printf '%s\n' "$line" >> "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
    fi

  done < "$file"

  if ! chmod --reference="$file" "$tmp" ||
    ! mv -f -- "$tmp" "$file"; then
    rm -f "$tmp"
    error "Failed to remove the $block block from setup script: $file"
    return 1
  fi

  return 0
}

finalizeSetupScript() {

  local file="$1"

  [ -n "$file" ] || return 0
  if [ ! -s "$file" ]; then
    error "Failed to find staged setup script: $file"
    return 1
  fi

  if ! unix2dos -q "$file"; then
    error "Failed to convert setup script to DOS format: $file"
    return 1
  fi

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

validateSetupScript() {

  local file="$1"
  local block
  local blocks=(
    LOCAL_ACCOUNT
    PRODUCT_KEY
    SHARED_FOLDER
    OEM_SCRIPT
  )

  [ -s "$file" ] || return 1

  for block in "${blocks[@]}"; do
    validateSetupBlock "$file" "$block" || return 1
  done

  return 0
}

validateSetupBlock() {

  local file="$1"
  local block="$2"
  local begin="rem BEGIN $block"
  local end="rem END $block"
  local begin_count end_count begin_line end_line

  [ -s "$file" ] || return 1

  begin_count=$(grep -Fxc -- "$begin" "$file" || true)
  end_count=$(grep -Fxc -- "$end" "$file" || true)

  if [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
    error "Invalid $block markers in setup script: $file"
    return 1
  fi

  begin_line=$(grep -nFx -- "$begin" "$file" | cut -d: -f1) || return 1
  end_line=$(grep -nFx -- "$end" "$file" | cut -d: -f1) || return 1

  if [ "$begin_line" -ge "$end_line" ]; then
    error "Invalid $block marker order in setup script: $file"
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
  local workgroup="$2"
  local ns="urn:schemas-microsoft-com:unattend"
  local specialize='/u:unattend/u:settings[@pass="specialize"]'
  local component="$specialize/u:component[@name='Microsoft-Windows-UnattendedJoin']"
  local identification="$component/u:Identification"
  local arch counts settings_count join_count identification_count tmp

  arch=$(getXMLArchitecture "$asset") || return 1

  counts=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -v "count($specialize)" -o '|' \
    -v "count($component)" \
    "$asset") || return 1

  IFS='|' read -r settings_count join_count <<< "$counts"

  [ "$settings_count" = "1" ] || return 1
  (( join_count <= 1 )) || return 1

  if ! tmp=$(mktemp "${asset}.XXXXXX") ||
    ! cp -p -- "$asset" "$tmp"; then

    rm -f "${tmp:-}"
    return 1
  fi

  if [ "$join_count" = "0" ]; then
    if ! xmlstarlet ed -L \
      -N "u=$ns" \
      -s "$specialize" \
        -t elem -n 'component' \
      -i "$specialize/*[local-name()='component' and not(@name)][last()]" \
        -t attr -n 'name' -v 'Microsoft-Windows-UnattendedJoin' \
      "$tmp"; then

      rm -f "$tmp"
      return 1
    fi
  fi

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -i "$component[not(@processorArchitecture)]" \
      -t attr -n 'processorArchitecture' -v "$arch" \
    -u "$component/@processorArchitecture" \
      -v "$arch" \
    -i "$component[not(@publicKeyToken)]" \
      -t attr -n 'publicKeyToken' -v '31bf3856ad364e35' \
    -u "$component/@publicKeyToken" \
      -v '31bf3856ad364e35' \
    -i "$component[not(@language)]" \
      -t attr -n 'language' -v 'neutral' \
    -u "$component/@language" \
      -v 'neutral' \
    -i "$component[not(@versionScope)]" \
      -t attr -n 'versionScope' -v 'nonSxS' \
    -u "$component/@versionScope" \
      -v 'nonSxS' \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  identification_count=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -v "count($identification)" \
    "$tmp") || {
    rm -f "$tmp"
    return 1
  }

  (( identification_count <= 1 )) || {
    rm -f "$tmp"
    return 1
  }

  if [ "$identification_count" = "0" ]; then
    if ! xmlstarlet ed -L \
      -N "u=$ns" \
      -s "$component" \
        -t elem -n 'Identification' \
      "$tmp"; then

      rm -f "$tmp"
      return 1
    fi
  fi

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -d "$identification/u:Credentials | $identification/u:JoinDomain | $identification/u:JoinWorkgroup | $identification/u:MachineObjectOU" \
    -s "$identification" \
      -t elem -n 'JoinWorkgroup' \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -u "$identification/u:JoinWorkgroup" \
      -v "$workgroup" \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  if ! chmod --reference="$asset" "$tmp" ||
    ! mv -f "$tmp" "$asset"; then

    rm -f "$tmp"
    return 1
  fi

  return 0
}

updateDomain() {

  local asset="$1"
  local domain="$2"
  local account="$3"
  local auth="$4"
  local pass="$5"
  local ou="$6"
  local ns="urn:schemas-microsoft-com:unattend"
  local wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
  local specialize='/u:unattend/u:settings[@pass="specialize"]'
  local shell='/u:unattend/u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]'
  local accounts="$shell/u:UserAccounts"
  local administrator="$accounts/u:AdministratorPassword"
  local autologon="$shell/u:AutoLogon"
  local domain_accounts="$accounts/u:DomainAccounts"
  local account_list="$domain_accounts/u:DomainAccountList"
  local domain_account="$account_list/u:DomainAccount"
  local component="$specialize/u:component[@name='Microsoft-Windows-UnattendedJoin']"
  local identification="$component/u:Identification"
  local credentials="$identification/u:Credentials"
  local cred_domain="$domain"
  local arch counts tmp child_count identification_count
  local settings_count join_count shell_count accounts_count
  local administrator_count autologon_count

  arch=$(getXMLArchitecture "$asset") || return 1

  case "$auth" in
    *@* ) cred_domain="" ;;
  esac

  counts=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -v "count($specialize)" -o '|' \
    -v "count($component)" -o '|' \
    -v "count($shell)" -o '|' \
    -v "count($accounts)" -o '|' \
    -v "count($administrator)" -o '|' \
    -v "count($autologon)" \
    "$asset") || return 1

  IFS='|' read -r \
    settings_count join_count shell_count accounts_count \
    administrator_count autologon_count <<< "$counts"

  [ "$settings_count" = "1" ] || return 1
  (( join_count <= 1 )) || return 1
  [ "$shell_count" = "1" ] || return 1
  (( accounts_count <= 1 )) || return 1
  (( administrator_count <= 1 )) || return 1
  (( autologon_count <= 1 )) || return 1

  if ! tmp=$(mktemp "${asset}.XXXXXX") ||
    ! cp -p -- "$asset" "$tmp"; then

    rm -f "${tmp:-}"
    return 1
  fi

  if [ "$accounts_count" = "0" ]; then
    child_count=$(xmlstarlet sel \
      -N "u=$ns" \
      -T -t \
      -v "count($shell/*)" \
      "$tmp") || {
      rm -f "$tmp"
      return 1
    }

    if [ "$child_count" = "0" ]; then
      xmlstarlet ed -L \
        -N "u=$ns" \
        -s "$shell" \
          -t elem -n 'UserAccounts' \
        "$tmp" || {
        rm -f "$tmp"
        return 1
      }
    else
      xmlstarlet ed -L \
        -N "u=$ns" \
        -i "$shell/*[1]" \
          -t elem -n 'UserAccounts' \
        "$tmp" || {
        rm -f "$tmp"
        return 1
      }
    fi
  fi

  # Replace the domain-account mapping and AutoLogon block as complete
  # project-owned structures. Other UserAccounts settings are preserved until
  # the local-account entries are removed after this function succeeds.
  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -d "$domain_accounts | $autologon" \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  if [ "$administrator_count" = "0" ]; then
    if ! xmlstarlet ed -L \
      -N "u=$ns" \
      -s "$accounts" \
        -t elem -n 'DomainAccounts' \
      "$tmp"; then

      rm -f "$tmp"
      return 1
    fi
  else
    if ! xmlstarlet ed -L \
      -N "u=$ns" \
      -i "($administrator)[1]" \
        -t elem -n 'DomainAccounts' \
      "$tmp"; then

      rm -f "$tmp"
      return 1
    fi
  fi

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -N "wcm=$wcm" \
    -s "$domain_accounts" \
      -t elem -n 'DomainAccountList' \
    -i "$domain_accounts/*[local-name()='DomainAccountList']" \
      -t attr -n 'wcm:action' -v 'add' \
    -s "$domain_accounts/*[local-name()='DomainAccountList']" \
      -t elem -n 'DomainAccount' \
    -i "$domain_accounts/*[local-name()='DomainAccountList']/*[local-name()='DomainAccount']" \
      -t attr -n 'wcm:action' -v 'add' \
    -s "$domain_accounts/*[local-name()='DomainAccountList']/*[local-name()='DomainAccount']" \
      -t elem -n 'Name' \
    -s "$domain_accounts/*[local-name()='DomainAccountList']/*[local-name()='DomainAccount']" \
      -t elem -n 'Group' -v 'Administrators' \
    -s "$domain_accounts/*[local-name()='DomainAccountList']" \
      -t elem -n 'Domain' \
    -a "$accounts" \
      -t elem -n 'AutoLogon' \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -s "$autologon" \
      -t elem -n 'Username' \
    -s "$autologon" \
      -t elem -n 'Domain' \
    -s "$autologon" \
      -t elem -n 'Enabled' -v 'true' \
    -s "$autologon" \
      -t elem -n 'LogonCount' -v '65432' \
    -s "$autologon" \
      -t elem -n 'Password' \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -s "$autologon/u:Password" \
      -t elem -n 'Value' \
    -s "$autologon/u:Password" \
      -t elem -n 'PlainText' -v 'true' \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -u "$domain_account/u:Name" \
      -v "$account" \
    -u "$account_list/u:Domain" \
      -v "$domain" \
    -u "$autologon/u:Username" \
      -v "$account" \
    -u "$autologon/u:Domain" \
      -v "$domain" \
    -u "$autologon/u:Password/u:Value" \
      -v "$pass" \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  if [ "$join_count" = "0" ]; then
    if ! xmlstarlet ed -L \
      -N "u=$ns" \
      -s "$specialize" \
        -t elem -n 'component' \
      -i "$specialize/*[local-name()='component' and not(@name)][last()]" \
        -t attr -n 'name' -v 'Microsoft-Windows-UnattendedJoin' \
      "$tmp"; then

      rm -f "$tmp"
      return 1
    fi
  fi

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -i "$component[not(@processorArchitecture)]" \
      -t attr -n 'processorArchitecture' -v "$arch" \
    -u "$component/@processorArchitecture" \
      -v "$arch" \
    -i "$component[not(@publicKeyToken)]" \
      -t attr -n 'publicKeyToken' -v '31bf3856ad364e35' \
    -u "$component/@publicKeyToken" \
      -v '31bf3856ad364e35' \
    -i "$component[not(@language)]" \
      -t attr -n 'language' -v 'neutral' \
    -u "$component/@language" \
      -v 'neutral' \
    -i "$component[not(@versionScope)]" \
      -t attr -n 'versionScope' -v 'nonSxS' \
    -u "$component/@versionScope" \
      -v 'nonSxS' \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  identification_count=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -v "count($identification)" \
    "$tmp") || {
    rm -f "$tmp"
    return 1
  }

  (( identification_count <= 1 )) || {
    rm -f "$tmp"
    return 1
  }

  if [ "$identification_count" = "0" ]; then
    if ! xmlstarlet ed -L \
      -N "u=$ns" \
      -s "$component" \
        -t elem -n 'Identification' \
      "$tmp"; then

      rm -f "$tmp"
      return 1
    fi
  fi

  # Replace only settings owned by the requested domain join. Preserve any
  # unrelated Identification settings present in a custom answer file.
  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -d "$identification/u:Credentials | $identification/u:JoinDomain | $identification/u:JoinWorkgroup | $identification/u:MachineObjectOU" \
    -s "$identification" \
      -t elem -n 'Credentials' \
    "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  local -a join_args=( -L -N "u=$ns" )

  if [ -n "$cred_domain" ]; then
    join_args+=(
      -s "$credentials"
        -t elem -n 'Domain'
    )
  fi

  join_args+=(
    -s "$credentials"
      -t elem -n 'Username'
    -s "$credentials"
      -t elem -n 'Password'
    -s "$identification"
      -t elem -n 'JoinDomain'
  )

  if [ -n "$ou" ]; then
    join_args+=(
      -s "$identification"
        -t elem -n 'MachineObjectOU'
    )
  fi

  if ! xmlstarlet ed "${join_args[@]}" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  local -a join_values=(
    -L
    -N "u=$ns"
    -u "$credentials/u:Username"
      -v "$auth"
    -u "$credentials/u:Password"
      -v "$pass"
    -u "$identification/u:JoinDomain"
      -v "$domain"
  )

  if [ -n "$cred_domain" ]; then
    join_values+=(
      -u "$credentials/u:Domain"
        -v "$cred_domain"
    )
  fi

  if [ -n "$ou" ]; then
    join_values+=(
      -u "$identification/u:MachineObjectOU"
        -v "$ou"
    )
  fi

  if ! xmlstarlet ed "${join_values[@]}" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  if ! chmod --reference="$asset" "$tmp" ||
    ! mv -f "$tmp" "$asset"; then

    rm -f "$tmp"
    return 1
  fi

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
  local ns="urn:schemas-microsoft-com:unattend"
  local setup='/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]'
  local specialize='/u:unattend/u:settings[@pass="specialize"]/u:component[@name="Microsoft-Windows-Shell-Setup"]'
  local oobe='/u:unattend/u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]'
  local app="$APP for $ENGINE"
  local -a args=(
    -L
    -N "u=$ns"
    -u "$setup/u:UserData/u:Organization | $specialize/u:OEMInformation/u:Model | $specialize/u:OEMName | $specialize/u:RegisteredOwner | $oobe/u:RegisteredOwner"
      -v "$app"
    -u "$oobe/u:Display/u:VerticalResolution"
      -v "$HEIGHT"
    -u "$oobe/u:Display/u:HorizontalResolution"
      -v "$WIDTH"
  )

  if [ -n "${HOST:-}" ]; then
    args+=(
      -u "$specialize/u:ComputerName"
        -v "$HOST"
    )
  fi

  xmlstarlet ed "${args[@]}" "$asset" || return 1

  return 0
}

updateLocaleXML() {

  local asset="$1"
  local language="$2"
  local ns="urn:schemas-microsoft-com:unattend"
  local international='/u:unattend/u:settings/u:component[@name="Microsoft-Windows-International-Core" or @name="Microsoft-Windows-International-Core-WinPE"]'
  local culture region keyboard
  local -a args=( -L -N "u=$ns" )

  culture=$(getLanguage "$language" "culture") || return 1

  if [ -n "$culture" ]; then
    args+=(
      -u "$international//u:UILanguage"
        -v "$culture"
    )
  fi

  region="${REGION:-$culture}"

  if [ -n "$region" ]; then
    args+=(
      -u "$international/u:UserLocale | $international/u:SystemLocale"
        -v "$region"
    )
  fi

  keyboard="${KEYBOARD:-$culture}"

  if [ -n "$keyboard" ]; then
    args+=(
      -u "$international/u:InputLocale"
        -v "$keyboard"
    )
  fi

  if (( ${#args[@]} > 3 )); then
    xmlstarlet ed "${args[@]}" "$asset" || return 1
  fi

  return 0
}

updateLocalAccount() {

  local asset="$1"
  local user="${USERNAME:-}"
  local pass="${PASSWORD:-admin}"
  local ns="urn:schemas-microsoft-com:unattend"
  local setup='/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]'
  local shell='/u:unattend/u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]'
  local local_accounts="$shell/u:UserAccounts/u:LocalAccounts/u:LocalAccount"
  local administrator="$shell/u:UserAccounts/u:AdministratorPassword"
  local autologon="$shell/u:AutoLogon"
  local counts records auto_user
  local shell_count local_count admin_count autologon_count
  local primary=0 matches=0 position name group token
  local separator=$'\x1f'
  local tmp current_user target_user pw admin
  local -a groups=()

  validateUsername "$user" "local" || return 1

  counts=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -v "count($shell)" -o '|' \
    -v "count($local_accounts)" -o '|' \
    -v "count($administrator)" -o '|' \
    -v "count($autologon)" \
    "$asset") || return 1

  IFS='|' read -r shell_count local_count admin_count autologon_count <<< "$counts"

  [ "$shell_count" = "1" ] || return 1
  (( local_count > 0 )) || return 1
  (( admin_count <= 1 )) || return 1
  (( autologon_count <= 1 )) || return 1

  records=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -m "$local_accounts" \
    -v 'position()' -o "$separator" \
    -v 'normalize-space(string(u:Name))' -o "$separator" \
    -v 'normalize-space(string(u:Group))' -n \
    "$asset") || return 1

  if [ "$autologon_count" = "1" ]; then
    auto_user=$(xmlstarlet sel \
      -N "u=$ns" \
      -T -t \
      -v "normalize-space(string($autologon/u:Username))" \
      "$asset") || return 1

    if [ -n "$auto_user" ]; then
      while IFS="$separator" read -r position name group; do
        [[ "${name,,}" == "${auto_user,,}" ]] || continue
        primary="$position"
        ((matches+=1))
      done <<< "$records"

      if (( matches > 1 )); then
        error "Multiple local accounts match the automatic-logon username!"
        return 1
      fi
    fi
  fi

  if [ "$primary" = "0" ] && [ "$local_count" = "1" ]; then
    primary=1
  fi

  # If a custom answer file contains several accounts without a usable
  # AutoLogon reference, select the unique account assigned to Administrators.
  if [ "$primary" = "0" ]; then
    matches=0

    while IFS="$separator" read -r position name group; do
      IFS=';,' read -r -a groups <<< "$group"

      for token in "${groups[@]}"; do
        token="${token#"${token%%[![:space:]]*}"}"
        token="${token%"${token##*[![:space:]]}"}"
        [[ "${token,,}" == "administrators" ]] || continue
        primary="$position"
        ((matches+=1))
        break
      done
    done <<< "$records"

    if (( matches != 1 )); then
      error "Failed to identify the primary local account in the answer file!"
      return 1
    fi
  fi

  local account="$local_accounts[$primary]"
  local password="$account/u:Password"

  current_user=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -v "normalize-space(string($account/u:Name))" \
    "$asset") || return 1

  [ -n "$current_user" ] || return 1
  target_user="${user:-$current_user}"

  if ! tmp=$(mktemp "${asset}.XXXXXX") ||
    ! cp -p -- "$asset" "$tmp"; then

    rm -f "${tmp:-}"
    return 1
  fi

  local account_password_count account_value_count account_plain_count
  local admin_value_count admin_plain_count
  local auto_name_count auto_password_count auto_value_count auto_plain_count

  counts=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -v "count($password)" -o '|' \
    -v "count($password/u:Value)" -o '|' \
    -v "count($password/u:PlainText)" -o '|' \
    -v "count($administrator/u:Value)" -o '|' \
    -v "count($administrator/u:PlainText)" -o '|' \
    -v "count($autologon/u:Username)" -o '|' \
    -v "count($autologon/u:Password)" -o '|' \
    -v "count($autologon/u:Password/u:Value)" -o '|' \
    -v "count($autologon/u:Password/u:PlainText)" \
    "$tmp") || {
    rm -f "$tmp"
    return 1
  }

  IFS='|' read -r \
    account_password_count account_value_count account_plain_count \
    admin_value_count admin_plain_count auto_name_count \
    auto_password_count auto_value_count auto_plain_count <<< "$counts"

  (( account_password_count <= 1 )) || { rm -f "$tmp"; return 1; }
  (( account_value_count <= 1 )) || { rm -f "$tmp"; return 1; }
  (( account_plain_count <= 1 )) || { rm -f "$tmp"; return 1; }
  (( admin_value_count <= 1 )) || { rm -f "$tmp"; return 1; }
  (( admin_plain_count <= 1 )) || { rm -f "$tmp"; return 1; }
  (( auto_name_count <= 1 )) || { rm -f "$tmp"; return 1; }
  (( auto_password_count <= 1 )) || { rm -f "$tmp"; return 1; }
  (( auto_value_count <= 1 )) || { rm -f "$tmp"; return 1; }
  (( auto_plain_count <= 1 )) || { rm -f "$tmp"; return 1; }

  if [ "$account_password_count" = "0" ]; then
    xmlstarlet ed -L \
      -N "u=$ns" \
      -s "$account" \
        -t elem -n 'Password' \
      "$tmp" || {
      rm -f "$tmp"
      return 1
    }
  fi

  if [ "$account_value_count" = "0" ]; then
    xmlstarlet ed -L \
      -N "u=$ns" \
      -s "$password" \
        -t elem -n 'Value' \
      "$tmp" || {
      rm -f "$tmp"
      return 1
    }
  fi

  if [ "$account_plain_count" = "0" ]; then
    xmlstarlet ed -L \
      -N "u=$ns" \
      -s "$password" \
        -t elem -n 'PlainText' \
      "$tmp" || {
      rm -f "$tmp"
      return 1
    }
  fi

  if [ "$admin_count" = "1" ]; then
    if [ "$admin_value_count" = "0" ]; then
      xmlstarlet ed -L \
        -N "u=$ns" \
        -s "$administrator" \
          -t elem -n 'Value' \
        "$tmp" || {
        rm -f "$tmp"
        return 1
      }
    fi

    if [ "$admin_plain_count" = "0" ]; then
      xmlstarlet ed -L \
        -N "u=$ns" \
        -s "$administrator" \
          -t elem -n 'PlainText' \
        "$tmp" || {
        rm -f "$tmp"
        return 1
      }
    fi
  fi

  if [ "$autologon_count" = "1" ]; then
    if [ "$auto_name_count" = "0" ]; then
      xmlstarlet ed -L \
        -N "u=$ns" \
        -s "$autologon" \
          -t elem -n 'Username' \
        "$tmp" || {
        rm -f "$tmp"
        return 1
      }
    fi

    if [ "$auto_password_count" = "0" ]; then
      xmlstarlet ed -L \
        -N "u=$ns" \
        -s "$autologon" \
          -t elem -n 'Password' \
        "$tmp" || {
        rm -f "$tmp"
        return 1
      }
    fi

    if [ "$auto_value_count" = "0" ]; then
      xmlstarlet ed -L \
        -N "u=$ns" \
        -s "$autologon/u:Password" \
          -t elem -n 'Value' \
        "$tmp" || {
        rm -f "$tmp"
        return 1
      }
    fi

    if [ "$auto_plain_count" = "0" ]; then
      xmlstarlet ed -L \
        -N "u=$ns" \
        -s "$autologon/u:Password" \
          -t elem -n 'PlainText' \
        "$tmp" || {
        rm -f "$tmp"
        return 1
      }
    fi
  fi

  pw=$(printf '%s' "${pass}Password" |
    iconv -f utf-8 -t utf-16le |
    base64 -w 0) || {
    rm -f "$tmp"
    return 1
  }

  admin=$(printf '%s' "${pass}AdministratorPassword" |
    iconv -f utf-8 -t utf-16le |
    base64 -w 0) || {
    rm -f "$tmp"
    return 1
  }

  local -a args=(
    -L
    -N "u=$ns"
    -u "$password/u:Value"
      -v "$pw"
    -u "$password/u:PlainText"
      -v 'false'
  )

  if [ -n "$user" ]; then
    args+=(
      -u "$account/u:Name"
        -v "$user"
      -u "$setup/u:UserData/u:FullName"
        -v "$user"
    )
  fi

  if [ "$admin_count" = "1" ]; then
    args+=(
      -u "$administrator/u:Value"
        -v "$admin"
      -u "$administrator/u:PlainText"
        -v 'false'
    )
  fi

  if [ "$autologon_count" = "1" ]; then
    args+=(
      -u "$autologon/u:Username"
        -v "$target_user"
      -u "$autologon/u:Password/u:Value"
        -v "$pw"
      -u "$autologon/u:Password/u:PlainText"
        -v 'false'
    )
  fi

  if ! xmlstarlet ed "${args[@]}" "$tmp" ||
    ! chmod --reference="$asset" "$tmp" ||
    ! mv -f "$tmp" "$asset"; then

    rm -f "$tmp"
    return 1
  fi

  return 0
}

updateMembership() {

  local asset="$1"
  local domain="$2"
  local workgroup="$3"
  local account="$4"
  local auth="$5"

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

    removeLocalAccount "$asset" || return 1
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
  local ns="urn:schemas-microsoft-com:unattend"
  local shell='/u:unattend/u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]'

  disabled "${AUTOLOGIN:-}" || return 0

  xmlstarlet ed -L \
    -N "u=$ns" \
    -d "$shell/u:AutoLogon" \
    "$asset" || return 1

  return 0
}

updateEditionXML() {

  local asset="$1"
  local ns="urn:schemas-microsoft-com:unattend"
  local upper='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  local lower='abcdefghijklmnopqrstuvwxyz'
  local setup='/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]'
  local selector="$setup/u:ImageInstall/u:OSImage/u:InstallFrom/u:MetaData[translate(normalize-space(u:Key), '$lower', '$upper')='/IMAGE/NAME']/u:Value"
  local edition count records position value prefix replacement
  local separator=$'\x1f'

  [ -n "${EDITION:-}" ] || return 0

  count=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -v "count($selector)" \
    "$asset") || return 1

  # Client and index-based answer files do not contain an /IMAGE/NAME
  # selector. In that case there is nothing to update.
  [ "$count" != "0" ] || return 0

  edition=$(normalizeServerEdition "$EDITION") || return 1
  edition="${edition//-/}"
  edition="${edition^^}"

  records=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -m "$selector" \
    -v 'position()' -o "$separator" \
    -v 'string(.)' -n \
    "$asset") || return 1

  while IFS="$separator" read -r position value; do
    [ -n "$position" ] || continue

    # Only Windows Server templates use EDITION as a mutable answer-file
    # selector. Products such as Hyper-V Server have fixed SERVER* flags that
    # must not be rewritten.
    [[ "${value,,}" == *"windows server"* ]] || continue

    if [[ "$value" =~ ^(.*[[:space:]])SERVER[A-Za-z0-9_-]+[[:space:]]*$ ]]; then
      prefix="${BASH_REMATCH[1]}"
      replacement="${prefix}SERVER$edition"
    elif [[ "$value" =~ ^SERVER[A-Za-z0-9_-]+[[:space:]]*$ ]]; then
      replacement="SERVER$edition"
    else
      continue
    fi

    xmlstarlet ed -L \
      -N "u=$ns" \
      -u "($selector)[$position]" \
      -v "$replacement" \
      "$asset" || return 1
  done <<< "$records"

  return 0
}

updateProductKey() {

  local script="$1"
  local key="${KEY:-}"
  local content

  if [ -z "$key" ]; then
    removeSetupBlock "$script" "PRODUCT_KEY" || return 1
    return 0
  fi

  printf -v content '%s\n%s' \
    'rem Install the product key without activating Windows immediately.' \
    "cscript.exe //B //Nologo \"%SystemRoot%\\System32\\slmgr.vbs\" /ipk \"$key\""

  replaceSetupBlock "$script" "PRODUCT_KEY" "$content" || return 1

  return 0
}

updateDiskID() {

  local asset="$1"
  local disk_type="${2,,}"
  local mode="${3:-setup}"
  local target="0"
  local ns="urn:schemas-microsoft-com:unattend"
  local setup='/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]'
  local disk_ids="$setup//u:DiskID"
  local count values value current
  local -a ids=()

  [ -s "$asset" ] || return 1

  case "$mode" in
    "setup" )
      case "$disk_type" in
        "" | "scsi" | "virtio-scsi" | "blk" | "virtio-blk" ) target="1" ;;
      esac
      ;;
    "image" ) ;;
    * ) return 1 ;;
  esac

  count=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -v "count($disk_ids)" \
    "$asset") || {
    error "Failed to read DiskID values from answer file: $asset"
    return 1
  }

  [ "$count" != "0" ] || return 0

  values=$(xmlstarlet sel \
    -N "u=$ns" \
    -T -t \
    -m "$disk_ids" \
    -v 'normalize-space(.)' -n \
    "$asset") || {
    error "Failed to read DiskID values from answer file: $asset"
    return 1
  }

  while IFS= read -r value; do
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
      error "Invalid DiskID value in answer file: $asset"
      return 1
    fi

    ids+=( "$value" )
  done <<< "$values"

  mapfile -t ids < <(printf '%s\n' "${ids[@]}" | sort -u)

  # Leave explicit multi-disk configurations untouched.
  (( ${#ids[@]} == 1 )) || return 0

  current="${ids[0]}"
  [ "$current" = "$target" ] && return 0

  case "$current" in
    "0" | "1" ) ;;
    * )
      error "Unsupported DiskID $current in answer file: $asset"
      return 1
      ;;
  esac

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -u "$disk_ids[normalize-space(.)='$current']" \
    -v "$target" \
    "$asset"; then

    error "Failed to update DiskID in answer file: $asset"
    return 1
  fi

  return 0
}

getXMLArchitecture() {

  local asset="$1"
  local ns="urn:schemas-microsoft-com:unattend"
  local arch
  local -a paths=(
    '/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]/@processorArchitecture'
    '/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-International-Core-WinPE"]/@processorArchitecture'
    '/u:unattend/u:settings/u:component[translate(@processorArchitecture, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") != "wow64"]/@processorArchitecture'
  )
  local path

  for path in "${paths[@]}"; do
    arch=$(xmlstarlet sel \
      -N "u=$ns" \
      -T -t \
      -v "normalize-space(string(($path)[1]))" \
      "$asset") || arch=""

    [ -n "$arch" ] || continue
    [[ "${arch,,}" != "wow64" ]] || continue
    printf '%s' "$arch"
    return 0
  done

  return 1
}

setConfigurationXML() {

  local asset="$1"
  local setup='/*[local-name()="unattend"]/*[local-name()="settings" and @pass="windowsPE"]/*[local-name()="component" and @name="Microsoft-Windows-Setup"]'
  local config="$setup/*[local-name()=\"UseConfigurationSet\"]"
  local setup_count config_count config_value result_count tmp

  [ -s "$asset" ] || return 1

  setup_count=$(xmlstarlet sel -T -t -v "count($setup)" "$asset") || return 1

  if [ "$setup_count" != "1" ]; then
    error "Failed to find a unique Microsoft-Windows-Setup component: $asset"
    return 1
  fi

  config_count=$(xmlstarlet sel -T -t -v "count($config)" "$asset") || return 1

  if [ "$config_count" -gt 1 ]; then
    error "Multiple UseConfigurationSet entries found in answer file: $asset"
    return 1
  fi

  if [ "$config_count" = "1" ]; then
    config_value=$(xmlstarlet sel \
      -T -t \
      -v "translate(normalize-space(string($config)), 'TRUE', 'true')" \
      "$asset") || return 1

    [ "$config_value" != "true" ] || return 0
  fi

  if ! tmp=$(mktemp -d); then
    error "Failed to create a temporary answer file!"
    return 1
  fi

  local stylesheet="$tmp/configuration.xsl"
  local result="$tmp/answer.xml"

  if ! cat > "$stylesheet" <<'XSL'
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" encoding="UTF-8" indent="yes"/>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="
    *[local-name()='UseConfigurationSet' and
      parent::*[
        local-name()='component' and
        @name='Microsoft-Windows-Setup' and
        parent::*[local-name()='settings' and @pass='windowsPE']
      ]
    ]">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:text>true</xsl:text>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="
    *[local-name()='UserData' and
      parent::*[
        local-name()='component' and
        @name='Microsoft-Windows-Setup' and
        parent::*[local-name()='settings' and @pass='windowsPE'] and
        not(*[local-name()='UseConfigurationSet'])
      ]
    ]">
    <xsl:element name="UseConfigurationSet" namespace="{namespace-uri()}">
      <xsl:text>true</xsl:text>
    </xsl:element>
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="
    *[local-name()='component' and
      @name='Microsoft-Windows-Setup' and
      parent::*[local-name()='settings' and @pass='windowsPE'] and
      not(*[local-name()='UseConfigurationSet']) and
      not(*[local-name()='UserData'])
    ]">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <xsl:element name="UseConfigurationSet" namespace="{namespace-uri()}">
        <xsl:text>true</xsl:text>
      </xsl:element>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
XSL
  then
    rm -rf "$tmp"
    return 1
  fi

  if ! xmlstarlet tr "$stylesheet" "$asset" > "$result"; then
    rm -rf "$tmp"
    error "Failed to enable the Windows configuration set!"
    return 1
  fi

  result_count=$(xmlstarlet sel \
    -T -t \
    -v "count($config[normalize-space(.)='true'])" \
    "$result") || {
    rm -rf "$tmp"
    return 1
  }

  if [ "$result_count" != "1" ]; then
    rm -rf "$tmp"
    error "Failed to enable the Windows configuration set!"
    return 1
  fi

  if ! chmod --reference="$asset" "$result" ||
    ! mv -f "$result" "$asset"; then

    rm -rf "$tmp"
    error "Failed to replace the updated answer file!"
    return 1
  fi

  rm -rf "$tmp" || return 1
  return 0
}

removeSharedFolder() {

  local script="$1"

  if ! disabled "${SHORTCUT:-}" &&
    ! disabled "${SAMBA:-}"; then
    return 0
  fi

  removeSetupBlock "$script" "SHARED_FOLDER" || return 1

  return 0
}

removeLocalAccount() {

  local asset="$1"
  local ns="urn:schemas-microsoft-com:unattend"
  local accounts='/u:unattend/u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:UserAccounts'

  if ! xmlstarlet ed -L \
    -N "u=$ns" \
    -d "$accounts/u:LocalAccounts | $accounts/u:AdministratorPassword" \
    "$asset"; then

    error "Failed to remove local account configuration from answer file!"
    return 1
  fi

  return 0
}

enableLog() {

  local script="$1"
  local content

  enabled "${LOG:-}" || return 0

  printf -v content '%s\n%s' \
    'rem Launch the custom script asynchronously in a separate visible window.' \
    'if exist "C:\OEM\install.bat" start "Install" cmd.exe /d /c ""C:\OEM\install.bat" > "C:\OEM\install.log" 2>&1"'

  replaceSetupBlock "$script" "OEM_SCRIPT" "$content" || return 1

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
