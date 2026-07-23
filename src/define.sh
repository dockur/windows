#!/usr/bin/env bash
set -Eeuo pipefail

: "${KEY:=""}"
: "${HOST:=""}"
: "${WIDTH:=""}"
: "${HEIGHT:=""}"
: "${VERIFY:=""}"
: "${DOMAIN:=""}"
: "${REGION:=""}"
: "${EDITION:=""}"
: "${MANUAL:=""}"
: "${REMOVE:=""}"
: "${VERSION:=""}"
: "${COMMAND:=""}"
: "${DETECTED:=""}"
: "${KEYBOARD:=""}"
: "${LANGUAGE:=""}"
: "${USERNAME:=""}"
: "${PASSWORD:=""}"
: "${SHORTCUT:=""}"
: "${DOMAIN_OU:=""}"
: "${WORKGROUP:=""}"
: "${AUTOLOGIN:=""}"

# Sanitize variables
KEY=$(strip "$KEY")
HOST=$(strip "$HOST")
WIDTH=$(strip "$WIDTH")
HEIGHT=$(strip "$HEIGHT")
DOMAIN=$(strip "$DOMAIN")
REGION=$(strip "$REGION")
COMMAND=$(strip "$COMMAND")
EDITION=$(strip "$EDITION")
KEYBOARD=$(strip "$KEYBOARD")
LANGUAGE=$(strip "$LANGUAGE")
USERNAME=$(strip "$USERNAME")
DOMAIN_OU=$(strip "$DOMAIN_OU")
WORKGROUP=$(strip "$WORKGROUP")

MIRRORS=3
SUGGEST=""

parseVersion() {

  VERSION=$(strip "$VERSION")
  [ -z "$VERSION" ] && VERSION="win11"

  case "${VERSION,,}" in
    "11" | "11p" | "win11" | "pro11" | "win11p" | "windows11" | "windows 11" )
      VERSION="win11x64"
      ;;
    "11e" | "win11e" | "windows11e" | "windows 11e" )
      VERSION="win11x64-enterprise-eval"
      ;;
    "11l" | "11ltsc" | "ltsc11" | "win11l" | "win11-ltsc" | "win11x64-ltsc" )
      VERSION="win11x64-enterprise-ltsc-eval"
      SUGGEST="win11x64-ltsc"
      ;;
    "11i" | "11iot" | "iot11" | "win11i" | "win11-iot" | "win11x64-iot" )
      VERSION="win11x64-enterprise-iot-eval"
      SUGGEST="win11x64-iot"
      ;;
    "10" | "10p" | "win10" | "pro10" | "win10p" | "windows10" | "windows 10" )
      VERSION="win10x64"
      ;;
    "10e" | "win10e" | "windows10e" | "windows 10e" )
      VERSION="win10x64-enterprise-eval"
      ;;
    "10l" | "10ltsc" | "ltsc10" | "win10l" | "win10-ltsc" | "win10x64-ltsc" )
      VERSION="win10x64-enterprise-ltsc-eval"
      SUGGEST="win10x64-ltsc"
      ;;
    "10i" | "10iot" | "iot10" | "win10i" | "win10-iot" | "win10x64-iot" )
      VERSION="win10x64-enterprise-iot-eval"
      SUGGEST="win10x64-iot"
      ;;
    "8" | "8p" | "81" | "81p" | "pro8" | "8.1" | "win8" | "win8p" | "win81" | "win81p" | "windows 8" )
      VERSION="win81x64"
      ;;
    "8e" | "81e" | "8.1e" | "win8e" | "win81e" | "windows 8e" )
      VERSION="win81x64-enterprise-eval"
      ;;
    "7" | "win7" | "windows7" | "windows 7" )
      VERSION="win7x64"
      SUGGEST="win7x64-ultimate"
      ;;
    "7u" | "win7u" | "windows7u" | "windows 7u" )
      VERSION="win7x64-ultimate"
      ;;
    "7e" | "win7e" | "windows7e" | "windows 7e" )
      VERSION="win7x64-enterprise"
      ;;
    "7x86" | "win7x86" | "win732" | "windows7x86" )
      VERSION="win7x86"
      SUGGEST="win7x86-ultimate"
      ;;
    "7ux86" | "7u32" | "win7x86-ultimate" )
      VERSION="win7x86-ultimate"
      ;;
    "7ex86" | "7e32" | "win7x86-enterprise" )
      VERSION="win7x86-enterprise"
      ;;
    "vista" | "vs" | "6" | "winvista" | "windowsvista" | "windows vista" )
      VERSION="winvistax64"
      SUGGEST="winvistax64-ultimate"
      ;;
    "vistu" | "vu" | "6u" | "winvistu" )
      VERSION="winvistax64-ultimate"
      ;;
    "viste" | "ve" | "6e" | "winviste" )
      VERSION="winvistax64-enterprise"
      ;;
    "vistax86" | "vista32" | "6x86" | "winvistax86" | "windowsvistax86" )
      VERSION="winvistax86"
      SUGGEST="winvistax86-ultimate"
      ;;
    "vux86" | "vu32" | "winvistax86-ultimate" )
      VERSION="winvistax86-ultimate"
      ;;
    "vex86" | "ve32" | "winvistax86-enterprise" )
      VERSION="winvistax86-enterprise"
      ;;
    "xp" | "xp32" | "xpx86" | "5" | "5x86" | "winxp" | "winxp86" | "windowsxp" | "windows xp" )
      VERSION="winxpx86"
      ;;
    "xp64" | "xpx64" | "5x64" | "winxp64" | "winxpx64" | "windowsxp64" | "windowsxpx64" )
      VERSION="winxpx64"
      ;;
    "2k" | "2000" | "win2k" | "win2000" | "windows2k" | "windows2000" )
      VERSION="win2kx86"
      ;;
    "25" | "2025" | "win25" | "win2025" | "windows2025" | "windows 2025" )
      VERSION="win2025-eval"
      ;;
    "22" | "2022" | "win22" | "win2022" | "windows2022" | "windows 2022" )
      VERSION="win2022-eval"
      ;;
    "19" | "2019" | "win19" | "win2019" | "windows2019" | "windows 2019" )
      VERSION="win2019-eval"
      ;;
    "16" | "2016" | "win16" | "win2016" | "windows2016" | "windows 2016" )
      VERSION="win2016-eval"
      ;;
    "hv" | "hyperv" | "hyper v" | "hyper-v" | "19hv" | "2019hv" | "win2019hv" )
      VERSION="win2019-hv"
      ;;
    "2012" | "2012r2" | "win2012" | "win2012r2" | "windows2012" | "windows 2012" )
      VERSION="win2012r2-eval"
      ;;
    "2008" | "2008r2" | "win2008" | "win2008r2" | "windows2008" | "windows 2008" )
      VERSION="win2008r2"
      ;;
    "2003" | "2003r2" | "win2003" | "win2003r2" | "windows2003" | "windows 2003" )
      VERSION="win2003r2"
      ;;
    "nano11" | "nano 11" )
      VERSION="nano11"
      ;;
    "core11" | "core 11" )
      VERSION="core11"
      ;;
    "tiny11" | "tiny 11" )
      VERSION="tiny11"
      ;;
    "tiny10" | "tiny 10" )
      VERSION="tiny10"
      SUGGEST="win10x64-ltsc"
      ;;
  esac

  if [ -z "$SUGGEST" ]; then
    case "${VERSION,,}" in
      *"-enterprise-ltsc-eval" )
        SUGGEST="${VERSION%-enterprise-ltsc-eval}-ltsc" ;;
      *"-enterprise-iot-eval" )
        SUGGEST="${VERSION%-enterprise-iot-eval}-iot" ;;
      *"-eval" )
        SUGGEST="${VERSION%-eval}" ;;
    esac
  fi

  return 0
}

getLanguage() {

  local id="$1"
  local ret="$2"
  local lang=""
  local desc=""
  local short=""
  local culture=""

  case "${id,,}" in
    "ar" | "ar-"* )
      short="ar"
      lang="Arabic"
      culture="ar-SA" ;;
    "bg" | "bg-"* )
      short="bg"
      lang="Bulgarian"
      culture="bg-BG" ;;
    "cs" | "cs-"* | "cz" | "cz-"* )
      short="cs"
      lang="Czech"
      culture="cs-CZ" ;;
    "da" | "da-"* | "dk" | "dk-"* )
      short="da"
      lang="Danish"
      culture="da-DK" ;;
    "de" | "de-"* )
      short="de"
      lang="German"
      culture="de-DE" ;;
    "el" | "el-"* | "gr" | "gr-"* )
      short="el"
      lang="Greek"
      culture="el-GR" ;;
    "gb" | "en-gb" )
      short="en-gb"
      lang="English International"
      desc="English"
      culture="en-GB" ;;
    "en" | "en-"* )
      short="en"
      lang="English"
      culture="en-US" ;;
    "mx" | "es-mx" )
      short="mx"
      lang="Spanish (Mexico)"
      desc="Spanish"
      culture="es-MX" ;;
    "es" | "es-"* )
      short="es"
      lang="Spanish"
      culture="es-ES" ;;
    "et" | "et-"* )
      short="et"
      lang="Estonian"
      culture="et-EE" ;;
    "fi" | "fi-"* )
      short="fi"
      lang="Finnish"
      culture="fi-FI" ;;
    "ca" | "fr-ca" )
      short="ca"
      lang="French Canadian"
      desc="French"
      culture="fr-CA" ;;
    "fr" | "fr-"* )
      short="fr"
      lang="French"
      culture="fr-FR" ;;
    "he" | "he-"* | "il" | "il-"* )
      short="he"
      lang="Hebrew"
      culture="he-IL" ;;
    "hr" | "hr-"* | "cr" | "cr-"* )
      short="hr"
      lang="Croatian"
      culture="hr-HR" ;;
    "hu" | "hu-"* )
      short="hu"
      lang="Hungarian"
      culture="hu-HU" ;;
    "it" | "it-"* )
      short="it"
      lang="Italian"
      culture="it-IT" ;;
    "ja" | "ja-"* | "jp" | "jp-"* )
      short="ja"
      lang="Japanese"
      culture="ja-JP" ;;
    "ko" | "ko-"* | "kr" | "kr-"* )
      short="ko"
      lang="Korean"
      culture="ko-KR" ;;
    "lt" | "lt-"* )
      short="lt"
      lang="Lithuanian"
      culture="lt-LT" ;;
    "lv" | "lv-"* )
      short="lv"
      lang="Latvian"
      culture="lv-LV" ;;
    "nb" | "nb-"* | "nn" | "nn-"* | "no" | "no-"* )
      short="no"
      lang="Norwegian"
      culture="nb-NO" ;;
    "nl" | "nl-"* )
      short="nl"
      lang="Dutch"
      culture="nl-NL" ;;
    "pl" | "pl-"* )
      short="pl"
      lang="Polish"
      culture="pl-PL" ;;
    "br" | "pt-br" )
      short="pt"
      lang="Brazilian Portuguese"
      desc="Portuguese"
      culture="pt-BR" ;;
    "pt" | "pt-"* )
      short="pp"
      lang="Portuguese"
      culture="pt-BR" ;;
    "ro" | "ro-"* )
      short="ro"
      lang="Romanian"
      culture="ro-RO" ;;
    "ru" | "ru-"* )
      short="ru"
      lang="Russian"
      culture="ru-RU" ;;
    "sk" | "sk-"* )
      short="sk"
      lang="Slovak"
      culture="sk-SK" ;;
    "sl" | "sl-"* | "si" | "si-"* )
      short="sl"
      lang="Slovenian"
      culture="sl-SI" ;;
    "sr" | "sr-"* )
      short="sr"
      lang="Serbian Latin"
      desc="Serbian"
      culture="sr-Latn-RS" ;;
    "sv" | "sv-"* | "se" | "se-"* )
      short="sv"
      lang="Swedish"
      culture="sv-SE" ;;
    "th" | "th-"* )
      short="th"
      lang="Thai"
      culture="th-TH" ;;
    "tr" | "tr-"* )
      short="tr"
      lang="Turkish"
      culture="tr-TR" ;;
    "ua" | "ua-"* | "uk" | "uk-"* )
      short="uk"
      lang="Ukrainian"
      culture="uk-UA" ;;
    "hk" | "zh-hk" | "cn-hk" )
      short="hk"
      lang="Chinese (Traditional)"
      desc="Chinese HK"
      culture="zh-TW" ;;
    "tw" | "zh-tw" | "cn-tw" )
      short="tw"
      lang="Chinese (Traditional)"
      desc="Chinese TW"
      culture="zh-TW" ;;
    "zh" | "zh-"* | "cn" | "cn-"* )
      short="cn"
      lang="Chinese (Simplified)"
      desc="Chinese"
      culture="zh-CN" ;;
  esac

  [ -z "$desc" ] && desc="$lang"

  case "${ret,,}" in
    "desc" ) echo "$desc" ;;
    "name" ) echo "$lang" ;;
    "code" ) echo "$short" ;;
    "culture" ) echo "$culture" ;;
    *) echo "$desc";;
  esac

  return 0
}

parseLanguage() {

  REGION="${REGION//_/-}"
  KEYBOARD="${KEYBOARD//_/-}"
  LANGUAGE="${LANGUAGE//_/-}"

  [ -z "$LANGUAGE" ] && LANGUAGE="en"

  case "${LANGUAGE,,}" in
    "arabic" | "arab" ) LANGUAGE="ar" ;;
    "bulgarian" | "bu" ) LANGUAGE="bg" ;;
    "chinese" | "cn" ) LANGUAGE="zh" ;;
    "croatian" | "cr" | "hrvatski" ) LANGUAGE="hr" ;;
    "czech" | "cz" | "cesky" ) LANGUAGE="cs" ;;
    "danish" | "dk" | "danske" ) LANGUAGE="da" ;;
    "dutch" | "nederlands" ) LANGUAGE="nl" ;;
    "english" ) LANGUAGE="en" ;;
    "british" | "gb" ) LANGUAGE="en-gb" ;;    "estonian" | "eesti" ) LANGUAGE="et" ;;
    "finnish" | "suomi" ) LANGUAGE="fi" ;;
    "french" | "français" | "francais" ) LANGUAGE="fr" ;;
    "german" | "deutsch" ) LANGUAGE="de" ;;
    "greek" | "gr" ) LANGUAGE="el" ;;
    "hebrew" | "il" ) LANGUAGE="he" ;;
    "hungarian" | "magyar" ) LANGUAGE="hu" ;;
    "italian" | "italiano" ) LANGUAGE="it" ;;
    "japanese" | "jp" ) LANGUAGE="ja" ;;
    "korean" | "kr" ) LANGUAGE="ko" ;;
    "latvian" | "latvijas" ) LANGUAGE="lv" ;;
    "lithuanian" | "lietuvos" ) LANGUAGE="lt" ;;
    "norwegian" | "no" | "nb" | "norsk" ) LANGUAGE="nn" ;;
    "polish" | "polski" ) LANGUAGE="pl" ;;
    "portuguese" | "pt" | "br" ) LANGUAGE="pt-br" ;;
    "português" | "portugues" ) LANGUAGE="pt-br" ;;
    "romanian" | "română" | "romana" ) LANGUAGE="ro" ;;
    "russian" | "ruski" ) LANGUAGE="ru" ;;
    "serbian" | "serbian latin" ) LANGUAGE="sr" ;;
    "slovak" | "slovenský" | "slovensky" ) LANGUAGE="sk" ;;
    "slovenian" | "si" | "slovenski" ) LANGUAGE="sl" ;;
    "spanish" | "espanol" | "español" ) LANGUAGE="es" ;;
    "swedish" | "se" | "svenska" ) LANGUAGE="sv" ;;
    "turkish" | "türk" | "turk" ) LANGUAGE="tr" ;;
    "thai" ) LANGUAGE="th" ;;
    "ukrainian" | "ua" ) LANGUAGE="uk" ;;
  esac

  local culture
  culture=$(getLanguage "$LANGUAGE" "culture")
  [ -n "$culture" ] && return 0

  error "Invalid LANGUAGE specified, value \"$LANGUAGE\" is not recognized!"
  return 1
}

printVersion() {

  local id="$1"
  local desc="$2"

  case "${id,,}" in
    "tiny11"* ) desc="Tiny 11" ;;
    "tiny10"* ) desc="Tiny 10" ;;
    "core11"* ) desc="Core 11" ;;
    "nano11"* ) desc="Nano 11" ;;
    "win7"* ) desc="Windows 7" ;;
    "win8"* ) desc="Windows 8" ;;
    "win10"* ) desc="Windows 10" ;;
    "win11"* ) desc="Windows 11" ;;
    "winxp"* ) desc="Windows XP" ;;
    "win9x"* ) desc="Windows ME" ;;
    "win98"* ) desc="Windows 98" ;;
    "win95"* ) desc="Windows 95" ;;
    "win2k"* ) desc="Windows 2000" ;;
    "winvista"* ) desc="Windows Vista" ;;
    "win2019-hv"* ) desc="Hyper-V Server" ;;
    "win2003"* ) desc="Windows Server 2003" ;;
    "win2008"* ) desc="Windows Server 2008" ;;
    "win2012"* ) desc="Windows Server 2012" ;;
    "win2016"* ) desc="Windows Server 2016" ;;
    "win2019"* ) desc="Windows Server 2019" ;;
    "win2022"* ) desc="Windows Server 2022" ;;
    "win2025"* ) desc="Windows Server 2025" ;;
  esac

  if [ -z "$desc" ]; then
    desc="Windows"
    [[ "${PLATFORM,,}" != "x64" ]] && desc+=" for ${PLATFORM}"
  fi

  echo "$desc"
  return 0
}

printVariant() {

  local id="$1"
  local desc="$2"

  desc=$(printVersion "$id" "$desc") || return 1

  case "${id,,}" in
    *"-iot" | *"-iot-eval" )
      desc+=" IoT"
      ;;
    *"-ltsc" | *"-ltsc-eval" )
      desc+=" LTSC"
      ;;
    *"-enterprise" | *"-enterprise-eval" )
      desc+=" Enterprise"
      ;;
  esac

  [[ "${id,,}" == *"-eval" ]] && desc+=" (Evaluation)"

  echo "$desc"
  return 0
}

printEdition() {

  local id="$1"
  local desc="$2"
  local result=""
  local edition=""

  result=$(printVersion "$id" "x")
  [[ "$result" == "x" ]] && echo "$desc" && return 0

  case "${id,,}" in
    *"-home" )
      edition="Home"
      ;;
    *"-starter" )
      edition="Starter"
      ;;
    *"-ultimate" )
      edition="Ultimate"
      ;;
    *"-enterprise" | *"-enterprise-eval" )
      edition="Enterprise"
      ;;
    *"-education" )
      edition="Education"
      ;;
    *"-hv" )
      edition="2019"
      ;;
    *"-iot" | *"-iot-eval" )
      edition="IoT Enterprise LTSC"
      ;;
    *"-ltsc" | *"-ltsc-eval" )
      edition="Enterprise LTSC"
      ;;
    "win7"* )
      edition="Professional"
      ;;
    "win8"* | "win10"* | "win11"* )
      edition="Pro"
      ;;
    "winxp"* )
      edition="Professional"
      ;;
    "winvista"* )
      edition="Business"
      ;;
    "win2025"* | "win2022"* | "win2019"* | "win2016"* | "win2012"* | "win2008"* | "win2003"* )
      case "${EDITION^^}" in
        *"DATACENTER"* ) edition="Datacenter" ;;
        "CORE" | "STANDARDCORE" ) edition="Core" ;;
        * ) edition="Standard" ;;
      esac
      ;;
  esac

  [ -n "$edition" ] && result+=" $edition"
  [[ "${id,,}" == *"-eval" ]] && result+=" (Evaluation)"

  echo "$result"
  return 0
}

fromFile() {

  local id=""
  local desc="$1"
  local file="${1,,}"
  local arch="${PLATFORM,,}"

  file="${file//-/_}"
  file="${file// /_}"

  case "$file" in
    *"_x64_"* | *"_x64."*)
      arch="x64"
      ;;
    *"_x86_"* | *"_x86."*)
      arch="x86"
      ;;
    *"_arm64_"* | *"_arm64."*)
      arch="arm64"
      ;;
  esac

  local add=""
  [[ "$arch" != "x64" ]] && add="$arch"

  case "$file" in
    "win7"* | "win_7"* | *"windows7"* | *"windows_7"* )
      id="win7${arch}"
      ;;
    "win8"* | "win_8"* | *"windows8"* | *"windows_8"* )
      id="win81${arch}"
      ;;
    "win10"*| "win_10"* | *"windows10"* | *"windows_10"* )
      id="win10${arch}"
      ;;
    "win11"* | "win_11"* | *"windows11"* | *"windows_11"* )
      id="win11${arch}"
      ;;
    *"winxp"* | *"win_xp"* | *"windowsxp"* | *"windows_xp"* )
      id="winxpx86"
      ;;
    *"winvista"* | *"win_vista"* | *"windowsvista"* | *"windows_vista"* )
      id="winvista${arch}"
      ;;
    "nano11"* | "nano_11"* )
      id="nano11"
      ;;
    "tiny11core"* | "tiny11_core"* | "tiny_11_core"* )
      id="core11"
      ;;
    "tiny11"* | "tiny_11"* )
      id="tiny11"
      ;;
    "tiny10"* | "tiny_10"* )
      id="tiny10"
      ;;
    *"_serverhypercore_"* )
      id="win2019${add}-hv"
      ;;
    *"server2025"* | *"server_2025"* )
      id="win2025${add}"
      ;;
    *"server2022"* | *"server_2022"* )
      id="win2022${add}"
      ;;
    *"server2019"* | *"server_2019"* )
      id="win2019${add}"
      ;;
    *"server2016"* | *"server_2016"* )
      id="win2016${add}"
      ;;
    *"server2012"* | *"server_2012"* )
      id="win2012r2${add}"
      ;;
    *"server2008"* | *"server_2008"* )
      id="win2008r2${add}"
      ;;
    *"server2003"* | *"server_2003"* )
      id="win2003r2${add}"
      ;;
  esac

  if [ -n "$id" ]; then
    desc=$(printVersion "$id" "$desc")
  fi

  echo "$desc"
  return 0
}

fromName() {

  local id=""
  local name="$1"
  local arch="$2"

  local add=""
  [[ "$arch" != "x64" ]] && add="$arch"

  case "${name,,}" in
    *"windows 7"* ) id="win7${arch}" ;;
    *"windows 8"* ) id="win81${arch}" ;;
    *"windows 10"* ) id="win10${arch}" ;;
    *"optimum 10"* ) id="win10${arch}" ;;
    *"windows 11"* ) id="win11${arch}" ;;
    *"optimum 11"* ) id="win11${arch}" ;;
    *"windows vista"* ) id="winvista${arch}" ;;
    *"server 2025"* ) id="win2025${add}" ;;
    *"server 2022"* ) id="win2022${add}" ;;
    *"server 2019"* ) id="win2019${add}" ;;
    *"server 2016"* ) id="win2016${add}" ;;
    *"server 2012"* ) id="win2012r2${add}" ;;
    *"server 2008"* ) id="win2008r2${add}" ;;
    *"server 2003"* ) id="win2003r2${add}" ;;
    *"hyper-v server"* ) id="win2019${add}" ;;
  esac

  echo "$id"
  return 0
}

getVersion() {

  local id
  local name="$1"
  local arch="$2"
  local evaluation=""

  id=$(fromName "$name" "$arch")
  [[ "${name,,}" == *"evaluation"* ]] && evaluation="-eval"

  case "${id,,}" in
    "win7"* | "winvista"* )
      case "${name,,}" in
        *" home"* ) id="$id-home" ;;
        *" starter"* ) id="$id-starter" ;;
        *" ultimate"* ) id="$id-ultimate" ;;
        *" enterprise"* ) id="$id-enterprise$evaluation" ;;
      esac
      ;;
    "win8"* )
      case "${name,,}" in
        *" enterprise"* ) id="$id-enterprise$evaluation" ;;
      esac
      ;;
    "win10"* | "win11"* )
      case "${name,,}" in
        *" iot"* ) id="$id-iot$evaluation" ;;
        *" ltsc"* ) id="$id-ltsc$evaluation" ;;
        *" home"* ) id="$id-home" ;;
        *" education"* ) id="$id-education" ;;
        *" enterprise"* ) id="$id-enterprise$evaluation" ;;
      esac
      ;;
    "win2025"* | "win2022"* | "win2019"* | "win2016"* | \
    "win2012"* | "win2008"* | "win2003"* )
      case "${name,,}" in
        *"hyper-v server"* ) id="$id-hv" ;;
        *"evaluation"* ) id="$id-eval" ;;
      esac
      ;;
  esac

  echo "$id"
  return 0
}

getMido() {

  local id="$1"
  local lang="$2"
  local ret="$3"
  local url=""
  local sum=""
  local size=""

  [[ "${lang,,}" != "en" && "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win11x64" )
      size=7736125440
      sum="d141f6030fed50f75e2b03e1eb2e53646c4b21e5386047cb860af5223f102a32"
      url="https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENT_CONSUMER_x64FRE_en-us.iso"
      ;;
    "win11x64-enterprise-eval" )
      size=7092807680
      sum="a61adeab895ef5a4db436e0a7011c92a2ff17bb0357f58b13bbc4062e535e7b9"
      url="https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
      ;;
    "win11x64-enterprise-ltsc-eval" )
      size=5112850432
      sum="67cec5865eaa037a72ddc633a717a10a2bed50778862267223ddb9c60ef5da68"
      url="https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_LTSC_EVAL_x64FRE_en-us.iso"
      ;;
    "win11x64-enterprise-iot-eval" )
      size=5060020224
      sum="2cee70bd183df42b92a2e0da08cc2bb7a2a9ce3a3841955a012c0f77aeb3cb29"
      url="https://software-static.download.prss.microsoft.com/dbazure/998969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_IOT_LTSC_EVAL_x64FRE_en-us.iso"
      ;;
    "win10x64-enterprise-eval" )
      size=5550497792
      sum="ef7312733a9f5d7d51cfa04ac497671995674ca5e1058d5164d6028f0938d668"
      url="https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66750/19045.2006.220908-0225.22h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
      ;;
    "win10x64-enterprise-ltsc-eval" )
      size=4898582528
      sum="e4ab2e3535be5748252a8d5d57539a6e59be8d6726345ee10e7afd2cb89fefb5"
      url="https://software-download.microsoft.com/download/pr/19044.1288.211006-0501.21h2_release_svc_refresh_CLIENT_LTSC_EVAL_x64FRE_en-us.iso"
      ;;
    "win81x64-enterprise-eval" )
      size=3961473024
      sum="2dedd44c45646c74efc5a028f65336027e14a56f76686a4631cf94ffe37c72f2"
      url="https://download.microsoft.com/download/B/9/9/B999286E-0A47-406D-8B3D-5B5AD7373A4A/9600.17050.WINBLUE_REFRESH.140317-1640_X64FRE_ENTERPRISE_EVAL_EN-US-IR3_CENA_X64FREE_EN-US_DV9.ISO"
      ;;
    "win2025-eval" )
      size=8152356864
      sum="7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51"
      url="https://software-static.download.prss.microsoft.com/dbazure/998969d5-f34g-4e03-ac9d-1f9786c66749/26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
      ;;
    "win2022-eval" )
      size=5044094976
      sum="3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325"
      url="https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"
      ;;
    "win2019-eval" )
      size=5296713728
      sum="549bca46c055157291be6c22a3aaaed8330e78ef4382c99ee82c896426a1cee1"
      url="https://software-download.microsoft.com/download/pr/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso"
      ;;
    "win2019-hv" )
      size=3022784512
      sum="cb28984af65ba1085cd6ade5fdd3d9c75efe7618846513f9ad44f1397a409f85"
      url="https://software-download.microsoft.com/download/pr/17763.557.190612-0019.rs5_release_svc_refresh_SERVERHYPERCORE_OEM_x64FRE_en-us.ISO"
      ;;
    "win2016-eval" )
      size=6972221440
      sum="1ce702a578a3cb1ac3d14873980838590f06d5b7101c5daaccbac9d73f1fb50f"
      url="https://software-download.microsoft.com/download/pr/Windows_Server_2016_Datacenter_EVAL_en-us_14393_refresh.ISO"
      ;;
    "win2012r2-eval" )
      size=4542291968
      sum="6612b5b1f53e845aacdf96e974bb119a3d9b4dcb5b82e65804ab7e534dc7b4d5"
      url="https://download.microsoft.com/download/6/2/A/62A76ABB-9990-4EFC-A4FE-C7D698DAEB96/9600.17050.WINBLUE_REFRESH.140317-1640_X64FRE_SERVER_EVAL_EN-US-IR3_SSS_X64FREE_EN-US_DV9.ISO"
      ;;
    "win2008r2-eval" )
      size=3166840832
      sum="30832ad76ccfa4ce48ccb936edefe02079d42fb1da32201bf9e3a880c8ed6312"
      url="https://download.microsoft.com/download/4/1/D/41DEA7E0-B30D-4012-A1E3-F24DC03BA1BB/7601.17514.101119-1850_x64fre_server_eval_en-us-GRMSXEVAL_EN_DVD.iso"
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) echo "$url";;
  esac

  return 0
}

getLink1() {

  # Fallbacks for users who cannot connect to the Microsoft servers

  local id="$1"
  local lang="$2"
  local ret="$3"
  local url=""
  local sum=""
  local size=""
  local host="https://dl.bobpony.com/windows"

  [[ "${lang,,}" != "en" && "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win11x64" | "win11x64-enterprise" | "win11x64-enterprise-eval" )
      size=6927149056
      sum="f5ffe9313eebc6299fba9e6eeb2971007264e6c6be013073a89b5ae9bd85bfb3"
      url="11/en-us_windows_11_25h2_x64.iso"
      ;;
    "win11x64-ltsc" | "win11x64-enterprise-ltsc" | "win11x64-enterprise-ltsc-eval" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="11/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win11x64-iot" | "win11x64-enterprise-iot" | "win11x64-enterprise-iot-eval" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="11/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win10x64" | "win10x64-enterprise" | "win10x64-enterprise-eval" )
      size=5723299840
      sum="316f718f21fc9b386d81dadd62dc60268a1cfd65b184ac6a052875a454c3431b"
      url="10/en-us_windows_10_22h2_x64.iso"
      ;;
    "win10x64-ltsc" | "win10x64-enterprise-ltsc" | "win10x64-enterprise-ltsc-eval" )
      size=4899461120
      sum="c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d"
      url="10/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso"
      ;;
    "win10x64-iot" | "win10x64-enterprise-iot" | "win10x64-enterprise-iot-eval" )
      size=4851668992
      sum="a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
      url="10/en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
      ;;      
    "win81x64" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      url="8.x/8.1/en_windows_8.1_with_update_x64_dvd_6051480.iso"
      ;;
    "win81x64-enterprise" | "win81x64-enterprise-eval" )
      size=4139163648
      sum="c3c604c03677504e8905090a8ce5bb1dde76b6fd58e10f32e3a25bef21b2abe1"
      url="8.x/8.1/en_windows_8.1_enterprise_with_update_x64_dvd_6054382.iso"
      ;;
    "win2025" | "win2025-eval" )
      size=7571058688
      sum="d273d0a85565ffbc06a3d46313f619103e2830a3373306ddbb9a08b8824f509d"
      url="server/2025/en-us_windows_server_2025_updated_oct_2025_x64_dvd_6c0c5aa8.iso"
      ;;
    "win2022" | "win2022-eval" )
      size=6023239680
      sum="5d6d91efa972cbdd6701d78db1dcf6a34c7024ca931c1718e7cb3d0c6dd54e88"
      url="server/2022/en-us_windows_server_2022_updated_oct_2025_x64_dvd_26e9af36.iso"
      ;;
    "win2019" | "win2019-eval" )
      size=5575774208
      sum="0067afe7fdc4e61f677bd8c35a209082aa917df9c117527fc4b2b52a447e89bb"
      url="server/2019/en-us_windows_server_2019_updated_aug_2021_x64_dvd_a6431a28.iso"
      ;;
    "win2016" | "win2016-eval" )
      size=6006587392
      sum="af06e5483c786c023123e325cea4775050324d9e1366f46850b515ae43f764be"
      url="server/2016/en_windows_server_2016_updated_feb_2018_x64_dvd_11636692.iso"
      ;;
    "win2012r2" | "win2012r2-eval" )
      size=5397889024
      sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
      url="server/2012r2/en_windows_server_2012_r2_with_update_x64_dvd_6052708-004.iso"
      ;;
    "win2008r2" | "win2008r2-eval" )
      size=3166584832
      sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
      url="server/2008r2/en_windows_server_2008_r2_with_sp1_x64_dvd_617601-018.iso"
      ;;
    "win7x64" | "win7x64-ultimate" )
      size=3320836096
      sum="0b738b55a5ea388ad016535a5c8234daf2e5715a0638488ddd8a228a836055a1"
      url="7/en_windows_7_with_sp1_x64.iso"
      ;;
    "win7x64-enterprise" | "win7x64-enterprise-eval" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="7/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
      ;;
    "win7x86" | "win7x86-ultimate" )
      size=2564411392
      sum="99f3369c90160816be07093dbb0ac053e0a84e52d6ed1395c92ae208ccdf67e5"
      url="7/en_windows_7_with_sp1_x86.iso"
      ;;
    "win7x86-enterprise" | "win7x86-enterprise-eval" )
      size=2434502656
      sum="8bdd46ff8cb8b8de9c4aba02706629c8983c45e87da110e64e13be17c8434dad"
      url="7/en_windows_7_enterprise_with_sp1_x86_dvd_u_677710.iso"
      ;;
    "winvistax64" | "winvistax64-ultimate" )
      size=3861460992
      sum="edf9f947c5791469fd7d2d40a5dcce663efa754f91847aa1d28ed7f585675b78"
      url="vista/en_windows_vista_sp2_x64_dvd_342267.iso"
      ;;
    "winvistax86" | "winvistax86-ultimate" )
      size=3243413504
      sum="9c36fed4255bd05a8506b2da88f9aad73643395e155e609398aacd2b5276289c"
      url="vista/en_windows_vista_with_sp2_x86_dvd_342266.iso"
      ;;
    "win2003r2" )
      size=731650535
      sum="6b64bbae7eb00fd000cc887ffdc9f224d00c557daad7f756cfa373950b880dc8"
      url="server/2003r2/en_win_srv_2003_r2_standard_x64_with_sp2_cd1_cd2.zip"
      ;;
    "winxpx86" )
      size=617756672
      sum="62b6c91563bad6cd12a352aa018627c314cfc5162d8e9f8af0756a642e602a46"
      url="xp/professional/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
    "win2kx86" )
      size=331701982
      sum="a93251b31f92316411bb48458a695d9051b13cdeba714c46f105012fdda45bf3"
      url="2000/5.00.2195.6717_x86fre_client-professional_retail_en-us.7z"
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) [ -n "$url" ] && echo "$host/$url";;
  esac

  return 0
}

getLink2() {

  local id="$1"
  local lang="$2"
  local ret="$3"
  local url=""
  local sum=""
  local size=""
  local host="https://files.dog/MSDN"

  [[ "${lang,,}" != "en" && "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win81x64" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      url="Windows%208.1%20with%20Update/en_windows_8.1_with_update_x64_dvd_6051480.iso"
      ;;
    "win81x64-enterprise" | "win81x64-enterprise-eval" )
      size=4139163648
      sum="c3c604c03677504e8905090a8ce5bb1dde76b6fd58e10f32e3a25bef21b2abe1"
      url="Windows%208.1%20with%20Update/en_windows_8.1_enterprise_with_update_x64_dvd_6054382.iso"
      ;;
    "win2012r2" | "win2012r2-eval" )
      size=5397889024
      sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
      url="Windows%20Server%202012%20R2%20with%20Update/en_windows_server_2012_r2_with_update_x64_dvd_6052708.iso"
      ;;
    "win2008r2" | "win2008r2-eval" )
      size=3166584832
      sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
      url="Windows%20Server%202008%20R2/en_windows_server_2008_r2_with_sp1_x64_dvd_617601.iso"
      ;;
    "win7x64" | "win7x64-ultimate" )
      size=3320903680
      sum="36f4fa2416d0982697ab106e3a72d2e120dbcdb6cc54fd3906d06120d0653808"
      url="Windows%207/en_windows_7_ultimate_with_sp1_x64_dvd_u_677332.iso"
      ;;
    "win7x64-enterprise" | "win7x64-enterprise-eval" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="Windows%207/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
      ;;
    "win7x86" | "win7x86-ultimate" )
      size=2564476928
      sum="e2c009a66d63a742941f5087acae1aa438dcbe87010bddd53884b1af6b22c940"
      url="Windows%207/en_windows_7_ultimate_with_sp1_x86_dvd_u_677460.iso"
      ;;
    "win7x86-enterprise" | "win7x86-enterprise-eval" )
      size=2434502656
      sum="8bdd46ff8cb8b8de9c4aba02706629c8983c45e87da110e64e13be17c8434dad"
      url="Windows%207/en_windows_7_enterprise_with_sp1_x86_dvd_u_677710.iso"
      ;;
    "winvistax64" | "winvistax64-ultimate" )
      size=3861460992
      sum="edf9f947c5791469fd7d2d40a5dcce663efa754f91847aa1d28ed7f585675b78"
      url="Windows%20Vista/en_windows_vista_sp2_x64_dvd_342267.iso"
      ;;
    "winvistax64-enterprise" )
      size=3205953536
      sum="0a0cd511b3eac95c6f081419c9c65b12317b9d6a8d9707f89d646c910e788016"
      url="Windows%20Vista/en_windows_vista_enterprise_sp2_x64_dvd_342332.iso"
      ;;
    "winvistax86" | "winvistax86-ultimate" )
      size=3243413504
      sum="9c36fed4255bd05a8506b2da88f9aad73643395e155e609398aacd2b5276289c"
      url="Windows%20Vista/en_windows_vista_with_sp2_x86_dvd_342266.iso"
      ;;
    "winvistax86-enterprise" )
      size=2420981760
      sum="54e2720004041e7db988a391543ea5228b0affc28efcf9303d2d0ff9402067f5"
      url="Windows%20Vista/en_windows_vista_enterprise_sp2_x86_dvd_342329.iso"
      ;;
    "win2003r2" )
      size=652367872
      sum="74245cba888f935b138b106c2744bec7f392925b472358960a0b5643cd6abb32"
      url="Windows%20Server%202003%20R2/en_win_srv_2003_r2_standard_x64_with_sp2_cd1_x13-05757.iso"
      ;;
    "winxpx86" )
      size=617756672
      sum="62b6c91563bad6cd12a352aa018627c314cfc5162d8e9f8af0756a642e602a46"
      url="Windows%20XP/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) [ -n "$url" ] && echo "$host/$url";;
  esac

  return 0
}

getLink3() {

  local id="$1"
  local lang="$2"
  local ret="$3"
  local url=""
  local sum=""
  local size=""
  local host="https://archive.org/download"

  [[ "${lang,,}" != "en" && "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "nano11" )
      size=2463565824
      sum="a1e0614372768cbe2d24de74b78a4a97bc1017ea5080dfed1d2125e4a527eb1a"
      url="nano11_25h2/nano11%2025h2.iso"
      ;;
    "core11" )
      size=3304132608
      sum="c0e0252b24144b8defb6c7ded2bc09f9297daf1fb8369b16c5b85382331eb47f"
      url="tiny11_25H2/tiny11core_25H2_Nov25.iso"
      ;;
    "tiny11" )
      size=5730246656
      sum="7b24815845684add7250808b3b0027ba4e94cf52c62e9ef40d5b965dd304d6ca"
      url="tiny11_25H2/tiny11_25H2_Nov25.iso"
      ;;
    "tiny10" )
      size=3839819776
      sum="a11116c0645d892d6a5a7c585ecc1fa13aa66f8c7cc6b03bf1f27bd16860cc35"
      url="tiny-10-23-h2/tiny10%20x64%2023h2.iso"
      ;;
    "win11x64" )
      size=7736125440
      sum="d141f6030fed50f75e2b03e1eb2e53646c4b21e5386047cb860af5223f102a32"
      url="W11x64_26200.6584/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENT_CONSUMER_x64FRE_en-us.iso"
      ;;
    "win11x64-enterprise" | "win11x64-enterprise-eval" )
      size=7620513792
      sum="2b65df49334b64e9341dc404e9c527bf1b2a9a105e95314a347fd29ac9900581"
      url="massgrave.dev-windows-x64-and-x86-archive/en-us_windows_11_business_editions_version_25h2_x64_dvd_41c521e7.iso"
      ;;
    "win11x64-ltsc" | "win11x64-enterprise-ltsc" | "win11x64-enterprise-ltsc-eval" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="Windows11LTSC/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win11x64-iot" | "win11x64-enterprise-iot" | "win11x64-enterprise-iot-eval" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="Windows11LTSC/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win10x64" | "win10x64-enterprise" | "win10x64-enterprise-eval" )
      size=6985445376
      sum="2c23bc8b95a9314f15ebff881dcbea49651f52a96a0327d7aaf523aa66043765"
      url="windows_10_version_2004/Windows%2010%2C%20version%2022H2/Updated%20October%202025%20%2819045.6456%29/en-us_windows_10_business_editions_version_22h2_updated_oct_2025_x64_dvd_d2eef4b0.iso"
      ;;
    "win10x64-ltsc" | "win10x64-enterprise-ltsc" | "win10x64-enterprise-ltsc-eval" )
      size=4899461120
      sum="c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d"
      url="en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96_202302/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso"
      ;;
    "win10x64-iot" | "win10x64-enterprise-iot" | "win10x64-enterprise-iot-eval" )
      size=4851668992
      sum="a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
      url="en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f_202411/en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
      ;;
    "win81x64" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      url="en_windows_8.1_with_update_x64_dvd_6051480/en_windows_8.1_with_update_x64_dvd_6051480.iso"
      ;;
    "win81x64-enterprise" | "win81x64-enterprise-eval" )
      size=4139163648
      sum="c3c604c03677504e8905090a8ce5bb1dde76b6fd58e10f32e3a25bef21b2abe1"
      url="en_windows_8.1_enterprise_with_update_x64_dvd/en_windows_8.1_enterprise_with_update_x64_dvd_6054382.iso"
      ;;
    "win2025" | "win2025-eval" )
      size=8145395712
      sum="f3e277e75acdb793e6f08f4880b514ae0046cedf618c22f727890e54367075e6"
      url="massgrave.dev-windows-x64-and-x86-archive/en-us_windows_server_2025_updated_dec_2025_x64_dvd_c54ab58b.iso"
      ;;
    "win2022" | "win2022-eval" )
      size=6023239680
      sum="5d6d91efa972cbdd6701d78db1dcf6a34c7024ca931c1718e7cb3d0c6dd54e88"
      url="massgrave.dev-windows-x64-and-x86-archive/en-us_windows_server_2022_updated_oct_2025_x64_dvd_26e9af36.iso"
      ;;
    "win2019" | "win2019-eval" )
      size=5651695616
      sum="ea247e5cf4df3e5829bfaaf45d899933a2a67b1c700a02ee8141287a8520261c"
      url="massgrave.dev-windows-x64-and-x86-archive/en-us_windows_server_2019_x64_dvd_f9475476.iso"
      ;;
    "win2016" | "win2016-eval" )
      size=6006587392
      sum="af06e5483c786c023123e325cea4775050324d9e1366f46850b515ae43f764be"
      url="en_windows_server_2016_updated_feb_2018_x64_dvd_11636692/en_windows_server_2016_updated_feb_2018_x64_dvd_11636692.iso"
      ;;
    "win2012r2" | "win2012r2-eval" )
      size=5397889024
      sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
      url="en_windows_server_2012_r2_with_update_x64_dvd_6052708_202006/en_windows_server_2012_r2_with_update_x64_dvd_6052708.iso"
      ;;
    "win2008r2" | "win2008r2-eval" )
      size=3166584832
      sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
      url="en_windows_server_2008_r2_with_sp1_x64_dvd_617601_202006/en_windows_server_2008_r2_with_sp1_x64_dvd_617601.iso"
      ;;
    "win7x64" | "win7x64-ultimate" )
      size=3320903680
      sum="36f4fa2416d0982697ab106e3a72d2e120dbcdb6cc54fd3906d06120d0653808"
      url="win7-ult-sp1-english/Win7_Ult_SP1_English_x64.iso"
      ;;
    "win7x64-enterprise" | "win7x64-enterprise-eval" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="en_windows_7_enterprise_with_sp1_x64_dvd_u_677651_202006/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
      ;;
    "win7x86" | "win7x86-ultimate" )
      size=2564476928
      sum="e2c009a66d63a742941f5087acae1aa438dcbe87010bddd53884b1af6b22c940"
      url="win7-ult-sp1-english/Win7_Ult_SP1_English_x32.iso"
      ;;
    "win7x86-enterprise" | "win7x86-enterprise-eval" )
      size=2434502656
      sum="8bdd46ff8cb8b8de9c4aba02706629c8983c45e87da110e64e13be17c8434dad"
      url="en_windows_7_enterprise_with_sp1_x86_dvd_u_677710_202006/en_windows_7_enterprise_with_sp1_x86_dvd_u_677710.iso"
      ;;
    "winvistax64" | "winvistax64-ultimate" )
      size=3861460992
      sum="edf9f947c5791469fd7d2d40a5dcce663efa754f91847aa1d28ed7f585675b78"
      url="ms_windows_vista_sp2/en_windows_vista_sp2_x64_dvd_342267.iso"
      ;;
    "winvistax64-enterprise" )
      size=3205953536
      sum="0a0cd511b3eac95c6f081419c9c65b12317b9d6a8d9707f89d646c910e788016"
      url="en_windows_vista_enterprise_sp2_x64_dvd_342332_202007/en_windows_vista_enterprise_sp2_x64_dvd_342332.iso"
      ;;
    "winvistax86" | "winvistax86-ultimate" )
      size=3243413504
      sum="9c36fed4255bd05a8506b2da88f9aad73643395e155e609398aacd2b5276289c"
      url="en_windows_vista_sp2_x86_dvd_342266/en_windows_vista_sp2_x86_dvd_342266.iso"
      ;;
    "winvistax86-enterprise" )
      size=2420981760
      sum="54e2720004041e7db988a391543ea5228b0affc28efcf9303d2d0ff9402067f5"
      url="en_windows_vista_enterprise_sp2_x86_dvd_342329_202007/en_windows_vista_enterprise_sp2_x86_dvd_342329.iso"
      ;;
    "win2003r2" )
      size=652367872
      sum="74245cba888f935b138b106c2744bec7f392925b472358960a0b5643cd6abb32"
      url="en_win_srv_2003_r2_standard_x64_with_sp2_cd1_x13-05757/en_win_srv_2003_r2_standard_x64_with_sp2_cd1_x13-05757.iso"
      ;;
    "winxpx64" )
      size=628299776
      sum="49b87fc4a9191dcf57588a2d36a87da87a37577e0f0a57b778dc15874287f8b0"
      url="en_win_xp_pro_x64_with_sp2/CRMPXFPP_EN.iso"
      ;;
    "winxpx86" )
      size=617756672
      sum="62b6c91563bad6cd12a352aa018627c314cfc5162d8e9f8af0756a642e602a46"
      url="XPPRO_SP3_ENU/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
    "win2kx86" )
      size=386859008
      sum="e3816f6e80b66ff686ead03eeafffe9daf020a5e4717b8bd4736b7c51733ba22"
      url="MicrosoftWindows2000BuildCollection/5.00.2195.6717_x86fre_client-professional_retail_en-us-ZRMPFPP_EN.iso"
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) [ -n "$url" ] && echo "$host/$url";;
  esac

  return 0
}

getValue() {

  local val=""
  local id="$2"
  local lang="$3"
  local type="$4"
  local func="getLink$1"

  if [ "$1" -gt 0 ] && [ "$1" -le "$MIRRORS" ]; then
    val=$($func "$id" "$lang" "$type")
  fi

  echo "$val"
  return 0
}

getLink() {

  local url
  url=$(getValue "$1" "$2" "$3" "")

  echo "$url"
  return 0
}

getHash() {

  local sum
  sum=$(getValue "$1" "$2" "$3" "sum")

  echo "$sum"
  return 0
}

getSize() {

  local size
  size=$(getValue "$1" "$2" "$3" "size")

  echo "$size"
  return 0
}

isMido() {

  local id="$1"
  local lang="$2"
  local sum

  disabled "${MIDO:-}" && return 1

  sum=$(getMido "$id" "en" "sum")
  [ -n "$sum" ] && return 0

  return 1
}

isESD() {

  local id="$1"
  local lang="$2"

  disabled "${ESD:-}" && return 1

  case "${id,,}" in
    "win11${PLATFORM,,}" | "win10${PLATFORM,,}" )
      return 0
      ;;
    "win11${PLATFORM,,}-enterprise" | "win11${PLATFORM,,}-enterprise-eval")
      return 0
      ;;
    "win10${PLATFORM,,}-enterprise" | "win10${PLATFORM,,}-enterprise-eval" )
      return 0
      ;;
  esac

  return 1
}

validVersion() {

  local id="$1"
  local lang="$2"
  local url i=0

  isESD "$id" "$lang" && return 0
  isMido "$id" "$lang" && return 0

  for ((i=1;i<=MIRRORS;i++)); do

    url=$(getLink "$i" "$id" "$lang")
    [ -n "$url" ] && return 0

  done

  return 1
}

isCompatible() {
  return 0
}

return 0
