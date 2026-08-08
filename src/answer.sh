#!/usr/bin/env bash
set -Eeuo pipefail

XML_NS_UNATTEND='urn:schemas-microsoft-com:unattend'
XML_NS_WCM='http://schemas.microsoft.com/WMIConfig/2002/State'

XML_NS_WCM_ARG="wcm=$XML_NS_WCM"
XML_NS_UNATTEND_ARG="u=$XML_NS_UNATTEND"

XML_SETTINGS_OOBE='/u:unattend/u:settings[@pass="oobeSystem"]'
XML_SETTINGS_WINDOWS_PE='/u:unattend/u:settings[@pass="windowsPE"]'
XML_SETTINGS_SPECIALIZE='/u:unattend/u:settings[@pass="specialize"]'

XML_COMPONENT_SETUP="$XML_SETTINGS_WINDOWS_PE/u:component[@name='Microsoft-Windows-Setup']"
XML_COMPONENT_SHELL_OOBE="$XML_SETTINGS_OOBE/u:component[@name='Microsoft-Windows-Shell-Setup']"
XML_COMPONENT_SHELL_SPECIALIZE="$XML_SETTINGS_SPECIALIZE/u:component[@name='Microsoft-Windows-Shell-Setup']"
XML_COMPONENT_UNATTENDED_JOIN="$XML_SETTINGS_SPECIALIZE/u:component[@name='Microsoft-Windows-UnattendedJoin']"

updateXML() {

  local asset="$1"
  local language="$2"

  local domain="${DOMAIN:-}"
  local workgroup="${WORKGROUP:-}"
  local account="" auth="" result
  local -a values=()

  [ -z "${WIDTH:-}" ] && WIDTH="1280"
  [ -z "${HEIGHT:-}" ] && HEIGHT="720"

  validateXMLSettings || return 1
  ensureXMLDefaultNamespace "$asset" || return 1

  updateUserXML "$asset" || return 1
  updateLocaleXML "$asset" "$language" || return 1

  if [ -n "$domain" ]; then

    result=$(prepareDomainAccount "$domain") || return 1
    mapfile -t values <<< "$result"
    (( ${#values[@]} == 2 )) || return 1

    account="${values[0]}"
    auth="${values[1]}"

  else

    updateLocalAccount "$asset" || return 1

  fi

  updateMembership "$asset" "$domain" "$workgroup" "$account" "$auth" || return 1
  updateAutologinXML "$asset" || return 1
  updateEditionXML "$asset" || return 1

  validateGeneratedXML "$asset" || return 1

  return 0
}

setXML() {

  local file="$1"
  local index="${2:-}"

  local target="/run/assets/$DETECTED.xml"
  local custom_files=("/custom.xml" "$STORAGE/custom.xml" "/run/assets/custom.xml")

  CUSTOM_XML=""

  removeGeneratedXML "$target" || return 2

  if [ -d "${custom_files[0]}" ]; then
    error "The bind ${custom_files[0]} maps to a file that does not exist!"
    return 2
  fi

  # A custom answer file always takes precedence over bundled or generated
  # templates, in root, storage, then asset-directory order.
  for file in "${custom_files[@]}"; do

    if [ -f "$file" ] && [ -s "$file" ]; then

      CUSTOM_XML="Y"
      XML="$file"

      return 0

    fi

  done

  file="$1"

  # Generate evaluation or edition-specific templates only when the selected
  # source is unavailable or differs from the detected image identity.
  if [[ "${DETECTED,,}" == *"-eval" ]] &&
    { [ ! -f "$file" ] || [ ! -s "$file" ]; }; then

    generateEvalXML "$DETECTED" "$index" || return $?
    file="$target"

  elif [ ! -f "$file" ] || [ ! -s "$file" ]; then

    file="$target"

  elif [[ "$file" != "$target" ]]; then

    generateFallbackXML "$DETECTED" "$index" || return $?
    file="$target"

  fi

  [ -f "$file" ] && [ -s "$file" ] || return 1

  XML="$file"
  return 0
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
  file="/run/assets/${id%%-*}.xml"
  [ -s "$file" ] || return 1

  return 0
}

addAnswerFile() {

  local asset="$1"
  local language="$2"
  local stage="$3"

  local answer="$stage/Autounattend.xml"

  if enabled "$MANUAL"; then
    removeGeneratedXML "$asset" || return 1
    return 0
  fi

  if [ ! -f "$asset" ] || [ ! -s "$asset" ]; then
    error "Failed to find answer file: $asset"
    return 1
  fi

  local name
  name=$(basename "$asset") || return 1

  info "Adding $name for automatic installation..."

  if ! cp -L -- "$asset" "$answer"; then
    error "Failed to stage answer file: $asset"
    return 1
  fi

  removeGeneratedXML "$asset" || return 1

  # Custom answer files keep their user-defined settings, but still receive
  # the media-specific disk and configuration-set adjustments below.
  if [ -z "${CUSTOM_XML:-}" ]; then

    if ! updateXML "$answer" "$language"; then
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

  if [ -z "${CUSTOM_XML:-}" ]; then

    if ! prepareSetupScript "$asset" "$stage"; then
      error "Failed to prepare the Windows setup script!"
      return 1
    fi

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

  local setup="$XML_COMPONENT_SETUP"
  local os_image="$setup/u:ImageInstall/u:OSImage"
  local install_from="$os_image/u:InstallFrom"
  local install_to="$os_image/u:InstallTo"
  local directory install_count install_to_count tmp

  if [ -n "$index" ] && [[ ! "$index" =~ ^[1-9][0-9]*$ ]]; then
    enabled "$DEBUG" && echo "The $type answer file received an invalid image index: $index." >&2
    error "Invalid $type image index: $index"
    return 1
  fi

  directory=$(dirname "$target") || {
    enabled "$DEBUG" && echo "dirname failed for the $type answer file target: $target" >&2
    error "Failed to determine the $type answer file directory!"
    return 1
  }

  if ! tmp=$(mktemp -p "$directory" ".${id}.XXXXXX"); then
    enabled "$DEBUG" && echo "mktemp failed in the $type answer file directory: $directory" >&2
    error "Failed to create a temporary $type answer file!"
    return 1
  fi

  if ! cp -L -- "$source" "$tmp"; then
    enabled "$DEBUG" && echo "Failed to copy the $type answer template from $source to $tmp." >&2
    rm -f "$tmp"
    error "Failed to generate $type answer file from $source!"
    return 1
  fi

  # Keep empty ProductKey structures because some Windows installers require
  # the node to exist, but remove a concrete key that could select another edition.
  if ! removeEmbeddedProductKeys "$tmp"; then
    enabled "$DEBUG" && echo "Failed while removing embedded product keys from the $type answer file." >&2
    rm -f "$tmp"
    error "Failed to remove the embedded $type product key!"
    return 1
  fi

  if [ "$type" != "evaluation" ] || [ "$remove_selector" = "Y" ]; then

    if ! xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -d "$install_from" "$tmp"; then
      enabled "$DEBUG" && echo "Failed to remove the existing InstallFrom selector from the $type answer file." >&2
      rm -f "$tmp"
      error "Failed to generate $type answer file from $source!"
      return 1
    fi

  fi

  if [ -n "$index" ]; then

    install_count=$(getXMLNodeCount "$tmp" "$install_from") || {
      enabled "$DEBUG" && echo "Failed to count InstallFrom selectors in the $type answer file." >&2
      rm -f "$tmp"
      error "Failed to read the $type image selector count!"
      return 1
    }

    if (( install_count > 1 )); then
      enabled "$DEBUG" && echo "The $type answer file contains $install_count InstallFrom selectors." >&2
      rm -f "$tmp"
      error "Multiple $type image selectors were found!"
      return 1
    fi

    if [ "$install_count" = "0" ]; then

      # InstallFrom must be inserted before InstallTo to preserve the ordering
      # expected by the Windows Setup schema.
      install_to_count=$(getXMLNodeCount "$tmp" "$install_to") || {
        enabled "$DEBUG" && echo "Failed to count InstallTo nodes in the $type answer file." >&2
        rm -f "$tmp"
        error "Failed to read the $type installation target count!"
        return 1
      }

      if [ "$install_to_count" != "1" ]; then
        enabled "$DEBUG" && echo "The $type answer file contains $install_to_count InstallTo nodes instead of 1." >&2
        rm -f "$tmp"
        error "Failed to find a unique $type installation target!"
        return 1
      fi

      if ! xmlstarlet ed -L \
        -N "$XML_NS_UNATTEND_ARG" \
        -N "$XML_NS_WCM_ARG" \
        -i "($install_to)[1]" -t elem -n 'InstallFrom' \
        -s "$os_image/*[local-name()='InstallFrom']" -t elem -n 'MetaData' \
        -i "$os_image/*[local-name()='InstallFrom']/*[local-name()='MetaData']" -t attr -n 'wcm:action' -v 'add' \
        -s "$os_image/*[local-name()='InstallFrom']/*[local-name()='MetaData']" -t elem -n 'Key' -v '/IMAGE/INDEX' \
        -s "$os_image/*[local-name()='InstallFrom']/*[local-name()='MetaData']" -t elem -n 'Value' -v "$index" \
        "$tmp"; then

        enabled "$DEBUG" && echo "xmlstarlet failed while inserting image index $index into the $type answer file." >&2
        rm -f "$tmp"
        error "Failed to select $type image index $index!"
        return 1
      fi
    fi

  fi

  if ! markGeneratedXML "$tmp"; then
    enabled "$DEBUG" && echo "Failed to mark the temporary $type answer file as generated: $tmp" >&2
    rm -f "$tmp"
    error "Failed to mark generated $type answer file!"
    return 1
  fi

  if ! validateGeneratedXML "$tmp"; then
    enabled "$DEBUG" && echo "Validation failed for the generated $type answer file: $tmp" >&2
    rm -f "$tmp"
    return 1
  fi

  if ! chmod 644 "$tmp"; then
    enabled "$DEBUG" && echo "Failed to set mode 644 on the generated $type answer file: $tmp" >&2
    rm -f "$tmp"
    error "Failed to create $type answer file: $target"
    return 1
  fi

  if ! mv -f "$tmp" "$target"; then
    enabled "$DEBUG" && echo "Failed to move the generated $type answer file from $tmp to $target." >&2
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

  if [[ "${id,,}" != *"-eval" ]]; then
    enabled "$DEBUG" && echo "Evaluation XML generation was requested for a non-evaluation image: $id" >&2
    return 1
  fi

  local normal="${id::-5}"
  local remove_selector="N"
  local index="$detected_index"
  local target="/run/assets/$id.xml"
  local source="/run/assets/$normal.xml"

  removeGeneratedXML "$source" || {
    enabled "$DEBUG" && echo "Failed to remove a previously generated evaluation source template: $source" >&2
    return 2
  }

  if [ ! -s "$source" ]; then

    source="/run/assets/${normal%%-*}.xml"
    removeGeneratedXML "$source" || {
      enabled "$DEBUG" && echo "Failed to remove a previously generated family evaluation template: $source" >&2
      return 2
    }

  fi

  if [ ! -s "$source" ]; then
    enabled "$DEBUG" && echo "No usable source template was found for evaluation image: $id" >&2
    return 1
  fi

  if [ -n "$detected_index" ]; then
    remove_selector="Y"
  else
    # No WIM was inspected, so retain the known defaults for download routes.
    case "${id,,}" in
      *"-ltsc-eval" ) index="1" ;;
      *"-iot-eval" )  index="2" ;;
    esac
  fi

  generateAnswerFile "$id" "$source" "$target" "$index" "evaluation" "$remove_selector" || {
    enabled "$DEBUG" && echo "Failed to generate the evaluation answer file for $id from $source." >&2
    return 2
  }

  return 0
}

generateFallbackXML() {

  # Fallback templates are generated from the generic version so unsupported
  # editions can use the detected WIM index without inheriting a product key.

  local id="$1"
  local index="${2:-}"

  local target="/run/assets/$id.xml"
  local source="/run/assets/${id%%-*}.xml"

  if [ "$source" = "$target" ]; then
    enabled "$DEBUG" && echo "Fallback XML generation has no distinct source template for: $id" >&2
    return 1
  fi

  removeGeneratedXML "$source" || {
    enabled "$DEBUG" && echo "Failed to remove a previously generated fallback source template: $source" >&2
    return 2
  }

  if [ ! -s "$source" ]; then
    enabled "$DEBUG" && echo "The fallback source template does not exist or is empty: $source" >&2
    return 1
  fi

  generateAnswerFile "$id" "$source" "$target" "$index" "fallback" "Y" || {
    enabled "$DEBUG" && echo "Failed to generate the fallback answer file for $id from $source." >&2
    return 2
  }

  return 0
}

updateUserXML() {

  local asset="$1"
  local app="$APP for $ENGINE"

  local xpath
  xpath="$XML_COMPONENT_SETUP/u:UserData/u:Organization"
  xpath+=" | $XML_COMPONENT_SHELL_SPECIALIZE/u:OEMInformation/u:Model"
  xpath+=" | $XML_COMPONENT_SHELL_SPECIALIZE/u:OEMName"
  xpath+=" | $XML_COMPONENT_SHELL_SPECIALIZE/u:RegisteredOwner"
  xpath+=" | $XML_COMPONENT_SHELL_OOBE/u:RegisteredOwner"

  local -a args=(
    -L
    -N "$XML_NS_UNATTEND_ARG"
    -u "$xpath" -v "$app"
    -u "$XML_COMPONENT_SHELL_OOBE/u:Display/u:VerticalResolution" -v "$HEIGHT"
    -u "$XML_COMPONENT_SHELL_OOBE/u:Display/u:HorizontalResolution" -v "$WIDTH"
  )

  if [ -n "${HOST:-}" ]; then
    args+=(-u "$XML_COMPONENT_SHELL_SPECIALIZE/u:ComputerName" -v "$HOST")
  fi

  xmlstarlet ed "${args[@]}" "$asset" || return 1

  return 0
}

updateLocaleXML() {

  local asset="$1"
  local language="$2"

  local international='/u:unattend/u:settings/u:component[@name="Microsoft-Windows-International-Core" or @name="Microsoft-Windows-International-Core-WinPE"]'
  local culture region keyboard
  local -a args=(-L -N "$XML_NS_UNATTEND_ARG")

  culture=$(getLanguage "$language" "culture") || return 1

  if [ -n "$culture" ]; then
    args+=(-u "$international//u:UILanguage" -v "$culture")
  fi

  region="${REGION:-$culture}"

  if [ -n "$region" ]; then
    args+=(-u "$international/u:UserLocale | $international/u:SystemLocale" -v "$region")
  fi

  keyboard="${KEYBOARD:-$culture}"

  if [ -n "$keyboard" ]; then
    args+=(-u "$international/u:InputLocale" -v "$keyboard")
  fi

  if (( ${#args[@]} > 3 )); then
    xmlstarlet ed "${args[@]}" "$asset" || return 1
  fi

  return 0
}

updateAutologinXML() {

  local asset="$1"
  local shell="$XML_COMPONENT_SHELL_OOBE"

  disabled "${AUTOLOGIN:-}" || return 0

  xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -d "$shell/u:AutoLogon" "$asset" || return 1

  return 0
}

updateProductKey() {

  local script="$1"

  local key="${KEY:-}" content

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

updateWorkgroup() {

  local asset="$1"
  local workgroup="$2"
  local arch tmp xpath

  arch=$(getXMLArchitecture "$asset") || return 1

  # Apply all membership changes to a copy and publish it only after the old
  # domain, credential, OU, and workgroup nodes have been replaced successfully.
  tmp=$(copyXMLAsset "$asset") || return 1

  xpath="$XML_COMPONENT_UNATTENDED_JOIN/u:Identification/u:Credentials"
  xpath+=" | $XML_COMPONENT_UNATTENDED_JOIN/u:Identification/u:JoinDomain"
  xpath+=" | $XML_COMPONENT_UNATTENDED_JOIN/u:Identification/u:JoinWorkgroup"
  xpath+=" | $XML_COMPONENT_UNATTENDED_JOIN/u:Identification/u:MachineObjectOU"

  if ! ensureUnattendedJoin "$tmp" "$arch" ||
    ! xmlstarlet ed -L \
      -N "$XML_NS_UNATTEND_ARG" \
      -d "$xpath" \
      -s "$XML_COMPONENT_UNATTENDED_JOIN/u:Identification" -t elem -n 'JoinWorkgroup' "$tmp" ||
    ! xmlstarlet ed -L \
      -N "$XML_NS_UNATTEND_ARG" \
      -u "$XML_COMPONENT_UNATTENDED_JOIN/u:Identification/*[local-name()='JoinWorkgroup']" -v "$workgroup" "$tmp" ||
    ! replaceXMLAsset "$asset" "$tmp"; then

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

  local arch tmp

  arch=$(getXMLArchitecture "$asset") || return 1

  # Account and join settings are separate XML transformations, so update a
  # copy to keep the original answer file intact if either transformation fails.
  tmp=$(copyXMLAsset "$asset") || return 1

  if ! configureDomainAccounts "$tmp" "$domain" "$account" "$pass" ||
    ! configureDomainJoin "$tmp" "$domain" "$auth" "$pass" "$ou" "$arch" ||
    ! replaceXMLAsset "$asset" "$tmp"; then

    rm -f "$tmp"
    return 1
  fi

  return 0
}

configureDomainAccounts() {

  local asset="$1"
  local domain="$2"
  local account="$3"
  local pass="$4"

  local shell="$XML_COMPONENT_SHELL_OOBE"
  local accounts="$shell/u:UserAccounts"
  local administrator="$accounts/u:AdministratorPassword"
  local autologon="$shell/u:AutoLogon"
  local domain_accounts="$accounts/u:DomainAccounts"
  local counts shell_count administrator_count
  local accounts_count autologon_count child_count

  counts=$(xmlstarlet sel \
    -N "$XML_NS_UNATTEND_ARG" \
    -T -t \
    -v "count($shell)" -o '|' \
    -v "count($accounts)" -o '|' \
    -v "count($administrator)" -o '|' -v "count($autologon)" "$asset") || return 1

  IFS='|' read -r shell_count accounts_count administrator_count autologon_count <<< "$counts"

  [ "$shell_count" = "1" ] || return 1
  (( accounts_count <= 1 )) || return 1
  (( administrator_count <= 1 )) || return 1
  (( autologon_count <= 1 )) || return 1

  if [ "$accounts_count" = "0" ]; then

    child_count=$(getXMLNodeCount "$asset" "$shell/*") || return 1

    if [ "$child_count" = "0" ]; then
      xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -s "$shell" -t elem -n 'UserAccounts' "$asset" || return 1
    else
      xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -i "$shell/*[1]" -t elem -n 'UserAccounts' "$asset" || return 1
    fi

  fi

  local created_accounts="$accounts/*[local-name()='DomainAccounts']"
  local account_list="$created_accounts/*[local-name()='DomainAccountList']"
  local domain_account="$account_list/*[local-name()='DomainAccount']"
  local created_autologon="$shell/*[local-name()='AutoLogon']"
  local auto_password="$created_autologon/*[local-name()='Password']"

  # Rebuild domain-account and autologon nodes from a clean state so stale
  # local-template values cannot survive a domain conversion.
  local -a args=(
    -L
    -N "$XML_NS_UNATTEND_ARG"
    -N "$XML_NS_WCM_ARG"
    -d "$domain_accounts | $autologon"
  )

  # Insert DomainAccounts before AdministratorPassword when it exists to retain
  # the child order expected by the unattend schema.
  if [ "$administrator_count" = "1" ]; then
    args+=(-i "($administrator)[1]" -t elem -n 'DomainAccounts')
  else
    args+=(-s "$accounts" -t elem -n 'DomainAccounts')
  fi

  args+=(
    -s "$created_accounts" -t elem -n 'DomainAccountList'
    -i "$account_list" -t attr -n 'wcm:action' -v 'add'
    -s "$account_list" -t elem -n 'DomainAccount'
    -i "$domain_account" -t attr -n 'wcm:action' -v 'add'
    -s "$domain_account" -t elem -n 'Name'
    -s "$domain_account" -t elem -n 'Group' -v 'Administrators'
    -s "$account_list" -t elem -n 'Domain'
    -a "$accounts" -t elem -n 'AutoLogon'
    -s "$created_autologon" -t elem -n 'Username'
    -s "$created_autologon" -t elem -n 'Domain'
    -s "$created_autologon" -t elem -n 'Enabled' -v 'true'
    -s "$created_autologon" -t elem -n 'LogonCount' -v '65432'
    -s "$created_autologon" -t elem -n 'Password'
    -s "$auto_password" -t elem -n 'Value'
    -s "$auto_password" -t elem -n 'PlainText' -v 'true'
  )

  xmlstarlet ed "${args[@]}" "$asset" || return 1

  xmlstarlet ed -L \
    -N "$XML_NS_UNATTEND_ARG" \
    -u "$domain_account/*[local-name()='Name']" -v "$account" \
    -u "$account_list/*[local-name()='Domain']" -v "$domain" \
    -u "$created_autologon/*[local-name()='Username']" -v "$account" \
    -u "$created_autologon/*[local-name()='Domain']" -v "$domain" \
    -u "$auto_password/*[local-name()='Value']" -v "$pass" "$asset" || return 1

  return 0
}

configureDomainJoin() {

  local asset="$1"
  local domain="$2"
  local auth="$3"
  local pass="$4"
  local ou="$5"
  local arch="$6"

  local cred_domain="$domain"
  local credentials="$XML_COMPONENT_UNATTENDED_JOIN/u:Identification/*[local-name()='Credentials']"

  local xpath
  xpath="$XML_COMPONENT_UNATTENDED_JOIN/u:Identification/u:Credentials"
  xpath+=" | $XML_COMPONENT_UNATTENDED_JOIN/u:Identification/u:JoinDomain"
  xpath+=" | $XML_COMPONENT_UNATTENDED_JOIN/u:Identification/u:JoinWorkgroup"
  xpath+=" | $XML_COMPONENT_UNATTENDED_JOIN/u:Identification/u:MachineObjectOU"

  local -a args=(
    -L
    -N "$XML_NS_UNATTEND_ARG"
    -d "$xpath"
    -s "$XML_COMPONENT_UNATTENDED_JOIN/u:Identification" -t elem -n 'Credentials'
  )

  ensureUnattendedJoin "$asset" "$arch" || return 1

  # A user@domain UPN already contains its qualifier; adding a separate Domain
  # credential node would describe the account twice.
  case "$auth" in
    *@* ) cred_domain="" ;;
  esac

  if [ -n "$cred_domain" ]; then
    args+=(-s "$credentials" -t elem -n 'Domain')
  fi

  args+=(
    -s "$credentials" -t elem -n 'Username'
    -s "$credentials" -t elem -n 'Password'
    -s "$XML_COMPONENT_UNATTENDED_JOIN/u:Identification" -t elem -n 'JoinDomain'
  )

  if [ -n "$ou" ]; then
    args+=(-s "$XML_COMPONENT_UNATTENDED_JOIN/u:Identification" -t elem -n 'MachineObjectOU')
  fi

  xmlstarlet ed "${args[@]}" "$asset" || return 1

  local -a values=(
    -L
    -N "$XML_NS_UNATTEND_ARG"
    -u "$credentials/*[local-name()='Username']" -v "$auth"
    -u "$credentials/*[local-name()='Password']" -v "$pass"
    -u "$XML_COMPONENT_UNATTENDED_JOIN/u:Identification/*[local-name()='JoinDomain']" -v "$domain"
  )

  if [ -n "$cred_domain" ]; then
    values+=(-u "$credentials/*[local-name()='Domain']" -v "$cred_domain")
  fi

  if [ -n "$ou" ]; then
    values+=(-u "$XML_COMPONENT_UNATTENDED_JOIN/u:Identification/*[local-name()='MachineObjectOU']" -v "$ou")
  fi

  xmlstarlet ed "${values[@]}" "$asset" || return 1

  return 0
}

findPrimaryLocalAccount() {

  local asset="$1"

  local shell="$XML_COMPONENT_SHELL_OOBE"
  local local_accounts="$shell/u:UserAccounts/u:LocalAccounts/u:LocalAccount"
  local administrator="$shell/u:UserAccounts/u:AdministratorPassword"
  local autologon="$shell/u:AutoLogon"
  local auto_primary=0 auto_matches=0
  local admin_primary=0 admin_matches=0
  local selected=0 separator=$'\x1f'
  local counts records auto_user selected_user position name group
  local shell_count local_count found_admin found_autologon token
  local -a groups=()

  counts=$(xmlstarlet sel \
    -N "$XML_NS_UNATTEND_ARG" \
    -T -t \
    -v "count($shell)" -o '|' \
    -v "count($local_accounts)" -o '|' \
    -v "count($administrator)" -o '|' -v "count($autologon)" "$asset") || return 1

  IFS='|' read -r shell_count local_count found_admin found_autologon <<< "$counts"

  [ "$shell_count" = "1" ] || return 1
  (( local_count > 0 )) || return 1
  (( found_admin <= 1 )) || return 1
  (( found_autologon <= 1 )) || return 1

  auto_user=""

  if [ "$found_autologon" = "1" ]; then
    auto_user=$(xmlstarlet sel \
      -N "$XML_NS_UNATTEND_ARG" -T -t -v "normalize-space(string($autologon/u:Username))" "$asset") || return 1
  fi

  records=$(xmlstarlet sel \
    -N "$XML_NS_UNATTEND_ARG" \
    -T -t \
    -m "$local_accounts" \
    -v 'position()' -o "$separator" \
    -v 'normalize-space(string(u:Name))' -o "$separator" \
    -v 'normalize-space(string(u:Group))' -n "$asset") || return 1

  while IFS="$separator" read -r position name group; do

    if [ -n "$auto_user" ] &&
      [[ "${name,,}" == "${auto_user,,}" ]]; then
      auto_primary="$position"
      ((auto_matches += 1))
    fi

    IFS=';,' read -r -a groups <<< "$group"

    for token in "${groups[@]}"; do

      token="${token#"${token%%[![:space:]]*}"}"
      token="${token%"${token##*[![:space:]]}"}"

      [[ "${token,,}" == "administrators" ]] || continue

      admin_primary="$position"
      ((admin_matches += 1))

      break

    done

  done <<< "$records"

  if (( auto_matches > 1 )); then
    error "Multiple local accounts match the automatic-logon username!"
    return 1
  fi

  # Prefer the account referenced by AutoLogon, then the only account, then
  # the only administrator. Ambiguous templates are rejected rather than guessed.
  if (( auto_matches == 1 )); then
    selected="$auto_primary"
  elif (( local_count == 1 )); then
    selected=1
  elif (( admin_matches == 1 )); then
    selected="$admin_primary"
  else
    error "Failed to identify the primary local account in the answer file!"
    return 1
  fi

  selected_user=$(xmlstarlet sel \
    -N "$XML_NS_UNATTEND_ARG" -T -t -v "normalize-space(string(${local_accounts}[${selected}]/u:Name))" "$asset") || return 1

  [ -n "$selected_user" ] || return 1

  printf '%s\n' "$selected" "$selected_user" "$found_admin" "$found_autologon"

  return 0
}

updateLocalAccount() {

  local asset="$1"

  local user="${USERNAME:-}"
  local pass="${PASSWORD:-admin}"
  local setup="$XML_COMPONENT_SETUP"
  local shell="$XML_COMPONENT_SHELL_OOBE"
  local local_accounts="$shell/u:UserAccounts/u:LocalAccounts/u:LocalAccount"
  local administrator="$shell/u:UserAccounts/u:AdministratorPassword"
  local autologon="$shell/u:AutoLogon"
  local primary admin_count autologon_count tmp
  local current_user target_user pw admin result
  local -a values=()

  validateUsername "$user" "local" || return 1

  result=$(findPrimaryLocalAccount "$asset") || return 1
  mapfile -t values <<< "$result"
  (( ${#values[@]} == 4 )) || return 1

  primary="${values[0]}"
  current_user="${values[1]}"
  admin_count="${values[2]}"
  autologon_count="${values[3]}"

  local account="${local_accounts}[${primary}]"
  local password="$account/*[local-name()='Password']"
  local admin_value="$administrator/*[local-name()='Value']"
  local admin_plain="$administrator/*[local-name()='PlainText']"
  local auto_password="$autologon/*[local-name()='Password']"
  local auto_value="$auto_password/*[local-name()='Value']"
  local auto_plain="$auto_password/*[local-name()='PlainText']"

  target_user="${user:-$current_user}"

  # Update the selected local account, Administrator password, and AutoLogon
  # credentials atomically so they cannot become inconsistent.
  tmp=$(copyXMLAsset "$asset") || return 1

  if ! validateUniqueXMLNodes "$tmp" \
      "$password" \
      "$password/*[local-name()='Value']" \
      "$password/*[local-name()='PlainText']" \
      "$admin_value" \
      "$admin_plain" \
      "$autologon/*[local-name()='Username']" "$auto_password" "$auto_value" "$auto_plain"; then

    rm -f "$tmp"
    return 1
  fi

  pw=$(encodeUnattendPassword "$pass" "Password") || {
    rm -f "$tmp"
    return 1
  }

  admin=$(encodeUnattendPassword "$pass" "AdministratorPassword") || {
    rm -f "$tmp"
    return 1
  }

  local -a args=(
    -L
    -N "$XML_NS_UNATTEND_ARG"
    -s "${account}[not(*[local-name()='Password'])]" -t elem -n 'Password'
    -s "${password}[not(*[local-name()='Value'])]" -t elem -n 'Value'
    -s "${password}[not(*[local-name()='PlainText'])]" -t elem -n 'PlainText'
    -u "$password/*[local-name()='Value']" -v "$pw"
    -u "$password/*[local-name()='PlainText']" -v 'false'
  )

  if [ -n "$user" ]; then
    args+=(
      -u "$account/u:Name" -v "$user"
      -u "$setup/u:UserData/u:FullName" -v "$user"
    )
  fi

  if [ "$admin_count" = "1" ]; then
    args+=(
      -s "${administrator}[not(*[local-name()='Value'])]" -t elem -n 'Value'
      -s "${administrator}[not(*[local-name()='PlainText'])]" -t elem -n 'PlainText'
      -u "$admin_value" -v "$admin"
      -u "$admin_plain" -v 'false'
    )
  fi

  if [ "$autologon_count" = "1" ]; then
    args+=(
      -s "${autologon}[not(*[local-name()='Username'])]" -t elem -n 'Username'
      -s "${autologon}[not(*[local-name()='Password'])]" -t elem -n 'Password'
      -s "${auto_password}[not(*[local-name()='Value'])]" -t elem -n 'Value'
      -s "${auto_password}[not(*[local-name()='PlainText'])]" -t elem -n 'PlainText'
      -u "$autologon/*[local-name()='Username']" -v "$target_user"
      -u "$auto_value" -v "$pw"
      -u "$auto_plain" -v 'false'
    )
  fi

  if ! xmlstarlet ed "${args[@]}" "$tmp" ||
    ! replaceXMLAsset "$asset" "$tmp"; then

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

    if ! updateDomain "$asset" "$domain" "$account" "$auth" "$PASSWORD" "${DOMAIN_OU:-}"; then
      error "Failed to add domain configuration to answer file!"
      return 1
    fi

    removeLocalAccount "$asset" || return 1
    return 0
  fi

  [ -n "$workgroup" ] || return 0

  if ! updateWorkgroup "$asset" "$workgroup"; then
    error "Failed to add workgroup configuration to answer file!"
    return 1
  fi

  return 0
}

updateEditionXML() {

  local asset="$1"

  local setup="$XML_COMPONENT_SETUP"
  local upper='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  local lower='abcdefghijklmnopqrstuvwxyz'
  local selector="$setup/u:ImageInstall/u:OSImage/u:InstallFrom/u:MetaData[translate(normalize-space(u:Key), '$lower', '$upper')='/IMAGE/NAME']/u:Value"
  local edition count records position value replacement
  local separator=$'\x1f'

  [ -n "${EDITION:-}" ] || return 0

  count=$(getXMLNodeCount "$asset" "$selector") || return 1

  # Client and index-based answer files do not contain an /IMAGE/NAME
  # selector. In that case there is nothing to update.
  [ "$count" != "0" ] || return 0

  edition=$(normalizeServerEdition "$EDITION") || return 1
  edition="${edition//-/}"
  edition="${edition^^}"

  records=$(xmlstarlet sel \
    -N "$XML_NS_UNATTEND_ARG" -T -t -m "$selector" -v 'position()' -o "$separator" -v 'string(.)' -n "$asset") || return 1

  while IFS="$separator" read -r position value; do

    [ -n "$position" ] || continue

    # Only Windows Server templates use EDITION as a mutable answer-file selector.
    # Products such as Hyper-V Server have fixed SERVER* flags that must not be rewritten.
    [[ "${value,,}" == *"windows server"* ]] || continue
    [[ "$value" =~ ^(.*[[:space:]])SERVER[A-Za-z0-9_-]+[[:space:]]*$ ]] || continue

    replacement="${BASH_REMATCH[1]}SERVER$edition"

    xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -u "($selector)[$position]" -v "$replacement" "$asset" || return 1

  done <<< "$records"

  return 0
}

updateDiskID() {

  local asset="$1"
  local disk_type="${2,,}"

  local target="0"
  local setup="$XML_COMPONENT_SETUP"
  local disk_ids="$setup//u:DiskID"
  local count values value current
  local -a ids=()

  [ -s "$asset" ] || return 1

  # The setup overlay occupies disk 0, so VirtIO disks move to disk 1.

  case "$disk_type" in
    "" | "scsi" | "virtio-scsi" | "blk" | "virtio-blk" ) target="1" ;;
  esac

  count=$(getXMLNodeCount "$asset" "$disk_ids") || {
    error "Failed to read DiskID values from answer file: $asset"
    return 1
  }

  [ "$count" != "0" ] || return 0

  values=$(xmlstarlet sel -N "$XML_NS_UNATTEND_ARG" -T -t -m "$disk_ids" -v 'normalize-space(.)' -n "$asset") || {
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
      return 1 ;;

  esac

  if ! xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -u "${disk_ids}[normalize-space(.)='$current']" -v "$target" "$asset"; then
    error "Failed to update DiskID in answer file: $asset"
    return 1
  fi

  return 0
}

getXMLArchitecture() {

  local asset="$1"

  # Prefer architecture declarations from Windows PE setup components and skip
  # wow64 compatibility components, which do not describe the target image.
  local -a paths=(
    "$XML_COMPONENT_SETUP/@processorArchitecture"
    "$XML_SETTINGS_WINDOWS_PE/u:component[@name='Microsoft-Windows-International-Core-WinPE']/@processorArchitecture"
    '/u:unattend/u:settings/u:component[translate(@processorArchitecture, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") != "wow64"]/@processorArchitecture'
  )

  local arch path

  for path in "${paths[@]}"; do

    arch=$(xmlstarlet sel -N "$XML_NS_UNATTEND_ARG" -T -t -v "normalize-space(string(($path)[1]))" "$asset") || arch=""

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
  local userdata="$setup/*[local-name()='UserData']"
  local config="$setup/*[local-name()='UseConfigurationSet']"
  local setup_count config_count config_value userdata_count result_count tmp

  [ -s "$asset" ] || return 1

  setup_count=$(getXMLNodeCount "$asset" "$setup") || return 1

  if [ "$setup_count" != "1" ]; then
    error "Failed to find a unique Microsoft-Windows-Setup component: $asset"
    return 1
  fi

  config_count=$(getXMLNodeCount "$asset" "$config") || return 1

  if [ "$config_count" -gt 1 ]; then
    error "Multiple UseConfigurationSet entries found in answer file: $asset"
    return 1
  fi

  if [ "$config_count" = "1" ]; then
    config_value=$(xmlstarlet sel -T -t -v "translate(normalize-space(string($config)), 'TRUE', 'true')" "$asset") || return 1
    [ "$config_value" != "true" ] || return 0
  fi

  userdata_count=$(getXMLNodeCount "$asset" "$userdata") || return 1

  if [ "$userdata_count" -gt 1 ]; then
    error "Multiple UserData entries found in answer file: $asset"
    return 1
  fi

  tmp=$(copyXMLAsset "$asset") || {
    error "Failed to create a temporary answer file!"
    return 1
  }

  local msg="Failed to enable the Windows configuration set!"

  if [ "$config_count" = "0" ] && ! ensureXMLDefaultNamespace "$tmp"; then
    rm -f "$tmp"
    error "$msg (1)"
    return 1
  fi

  if [ "$config_count" = "1" ]; then
    xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -u "$config" -v "true" "$tmp" || {
      rm -f "$tmp"
      error "$msg (2)"
      return 1
    }
  elif [ "$userdata_count" = "1" ]; then
    xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -i "$userdata" -t elem -n "UseConfigurationSet" -v "true" "$tmp" || {
      rm -f "$tmp"
      error "$msg (3)"
      return 1
    }
  else
    xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -s "$setup" -t elem -n "UseConfigurationSet" -v "true" "$tmp" || {
      rm -f "$tmp"
      error "$msg (4)"
      return 1
    }
  fi

  result_count=$(getXMLNodeCount "$tmp" "$XML_COMPONENT_SETUP/u:UseConfigurationSet[normalize-space(.)='true']") || {
    rm -f "$tmp"
    return 1
  }

  if [ "$result_count" != "1" ]; then
    rm -f "$tmp"
    error "$msg (5)"
    return 1
  fi

  if ! replaceXMLAsset "$asset" "$tmp"; then
    error "Failed to replace the updated answer file!"
    return 1
  fi

  return 0
}

removeSharedFolder() {

  local script="$1"

  if ! disabled "${SHORTCUT:-}" && ! disabled "${SAMBA:-}"; then
    return 0
  fi

  removeSetupBlock "$script" "SHARED_FOLDER" || return 1

  return 0
}

removeLocalAccount() {

  local asset="$1"

  local accounts="$XML_COMPONENT_SHELL_OOBE/u:UserAccounts"

  if ! xmlstarlet ed -L \
    -N "$XML_NS_UNATTEND_ARG" -d "$accounts/u:LocalAccounts | $accounts/u:AdministratorPassword" "$asset"; then

    error "Failed to remove local account configuration from answer file!"
    return 1
  fi

  return 0
}

removeEmbeddedProductKeys() {

  local asset="$1"

  local product_keys='//u:ProductKey'
  local separator=$'\x1f' delete_xpath=""
  local count records position child_key direct_key

  count=$(xmlstarlet sel \
    -N "$XML_NS_UNATTEND_ARG" -T -t \
    -v "count($product_keys)" \
    "$asset") || return 1

  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  (( count == 0 )) && return 0

  records=$(xmlstarlet sel \
    -N "$XML_NS_UNATTEND_ARG" -T -t \
    -m "$product_keys" \
    -v 'position()' -o "$separator" \
    -v 'normalize-space(string((u:Key[normalize-space(.)])[1]))' -o "$separator" \
    -v 'normalize-space(string(text()[normalize-space()][1]))' -n \
    "$asset") || return 1

  while IFS="$separator" read -r position child_key direct_key; do

    [ -n "$position" ] || continue

    if [[ ! "$child_key" =~ ^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$ ]] &&
      [[ ! "$direct_key" =~ ^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$ ]]; then
      continue
    fi

    if [[ "$child_key" =~ ^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$ ]]; then
      [ -z "$delete_xpath" ] || delete_xpath+=" | "
      delete_xpath+="($product_keys)[$position]/u:Key[normalize-space(.)][1]"
    fi

    if [[ "$direct_key" =~ ^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$ ]]; then
      [ -z "$delete_xpath" ] || delete_xpath+=" | "
      delete_xpath+="($product_keys)[$position]/text()[normalize-space()][1]"
    fi

  done <<< "$records"

  [ -n "$delete_xpath" ] || return 0

  xmlstarlet ed -L -N "$XML_NS_UNATTEND_ARG" -d "$delete_xpath" "$asset" || return 1

  return 0
}

validateXMLSettings() {

  validateMembership || return 1
  validateComputerName "${HOST:-}" || return 1
  validateProductKey "${KEY:-}" || return 1
  validatePassword "${PASSWORD:-}" || return 1

  validateResolution "WIDTH" "$WIDTH" 320 || return 1
  validateResolution "HEIGHT" "$HEIGHT" 200 || return 1

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
  local blocks=(LOCAL_ACCOUNT PRODUCT_KEY SHARED_FOLDER OEM_SCRIPT)

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

  [ -z "$value" ] && return 0

  if [ "${#value}" -gt 15 ]; then
    error "The WORKGROUP variable cannot contain more than 15 characters!"
    return 1
  fi

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    error "The WORKGROUP variable cannot contain control characters!"
    return 1
  fi

  local safe
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
      invalid_message="The USERNAME variable contains characters that are not supported by Windows local accounts!" ;;

    "domain" )

      if [ -z "$value" ]; then
        error "The USERNAME variable does not contain a valid domain account name!"
        return 1
      fi

      maximum=256
      length_suffix=" for a domain account"
      invalid_message="The domain account name contains characters that are not supported by Windows unattended setup!" ;;

    * )
      return 1 ;;

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

      [[ "$type" == "domain" ]] && return 0

      error "The USERNAME value \"$value\" is reserved for a built-in Windows account!"
      return 1 ;;

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

validateLegacyEncoding() {

  local name="$1"
  local value="$2"
  local desc="${3:-}"

  local suffix=""
  [ -n "$desc" ] && suffix=" for $desc"

  if LC_ALL=C grep -q '[^ -~]' <<< "$value"; then
    error "The $name variable may only contain printable ASCII characters$suffix!"
    return 1
  fi

  return 0
}

prepareDomainAccount() {

  local domain="$1"

  local auth="${USERNAME:-}"
  local account="" qualifier=""

  if [ -z "$auth" ]; then
    error "The USERNAME variable must be specified when joining a domain!"
    return 1
  fi

  if [ -z "${PASSWORD:-}" ]; then
    error "The PASSWORD variable must be specified when joining a domain!"
    return 1
  fi

  validateDomainName "$domain" || return 1

  # Accept user or user@domain. DOMAIN\user is rejected because unattended
  # setup stores the domain separately from the credential username.
  if [[ "$auth" == *\\* ]]; then
    error "The USERNAME variable must use either \"user\" or \"user@domain\" format!"
    return 1
  fi

  case "$auth" in

    *@* )

      account="${auth%%@*}"
      qualifier="${auth#*@}"

      if [ -z "$account" ] ||
        [ -z "$qualifier" ] ||
        [[ "$qualifier" == *@* ]]; then

        error "The USERNAME variable does not contain a valid domain account name!"
        return 1
      fi

      validateDomainName "$qualifier" "USERNAME" || return 1

      if [[ "${qualifier,,}" != "${domain,,}" ]]; then
        error "The domain in the USERNAME variable must match the DOMAIN variable!"
        return 1
      fi ;;

    * )
      account="$auth" ;;

  esac

  validateUsername "$account" "domain" || return 1

  if [[ "${account,,}" == "docker" ]]; then
    error "The USERNAME variable must be changed from its default value when joining a domain!"
    return 1
  fi

  if [[ "$PASSWORD" == "admin" ]]; then
    error "The PASSWORD variable must be changed from its default value when joining a domain!"
    return 1
  fi

  printf '%s\n' "$account" "$auth"
  return 0
}

ensureUnattendedJoin() {

  local asset="$1"
  local arch="$2"

  local specialize="$XML_SETTINGS_SPECIALIZE"
  local component="$XML_COMPONENT_UNATTENDED_JOIN"
  local identification="$component/u:Identification"
  local counts settings_count component_count identification_count

  counts=$(xmlstarlet sel \
    -N "$XML_NS_UNATTEND_ARG" \
    -T -t \
    -v "count($specialize)" -o '|' \
    -v "count($component)" -o '|' -v "count($identification)" "$asset") || return 1

  IFS='|' read -r settings_count component_count identification_count <<< "$counts"

  [ "$settings_count" = "1" ] || return 1
  (( component_count <= 1 )) || return 1
  (( identification_count <= 1 )) || return 1

  # Templates may omit the join component entirely. Create it when absent, or
  # normalize its architecture and schema attributes when already present.
  if [ "$component_count" = "0" ]; then
    local created="($specialize/*[local-name()='component'])[last()]"

    xmlstarlet ed -L \
      -N "$XML_NS_UNATTEND_ARG" \
      -s "$specialize" -t elem -n 'component' \
      -i "$created" -t attr -n 'name' -v 'Microsoft-Windows-UnattendedJoin' \
      -i "$created" -t attr -n 'processorArchitecture' -v "$arch" \
      -i "$created" -t attr -n 'publicKeyToken' -v '31bf3856ad364e35' \
      -i "$created" -t attr -n 'language' -v 'neutral' \
      -i "$created" -t attr -n 'versionScope' -v 'nonSxS' \
      -s "$created" -t elem -n 'Identification' "$asset" || return 1

    return 0
  fi

  xmlstarlet ed -L \
    -N "$XML_NS_UNATTEND_ARG" \
    -i "${component}[not(@processorArchitecture)]" -t attr -n 'processorArchitecture' -v "$arch" \
    -u "$component/@processorArchitecture" -v "$arch" \
    -i "${component}[not(@publicKeyToken)]" -t attr -n 'publicKeyToken' -v '31bf3856ad364e35' \
    -u "$component/@publicKeyToken" -v '31bf3856ad364e35' \
    -i "${component}[not(@language)]" -t attr -n 'language' -v 'neutral' \
    -u "$component/@language" -v 'neutral' \
    -i "${component}[not(@versionScope)]" -t attr -n 'versionScope' -v 'nonSxS' \
    -u "$component/@versionScope" -v 'nonSxS' \
    -s "${component}[not(u:Identification)]" -t elem -n 'Identification' "$asset" || return 1

  return 0
}

encodeUnattendPassword() {

  local password="$1"
  local suffix="$2"

  # Windows unattend password fields use a field-specific suffix before
  # UTF-16LE/Base64 encoding; this is obfuscation rather than encryption.
  printf '%s' "${password}${suffix}" | iconv -f utf-8 -t utf-16le | base64 -w 0

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

ensureXMLDefaultNamespace() {

  local asset="$1"

  local default declared count root

  root=$(xmlstarlet sel -N "$XML_NS_UNATTEND_ARG" -T -t -v 'count(/u:unattend)' "$asset") || return 1
  [ "$root" = "1" ] || return 1

  declared=$(xmlstarlet sel -T -t -v 'count(/*/namespace::*[name()=""])' "$asset") || return 1
  default=$(xmlstarlet sel -T -t -v 'string(/*/namespace::*[name()=""])' -o '|' "$asset") || return 1
  default="${default%|}"

  if [ "$declared" = "1" ]; then
    [ "$default" = "$XML_NS_UNATTEND" ] && return 0
    return 1
  fi

  [ "$declared" = "0" ] || return 1

  count=$(xmlstarlet sel -T -t -v "count(//*[namespace-uri()=''])" "$asset") || return 1
  [ "$count" = "0" ] || return 1

  xmlstarlet ed -L \
    -N "$XML_NS_UNATTEND_ARG" \
    -i '/u:unattend' -t attr -n 'xmlns' -v "$XML_NS_UNATTEND" \
    "$asset" || return 1

  return 0
}

getXMLNodeCount() {

  local asset="$1"
  local xpath="$2"

  xmlstarlet sel -N "$XML_NS_UNATTEND_ARG" -T -t -v "count($xpath)" "$asset"
}

validateUniqueXMLNodes() {

  local asset="$1"
  shift

  local xpath count

  for xpath in "$@"; do
    count=$(getXMLNodeCount "$asset" "$xpath") || return 1
    (( count <= 1 )) || return 1
  done

  return 0
}

copyXMLAsset() {

  local asset="$1"
  local copy

  if ! copy=$(mktemp "${asset}.XXXXXX") ||
    ! cp -p -- "$asset" "$copy"; then

    rm -f "${copy:-}"
    return 1
  fi

  printf '%s' "$copy"
  return 0
}

replaceXMLAsset() {

  local asset="$1"
  local tmp="$2"

  if ! chmod --reference="$asset" "$tmp" ||
    ! mv -f "$tmp" "$asset"; then

    rm -f "$tmp"
    return 1
  fi

  return 0
}

markGeneratedXML() {

  local file="$1"
  local marker='<!-- generated-answer-file: do not reuse as a template -->'
  local first

  [ -s "$file" ] || return 1

  if ! first=$(head -n 1 "$file"); then
    error "Failed to inspect generated answer file: $file"
    return 1
  fi

  if [[ "$first" == "<?xml"* ]]; then
    sed -i "1a$marker" "$file" || return 1
  else
    sed -i "1i$marker" "$file" || return 1
  fi

  return 0
}

removeGeneratedXML() {

  local file="$1"
  local header

  [ -n "$file" ] || return 0
  [ -f "$file" ] || return 0

  if ! header=$(head -n 5 "$file"); then
    error "Failed to inspect answer file: $file"
    return 1
  fi

  grep -Fqi 'generated-answer-file' <<< "$header" || return 0

  if ! rm -f "$file"; then
    error "Failed to remove generated answer file: $file"
    return 1
  fi

  return 0
}

prepareSetupScript() {

  local asset="$1"
  local stage="$2"

  local staged=""
  staged=$(stageSetupScript "$asset" "$stage") || return 1

  [ -n "$staged" ] || return 0

  updateSetupScript "$staged" "$asset" || return 1
  finalizeSetupScript "$staged" || return 1

  return 0
}

updateSetupScript() {

  local script="$1"
  local asset="$2"

  local domain="${DOMAIN:-}"
  local user="${USERNAME:-}"
  local content id ps_user

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

    # Set-LocalUser is unavailable on older releases, which still require
    # the equivalent WMIC command.

    case "${id,,}" in
      "win10"* | "win11"* | "win2016"* | "win2019"* | "win2022"* | "win2025"* )
        ps_user="${user//\'/\'\'}"
        printf -v content '%s\n%s' \
          'rem Prevent the local user password from expiring.' \
          "powershell.exe -ExecutionPolicy Unrestricted -NoLogo -NoProfile -NonInteractive -Command \"Set-LocalUser -Name '$ps_user' -PasswordNeverExpires 1\""
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

  # Generated edition-specific answer files inherit the
  # script belonging to their generic source template.
  if [[ "$normal" == *-* ]]; then
    candidates+=("$dir/${normal%%-*}.cmd")
  fi

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

  local source target
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

  printf '%s' "$target"
  return 0
}

rewriteSetupBlock() {

  local file="$1"
  local block="$2"
  local action="$3"
  local content="${4:-}"

  local begin="rem BEGIN $block"
  local end="rem END $block"
  local line inside=0 tmp

  case "$action" in
    "replace" | "remove" ) ;;
    * ) return 1 ;;
  esac

  validateSetupBlock "$file" "$block" || return 1

  # Rewrite through a temporary file so malformed markers or interrupted writes
  # cannot leave a partially modified setup script.
  if ! tmp=$(mktemp "${file}.XXXXXX"); then
    error "Failed to create temporary setup script!"
    return 1
  fi

  while IFS= read -r line || [ -n "$line" ]; do

    if [ "$line" = "$begin" ]; then

      if [ "$action" = "replace" ]; then
        if ! printf '%s\n' "$line" >> "$tmp" ||
          ! printf '%s\n' "$content" >> "$tmp"; then
          rm -f "$tmp"
          return 1
        fi
      fi

      inside=1
      continue
    fi

    if [ "$line" = "$end" ]; then

      inside=0

      if [ "$action" = "replace" ]; then
        if ! printf '%s\n' "$line" >> "$tmp"; then
          rm -f "$tmp"
          return 1
        fi
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
    error "Failed to $action the $block block in setup script: $file"
    return 1
  fi

  return 0
}

replaceSetupBlock() {

  rewriteSetupBlock "$1" "$2" "replace" "$3"
}

removeSetupBlock() {

  rewriteSetupBlock "$1" "$2" "remove"
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

addSIFEntry() {

  local file="$1"
  local section="$2"
  local entry="$3"

  local header="[$section]"
  local line ending="lf"

  line=$(grep -Fnx -m 1 "$header" "$file" | cut -d: -f1) || line=""

  if [ -z "$line" ]; then
    line=$(grep -Fnx -m 1 "$header"$'\r' "$file" | cut -d: -f1) || line=""
    ending="crlf"
  fi

  if [ -z "$line" ]; then
    error "Failed to locate section \"$header\" in \"$file\" !"
    return 1
  fi

  if grep -Fqx "$entry" "$file" || grep -Fqx "$entry"$'\r' "$file"; then
    return 0
  fi

  if [[ "$ending" == "crlf" ]]; then
    printf '%s\r\n' "$entry"
  else
    printf '%s\n' "$entry"
  fi | sed -i "${line}r /dev/stdin" "$file" || return 1

  return 0
}

patchStorageDriver() {

  local file="$1"
  local arch="$2"

  # Text-mode setup reads TXTSETUP.SIF before Plug and Play is available, so the
  # VirtIO storage service and hardware IDs must be registered there explicitly.
  addSIFEntry "$file" "SCSI.Load" 'viostor=viostor.sys,4' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'viostor.sys=1,,,,,,4_,4,1,,,1,4' || return 1
  addSIFEntry "$file" "SCSI" 'viostor="Red Hat VirtIO SCSI Disk Device"' || return 1
  addSIFEntry "$file" "HardwareIdsDatabase" 'PCI\VEN_1AF4&DEV_1001&SUBSYS_00000000="viostor"' || return 1
  addSIFEntry "$file" "HardwareIdsDatabase" 'PCI\VEN_1AF4&DEV_1001&SUBSYS_00020000="viostor"' || return 1
  addSIFEntry "$file" "HardwareIdsDatabase" 'PCI\VEN_1AF4&DEV_1001&SUBSYS_00021AF4="viostor"' || return 1

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

  addSIFEntry "$file" "SCSI.Load" 'iaStor=iaStor.sys,4' || return 1
  addSIFEntry "$file" "FileFlags" 'iaStor.sys = 16' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaStor.cat = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaStor.inf = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaStor.sys = 1,,,,,,4_,4,1,,,1,4' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaStor.sys = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaahci.cat = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaAHCI.inf = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SCSI" 'iaStor="Intel(R) SATA RAID/AHCI Controller"' || return 1
  addSIFEntry "$file" "HardwareIdsDatabase" 'PCI\VEN_8086&DEV_2922&CC_0106="iaStor"' || return 1

  return 0
}

addLegacyDrivers() {

  local dir="$1"
  local target="$2"
  local driver="$3"
  local arch="$4"
  local drivers="$5"

  local msg="Adding drivers to image..."
  info "$msg" && html "$msg"

  extractDrivers "$drivers" || return 1
  copyStorageDriver "$dir" "$target" "$driver" "$arch" "$drivers" || return 1
  addNetworkDriver "$dir" "$driver" "$arch" "$drivers" || return 1

  local file
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

  local setup pid file block
  setup=$(find "$target" -maxdepth 1 -type f -iname setupp.ini -print -quit) || return 1

  [[ -n "$setup" ]] || return 0
  [[ -z "$KEY" ]] || return 0

  pid=$(<"$setup") || return 1
  pid="${pid%$'\r'}"

  if [[ "$driver" == "2k" ]]; then
    [ "${#pid}" -ge 3 ] || return 0
    echo "${pid::-3}270" > "$setup" || :
    return 0
  fi

  if [[ "$pid" == *"270" ]]; then
    warn "this version of $desc requires a volume license key (VLK), it will ask for one during installation."
    return 0
  fi

  file=$(find "$target" -maxdepth 1 -type f -iname PID.INF -print -quit) || return 1

  if [[ -n "$file" ]]; then

    local key=""

    # Prefer a staging or OEM key already shipped on the media before falling
    # back to Microsoft's documented generic installation keys.
    if [[ "$driver" == "2k3" ]]; then

      block=$(grep -i -A 2 "StagingKey" "$file") || block=""

      if [ -n "$block" ]; then
        key=$(printf '%s\n' "$block" | tail -n 2 | head -n 1) || key=""
      fi

    else

      key="${pid: -8:5}"

      if [[ "${pid^^}" == *"OEM" ]]; then

        block=$(grep -i -A 2 "$key" "$file") || block=""

      else

        block=$(grep -i -m 1 -A 2 "$key" "$file") || block=""

      fi

      if [ -n "$block" ]; then
        key=$(printf '%s\n' "$block" | tail -n 2 | head -n 1) || key=""
      fi

      key="${key#*= }"

    fi

    if [ -n "$key" ]; then
      key="${key%$'\r'}"
      [[ "${#key}" == "29" ]] && KEY="$key"
    fi

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
      fi ;;

    "2k3" )

      if [[ "${arch,,}" == "x86" ]]; then
        # Windows Server 2003 Standard x86 generic trial key (no activation)
        KEY="QKDCQ-TP2JM-G4MDG-VR6F2-P9C48"
      else
        # Windows Server 2003 Standard x64 generic trial key (no activation)
        KEY="P4WJG-WK3W7-3HM8W-RWHCK-8JTRY"
      fi ;;

  esac

  if [ "${#pid}" -ge 3 ]; then
    echo "${pid::-3}000" > "$setup" || :
  fi

  return 0
}

writeCommand() {

  local install="$1"

  [ -f "$install" ] || return 0

  if enabled "${LOG:-}"; then
    printf '%s' "\"Script\"=\"cmd /C start \\\"Install\\\" cmd.exe /D /C \\\"\\\"C:\\\\OEM\\\\install.bat\\\" > \\\"C:\\\\OEM\\\\install.log\\\" 2>&1\\\"\""
  else
    printf '%s' "\"Script\"=\"cmd /C start \\\"Install\\\" cmd.exe /D /C \\\"\\\"C:\\\\OEM\\\\install.bat\\\"\\\"\""
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
      '    OEMSkipRegional=1' '    OemSkipWelcome=1' "    AdminPassword=\"$sifPassword\"" '    TimeZone=0'

    if disabled "$AUTOLOGIN"; then
      printf '%s\n' '    AutoLogon=No'
    else
      printf '%s\n' \
        '    AutoLogon=Yes' '    AutoLogonCount=65432'
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
      '    Search_Page = http://www.google.com' '' '[TerminalServices]' '    AllowConnections=1' ''
  } | unix2dos > "$target/WINNT.SIF" || return 1

  if [[ "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[Components]' \
        '    TerminalServer=On' '' '[LicenseFilePrintData]' '    AutoMode=PerServer' '    AutoUsers=5' ''
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
      '"Desktopchanged"="1"' '' '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]'

    if disabled "$AUTOLOGIN"; then
      printf '%s\n' '"AutoAdminLogon"="0"'
    else
      printf '%s\n' \
        '"AutoAdminLogon"="1"' "\"DefaultUserName\"=\"$regUsername\"" "\"DefaultPassword\"=\"$regPassword\""
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
        '[HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Runonce]' '"^SetupICWDesktop"=-' ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  if [[ "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\srvWiz]' \
        '@=dword:00000000' \
        '' \
        '[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\ServerOOBE\SecurityOOBE]' \
        '"DontLaunchSecurityOOBE"=dword:00000000' ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  return 0
}

writeVBS() {

  local dir="$1"
  local username="$2"
  local shortcut="$3"

  # Locate the built-in Administrator by its RID 500 SID rather than its
  # localized display name, then rename that account to the requested username.

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
      '    End If' '  End If' 'Next' '' "Call Domain.MoveHere(LocalAdminADsPath, \"$username\")" ''

    if enabled "$shortcut"; then
      printf '%s\n' \
        'Set oLink = WshShell.CreateShortcut(WshShell.SpecialFolders("Desktop") & "\Shared.lnk")' \
        'With oLink' '  .TargetPath = "\\host.lan\Data"' '  .Save' 'End With' 'Set oLink = Nothing' ''
    fi
  } | unix2dos > "$dir/\$OEM\$/install.vbs" || return 1

  {
    printf '%s\n' \
      '[COMMANDS]' '"REGEDIT /s install.reg"' '"Wscript install.vbs"' ''
  } | unix2dos > "$dir/\$OEM\$/cmdlines.txt" || return 1

  return 0
}

disableAutoReboot() {

  local target="$1"

  local file rc=0
  local pattern='^[[:space:]]*HKLM[[:space:]]*,[[:space:]]*"SYSTEM\\CurrentControlSet\\Control\\CrashControl"[[:space:]]*,[[:space:]]*"AutoReboot"[[:space:]]*,[[:space:]]*[^,]*,'

  file=$(find "$target" -maxdepth 1 -type f -iname HIVESYS.INF -print -quit) || return 1

  if [ -z "$file" ]; then
    error "The file HIVESYS.INF could not be found!"
    return 1
  fi

  # Keep setup crashes visible instead of immediately rebooting into an
  # opaque installation loop.
  grep -Eqi "${pattern}[[:space:]]*[^,;[:space:]]+" "$file" || rc=$?

  case "$rc" in
    0 )
      sed -i -E "s|(${pattern})[[:space:]]*[^,;[:space:]]+|\\1 0|I" "$file" || :
      ;;
    1 )
      printf '%s\n' \
        'HKLM,"SYSTEM\CurrentControlSet\Control\CrashControl","AutoReboot",0x00010001,0' |
        unix2dos >> "$file" || :
      ;;
  esac

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

  # Legacy media uses directory names rather than metadata to identify the
  # architecture and the text-mode setup source tree.
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
      "$oem_dir" -maxdepth 1 -type f -iname install.bat -print -quit
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

  if [[ "$driver" == "2k" ]]; then
    validateLegacyEncoding "APP" "$APP" "$desc" || return 1
    validateLegacyEncoding "ENGINE" "$ENGINE" "$desc" || return 1
  fi

  XHEX=$(printf '%08x\n' "$((10#$WIDTH))") || return 1
  YHEX=$(printf '%08x\n' "$((10#$HEIGHT))") || return 1

  local username="${USERNAME:-Docker}"
  local password="${PASSWORD:-admin}"
  local workgroup="${WORKGROUP:-WORKGROUP}"

  local sifHost sifUsername sifPassword sifOrganization sifWorkgroup
  local regUsername regPassword

  validateLegacyUsername "$username" "$desc" || return 1
  validatePassword "$password" "$desc" || return 1

  if [[ "$driver" == "2k" ]]; then
    validateLegacyEncoding "USERNAME" "$username" "$desc" || return 1
    validateLegacyEncoding "PASSWORD" "$password" "$desc" || return 1
    validateLegacyEncoding "WORKGROUP" "$workgroup" "$desc" || return 1
  fi

  # WINNT.SIF and .reg files use different escaping rules, so prepare their
  # values independently before generating either file.
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
    "$product" "$sifHost" "$sifUsername" "$sifPassword" "$sifOrganization" "$sifWorkgroup" || return 1

  writeRegistry "$dir" "$shortcut" "$oem" "$regUsername" "$regPassword" || return 1

  appendRegistry "$dir" "$driver" || return 1
  writeVBS "$dir" "$username" "$shortcut" || return 1

  return 0
}

return 0
