#!/usr/bin/env bash
set -Eeuo pipefail

: "${KEY:=""}"
: "${WIDTH:=""}"
: "${HEIGHT:=""}"
: "${VERIFY:=""}"
: "${REGION:=""}"
: "${EDITION:=""}"
: "${MANUAL:=""}"
: "${REMOVE:=""}"
: "${VERSION:=""}"
: "${DETECTED:=""}"
: "${KEYBOARD:=""}"
: "${LANGUAGE:=""}"
: "${USERNAME:=""}"
: "${PASSWORD:=""}"

MIRRORS=4

parseVersion() {

  if [[ "${VERSION}" == \"*\" || "${VERSION}" == \'*\' ]]; then
    VERSION="${VERSION:1:-1}"
  fi

  [ -z "$VERSION" ] && VERSION="win11"

  case "${VERSION,,}" in
    "11" | "11p" | "win11" | "pro11" | "win11p" | "windows11" | "windows 11" )
      VERSION="win11x64"
      ;;
    "11e" | "win11e" | "windows11e" | "windows 11e" )
      VERSION="win11x64-enterprise-eval"
      ;;
    "11i" | "11iot" | "iot11" | "win11i" | "win11-iot" | "win11x64-iot" | "win11x64-enterprise-iot-eval" )
      VERSION="win11x64-enterprise-iot-eval"
      [ -z "$DETECTED" ] && DETECTED="win11x64-iot"
      ;;
    "11l" | "11ltsc" | "ltsc11" | "win11l" | "win11-ltsc" | "win11x64-ltsc" | "win11x64-enterprise-ltsc-eval" )
      VERSION="win11x64-enterprise-ltsc-eval"
      [ -z "$DETECTED" ] && DETECTED="win11x64-ltsc"
      ;;
    "10" | "10p" | "win10" | "pro10" | "win10p" | "windows10" | "windows 10" )
      VERSION="win10x64"
      ;;
    "10e" | "win10e" | "windows10e" | "windows 10e" )
      VERSION="win10x64-enterprise-eval"
      ;;
    "10i" | "10iot" | "iot10" | "win10i" | "win10-iot" | "win10x64-iot" | "win10x64-enterprise-iot-eval" )
      VERSION="win10x64-enterprise-iot-eval"
      [ -z "$DETECTED" ] && DETECTED="win10x64-iot"
      ;;
    "10l" | "10ltsc" | "ltsc10" | "win10l" | "win10-ltsc" | "win10x64-ltsc" | "win10x64-enterprise-ltsc-eval" )
      VERSION="win10x64-enterprise-ltsc-eval"
      [ -z "$DETECTED" ] && DETECTED="win10x64-ltsc"
      ;;
    "8" | "8p" | "81" | "81p" | "pro8" | "8.1" | "win8" | "win8p" | "win81" | "win81p" | "windows 8" )
      VERSION="win81x64"
      ;;
    "8e" | "81e" | "8.1e" | "win8e" | "win81e" | "windows 8e" )
      VERSION="win81x64-enterprise-eval"
      ;;
    "7" | "win7" | "windows7" | "windows 7" )
      VERSION="win7x64"
      [ -z "$DETECTED" ] && DETECTED="win7x64-ultimate"
      ;;
    "7u" | "win7u" | "windows7u" | "windows 7u" )
      VERSION="win7x64-ultimate"
      ;;
    "7e" | "win7e" | "windows7e" | "windows 7e" )
      VERSION="win7x64-enterprise"
      ;;
    "7x86" | "win7x86" | "win732" | "windows7x86" )
      VERSION="win7x86"
      [ -z "$DETECTED" ] && DETECTED="win7x86-ultimate"
      ;;
    "7ux86" | "7u32" | "win7x86-ultimate" )
      VERSION="win7x86-ultimate"
      ;;
    "7ex86" | "7e32" | "win7x86-enterprise" )
      VERSION="win7x86-enterprise"
      ;;
    "vista" | "vs" | "6" | "winvista" | "windowsvista" | "windows vista" )
      VERSION="winvistax64"
      [ -z "$DETECTED" ] && DETECTED="winvistax64-ultimate"
      ;;
    "vistu" | "vu" | "6u" | "winvistu" )
      VERSION="winvistax64-ultimate"
      ;;
    "viste" | "ve" | "6e" | "winviste" )
      VERSION="winvistax64-enterprise"
      ;;
    "vistax86" | "vista32" | "6x86" | "winvistax86" | "windowsvistax86" )
      VERSION="winvistax86"
      [ -z "$DETECTED" ] && DETECTED="winvistax86-ultimate"
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
    "core11" | "core 11" )
      VERSION="core11"
      [ -z "$DETECTED" ] && DETECTED="win11x64"
      ;;
    "tiny11" | "tiny 11" )
      VERSION="tiny11"
      [ -z "$DETECTED" ] && DETECTED="win11x64"
      ;;
   "tiny10" | "tiny 10" )
      VERSION="tiny10"
      [ -z "$DETECTED" ] && DETECTED="win10x64-ltsc"
      ;;
  esac

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
      desc="$lang"
      culture="ar-SA" ;;
    "bg" | "bg-"* )
      short="bg"
      lang="Bulgarian"
      desc="$lang"
      culture="bg-BG" ;;
    "cs" | "cs-"* | "cz" | "cz-"* )
      short="cs"
      lang="Czech"
      desc="$lang"
      culture="cs-CZ" ;;
    "da" | "da-"* | "dk" | "dk-"* )
      short="da"
      lang="Danish"
      desc="$lang"
      culture="da-DK" ;;
    "de" | "de-"* )
      short="de"
      lang="German"
      desc="$lang"
      culture="de-DE" ;;
    "el" | "el-"* | "gr" | "gr-"* )
      short="el"
      lang="Greek"
      desc="$lang"
      culture="el-GR" ;;
    "gb" | "en-gb" )
      short="en-gb"
      lang="English International"
      desc="English"
      culture="en-GB" ;;
    "en" | "en-"* )
      short="en"
      lang="English"
      desc="English"
      culture="en-US" ;;
    "mx" | "es-mx" )
      short="mx"
      lang="Spanish (Mexico)"
      desc="Spanish"
      culture="es-MX" ;;
    "es" | "es-"* )
      short="es"
      lang="Spanish"
      desc="$lang"
      culture="es-ES" ;;
    "et" | "et-"* )
      short="et"
      lang="Estonian"
      desc="$lang"
      culture="et-EE" ;;
    "fi" | "fi-"* )
      short="fi"
      lang="Finnish"
      desc="$lang"
      culture="fi-FI" ;;
    "ca" | "fr-ca" )
      short="ca"
      lang="French Canadian"
      desc="French"
      culture="fr-CA" ;;
    "fr" | "fr-"* )
      short="fr"
      lang="French"
      desc="$lang"
      culture="fr-FR" ;;
    "he" | "he-"* | "il" | "il-"* )
      short="he"
      lang="Hebrew"
      desc="$lang"
      culture="he-IL" ;;
    "hr" | "hr-"* | "cr" | "cr-"* )
      short="hr"
      lang="Croatian"
      desc="$lang"
      culture="hr-HR" ;;
    "hu" | "hu-"* )
      short="hu"
      lang="Hungarian"
      desc="$lang"
      culture="hu-HU" ;;
    "it" | "it-"* )
      short="it"
      lang="Italian"
      desc="$lang"
      culture="it-IT" ;;
    "ja" | "ja-"* | "jp" | "jp-"* )
      short="ja"
      lang="Japanese"
      desc="$lang"
      culture="ja-JP" ;;
    "ko" | "ko-"* | "kr" | "kr-"* )
      short="ko"
      lang="Korean"
      desc="$lang"
      culture="ko-KR" ;;
    "lt" | "lt-"* )
      short="lt"
      lang="Lithuanian"
      desc="$lang"
      culture="lt-LT" ;;
    "lv" | "lv-"* )
      short="lv"
      lang="Latvian"
      desc="$lang"
      culture="lv-LV" ;;
    "nb" | "nb-"* |"nn" | "nn-"* | "no" | "no-"* )
      short="no"
      lang="Norwegian"
      desc="$lang"
      culture="nb-NO" ;;
    "nl" | "nl-"* )
      short="nl"
      lang="Dutch"
      desc="$lang"
      culture="nl-NL" ;;
    "pl" | "pl-"* )
      short="pl"
      lang="Polish"
      desc="$lang"
      culture="pl-PL" ;;
    "br" | "pt-br" )
      short="pt"
      lang="Brazilian Portuguese"
      desc="Portuguese"
      culture="pt-BR" ;;
    "pt" | "pt-"* )
      short="pp"
      lang="Portuguese"
      desc="$lang"
      culture="pt-BR" ;;
    "ro" | "ro-"* )
      short="ro"
      lang="Romanian"
      desc="$lang"
      culture="ro-RO" ;;
    "ru" | "ru-"* )
      short="ru"
      lang="Russian"
      desc="$lang"
      culture="ru-RU" ;;
    "sk" | "sk-"* )
      short="sk"
      lang="Slovak"
      desc="$lang"
      culture="sk-SK" ;;
    "sl" | "sl-"* | "si" | "si-"* )
      short="sl"
      lang="Slovenian"
      desc="$lang"
      culture="sl-SI" ;;
    "sr" | "sr-"* )
      short="sr"
      lang="Serbian Latin"
      desc="Serbian"
      culture="sr-Latn-RS" ;;
    "sv" | "sv-"* | "se" | "se-"* )
      short="sv"
      lang="Swedish"
      desc="$lang"
      culture="sv-SE" ;;
    "th" | "th-"* )
      short="th"
      lang="Thai"
      desc="$lang"
      culture="th-TH" ;;
    "tr" | "tr-"* )
      short="tr"
      lang="Turkish"
      desc="$lang"
      culture="tr-TR" ;;
    "ua" | "ua-"* | "uk" | "uk-"* )
      short="uk"
      lang="Ukrainian"
      desc="$lang"
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

  REGION="${REGION//_/-/}"
  KEYBOARD="${KEYBOARD//_/-/}"
  LANGUAGE="${LANGUAGE//_/-/}"

  [ -z "$LANGUAGE" ] && LANGUAGE="en"

  case "${LANGUAGE,,}" in
    "arabic" | "arab" ) LANGUAGE="ar" ;;
    "bulgarian" | "bu" ) LANGUAGE="bg" ;;
    "chinese" | "cn" ) LANGUAGE="zh" ;;
    "croatian" | "cr" | "hrvatski" ) LANGUAGE="hr" ;;
    "czech" | "cz" | "cesky" ) LANGUAGE="cs" ;;
    "danish" | "dk" | "danske" ) LANGUAGE="da" ;;
    "dutch" | "nederlands" ) LANGUAGE="nl" ;;
    "english" | "gb" | "british" ) LANGUAGE="en" ;;
    "estonian" | "eesti" ) LANGUAGE="et" ;;
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
    *"-enterprise" )
      edition="Enterprise"
      ;;
    *"-education" )
      edition="Education"
      ;;
    *"-hv" )
      edition="2019"
      ;;
    *"-iot" | *"-iot-eval" )
      edition="LTSC"
      ;;
    *"-ltsc" | *"-ltsc-eval" )
      edition="LTSC"
      ;;
    *"-enterprise-eval" )
      edition="Enterprise (Evaluation)"
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

  id=$(fromName "$name" "$arch")

  case "${id,,}" in
    "win7"* | "winvista"* )
        case "${name,,}" in
          *" home"* ) id="$id-home" ;;
          *" starter"* ) id="$id-starter" ;;
          *" ultimate"* ) id="$id-ultimate" ;;
          *" enterprise evaluation"* ) id="$id-enterprise-eval" ;;
          *" enterprise"* ) id="$id-enterprise" ;;
        esac
      ;;
    "win8"* )
        case "${name,,}" in
          *" enterprise evaluation"* ) id="$id-enterprise-eval" ;;
          *" enterprise"* ) id="$id-enterprise" ;;
        esac
      ;;
    "win10"* | "win11"* )
       case "${name,,}" in
          *" iot"* ) id="$id-iot" ;;
          *" ltsc"* ) id="$id-ltsc" ;;
          *" home"* ) id="$id-home" ;;
          *" education"* ) id="$id-education" ;;
          *" enterprise evaluation"* ) id="$id-enterprise-eval" ;;
          *" enterprise"* ) id="$id-enterprise" ;;
        esac
      ;;
    "win2025"* | "win2022"* | "win2019"* | "win2016"* | "win2012"* | "win2008"* | "win2003"* )
       case "${name,,}" in
          *" evaluation"* ) id="$id-eval" ;;
          *"hyper-v server"* ) id="$id-hv" ;;
        esac
      ;;
  esac

  echo "$id"
  return 0
}

switchEdition() {

  local id="$1"

  case "${id,,}" in
    "win11${PLATFORM,,}-enterprise-eval" )
      DETECTED="win11${PLATFORM,,}-enterprise"
      ;;
    "win10${PLATFORM,,}-enterprise-eval" )
      DETECTED="win10${PLATFORM,,}-enterprise"
      ;;
    "win81${PLATFORM,,}-enterprise-eval" )
      DETECTED="win81${PLATFORM,,}-enterprise"
      ;;
    "win7${PLATFORM,,}" | "win7${PLATFORM,,}-enterprise-eval" )
      DETECTED="win7${PLATFORM,,}-enterprise"
      ;;
    "win2025-eval" ) DETECTED="win2025" ;;
    "win2022-eval" ) DETECTED="win2022" ;;
    "win2019-eval" ) DETECTED="win2019" ;;
    "win2016-eval" ) DETECTED="win2016" ;;
    "win2012r2-eval" ) DETECTED="win2012r2" ;;
    "win2008r2-eval" ) DETECTED="win2008r2" ;;
  esac

  return 0
}

getMido() {

  local id="$1"
  local lang="$2"
  local ret="$3"
  local url=""
  local sum=""
  local size=""

  [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win11x64" )
      size=5819484160
      sum="b56b911bf18a2ceaeb3904d87e7c770bdf92d3099599d61ac2497b91bf190b11"
      ;;
    "win11x64-enterprise-eval" )
      size=4295096320
      sum="dad633276073f14f3e0373ef7e787569e216d54942ce522b39451c8f2d38ad43"
      url="https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1.240331-1435.ge_release_CLIENTENTERPRISEEVAL_OEMRET_A64FRE_en-us.iso"
      ;;
    "win11x64-enterprise-iot-eval" | "win11x64-enterprise-ltsc-eval" )
      size=5060020224
      sum="2cee70bd183df42b92a2e0da08cc2bb7a2a9ce3a3841955a012c0f77aeb3cb29"
      url="https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1.240331-1435.ge_release_CLIENT_IOT_LTSC_EVAL_x64FRE_en-us.iso"
      ;;
    "win10x64" )
      size=6140975104
      sum="a6f470ca6d331eb353b815c043e327a347f594f37ff525f17764738fe812852e"
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
      size=6014152704
      sum="d0ef4502e350e3c6c53c15b1b3020d38a5ded011bf04998e950720ac8579b23d"
      url="https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
      ;;
    "win2022-eval" )
      size=5044094976
      sum="3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325"
      url="https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"
      ;;
    "win2019-eval" )
      size=5652088832
      sum="6dae072e7f78f4ccab74a45341de0d6e2d45c39be25f1f5920a2ab4f51d7bcbb"
      url="https://software-download.microsoft.com/download/pr/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso"
     ;;
    "win2019-hv" )
      size=3072712704
      sum="48e9b944518e5bbc80876a9a7ff99716f386f404f4be48dca47e16a66ae7872c"
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
    "win2008r2" )
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

  [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win11x64" | "win11x64-enterprise" | "win11x64-enterprise-eval" )
      size=5332989952
      sum="aa1ad990f930d907b7a34ea897abbb0dfbe47552ca8acc146f92e40381839e05"
      url="11/en-us_windows_11_24h2_x64.iso"
      ;;
    "win11x64-iot" | "win11x64-enterprise-iot-eval" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="11/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win11x64-ltsc" | "win11x64-enterprise-ltsc-eval" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="11/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win10x64" | "win10x64-enterprise" | "win10x64-enterprise-eval" )
      size=5535252480
      sum="557871965263d0fd0a1ea50b5d0d0d7cb04a279148ca905c1c675c9bc0d5486c"
      url="10/en-us_windows_10_22h2_x64.iso"
      ;;
    "win10x64-iot" | "win10x64-enterprise-iot-eval" )
      size=4851668992
      sum="a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
      url="10/en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
      ;;
    "win10x64-ltsc" | "win10x64-enterprise-ltsc-eval" )
      size=4899461120
      sum="c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d"
      url="10/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso"
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
      size=5307176960
      sum="2293897341febdcea599f5412300b470b5288c6fd2b89666a7b27d283e8d3cf3"
      url="server/2025/en-us_windows_server_2025_preview_x64_dvd_ce9eb1a5.iso"
      ;;
    "win2022" | "win2022-eval" )
      size=5365624832
      sum="c3c57bb2cf723973a7dcfb1a21e97dfa035753a7f111e348ad918bb64b3114db"
      url="server/2022/en-us_windows_server_2022_updated_jan_2024_x64_dvd_2b7a0c9f.iso"
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
    "winxpx64" )
      size=614166528
      sum="8fac68e1e56c64ad9a2aa0ad464560282e67fa4f4dd51d09a66f4e548eb0f2d6"
      url="xp/professional/en_win_xp_pro_x64_vl.iso"
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

  [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0

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
    "winxpx64" )
      size=614166528
      sum="8fac68e1e56c64ad9a2aa0ad464560282e67fa4f4dd51d09a66f4e548eb0f2d6"
      url="Windows%20XP/en_win_xp_pro_x64_vl.iso"
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
  local host="https://nixsys.com/drivers"

  [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win7x64" | "win7x64-ultimate" )
      size=3319478272
      sum="3286963e1476082ba882a5058c205c264772bead9e99e15cd1cb255f04b72900"
      url="WINDOWS764_EN_DVD.iso"
      ;;
    "win7x86" | "win7x86-ultimate" )
      size=2564784128
      sum="bd4c03c917d00a40222d92a6fab04981a7bd46140bda1888eb961a322e3c5d89"
      url="WINDOWS732_EN_DVD.iso"
      ;;
    "winxpx86" )
      size=618065920
      sum="8177d0137dfe4e8296a85793f140806c9250a5992c8e0e50158c742767ad1182"
      url="WinXPsp3.iso"
      ;;
    "win2kx86" )
      size=387424256
      sum="08b11c3897eb38d1e6566a17cec5cdf2b3c620444e160e3db200a7e223aabbd8"
      url="Windows_2000_SP4.iso"
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) [ -n "$url" ] && echo "$host/$url";;
  esac

  return 0
}

getLink4() {

  local id="$1"
  local lang="$2"
  local ret="$3"
  local url=""
  local sum=""
  local size=""
  local host="https://archive.org/download"

  [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "core11" )
      size=2159738880
      sum="78f0f44444ff95b97125b43e560a72e0d6ce0a665cf9f5573bf268191e5510c1"
      url="tiny-11-core-x-64-beta-1/tiny11%20core%20x64%20beta%201.iso"
      ;;
    "tiny11" )
      size=3788177408
      sum="a028800a91addc35d8ae22dce7459b67330f7d69d2f11c70f53c0fdffa5b4280"
      url="tiny11-2311/tiny11%202311%20x64.iso"
      ;;
    "tiny10" )
      size=3839819776
      sum="a11116c0645d892d6a5a7c585ecc1fa13aa66f8c7cc6b03bf1f27bd16860cc35"
      url="tiny-10-23-h2/tiny10%20x64%2023h2.iso"
      ;;
    "win11x64" )
      size=5819484160
      sum="b56b911bf18a2ceaeb3904d87e7c770bdf92d3099599d61ac2497b91bf190b11"
      url="windows-11-24h2-x64/Windows%2011%2024H2%20x64.iso"
      ;;
    "win11x64-enterprise" | "win11x64-enterprise-eval" )
      size=6209064960
      sum="c8dbc96b61d04c8b01faf6ce0794fdf33965c7b350eaa3eb1e6697019902945c"
      url="Windows11Enterprise23H2x64/22631.2428.231001-0608.23H2_NI_RELEASE_SVC_REFRESH_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
      ;;
    "win11x64-iot" | "win11x64-enterprise-iot-eval" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="Windows11LTSC/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win11x64-ltsc" | "win11x64-enterprise-ltsc-eval" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="Windows11LTSC/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win10x64" | "win10x64-enterprise" | "win10x64-enterprise-eval" )
      size=6978310144
      sum="7847abd6f39abd02dc8089c4177d354f9eb66fa0ee2fe8ae20e596e675d1ab67"
      url="Windows-10-22H2-July-2024-64-bit-DVD-English/en-us_windows_10_business_editions_version_22h2_updated_july_2024_x64_dvd_c004521a.iso"
      ;;
    "win10x64-iot" | "win10x64-enterprise-iot-eval" )
      size=4851668992
      sum="a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
      url="en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f_202411/en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
      ;;
    "win10x64-ltsc" | "win10x64-enterprise-ltsc-eval" )
      size=4899461120
      sum="c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d"
      url="en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96_202302/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso"
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
    "win2022" | "win2022-eval" )
      size=5365624832
      sum="c3c57bb2cf723973a7dcfb1a21e97dfa035753a7f111e348ad918bb64b3114db"
      url="win-server-2022/2227-January_2024/en-us_windows_server_2022_updated_jan_2024_x64_dvd_2b7a0c9f.iso"
      ;;
    "win2019" | "win2019-eval" )
      size=5575774208
      sum="0067afe7fdc4e61f677bd8c35a209082aa917df9c117527fc4b2b52a447e89bb"
      url="sw-dvd-9-win-server-std-core-2019-1809.18-64-bit-english-dc-std-mlf-x-22-74330/SW_DVD9_Win_Server_STD_CORE_2019_1809.18_64Bit_English_DC_STD_MLF_X22-74330.ISO"
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
      url="en_windows_vista_sp2_x64_dvd_342267_202010/en_windows_vista_sp2_x64_dvd_342267.iso"
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
    "winxpx86" )
      size=617756672
      sum="62b6c91563bad6cd12a352aa018627c314cfc5162d8e9f8af0756a642e602a46"
      url="XPPRO_SP3_ENU/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
    "winxpx64" )
      size=614166528
      sum="8fac68e1e56c64ad9a2aa0ad464560282e67fa4f4dd51d09a66f4e548eb0f2d6"
      url="windows-xp-all-sp-msdn-iso-files-en-de-ru-tr-x86-x64/en_win_xp_sp1_pro_x64_vl.iso"
      ;;
    "win2kx86" )
      size=386859008
      sum="e3816f6e80b66ff686ead03eeafffe9daf020a5e4717b8bd4736b7c51733ba22"
      url="MicrosoftWindows2000BuildCollection/5.00.2195.6717_x86fre_client-professional_retail_en-us-ZRMPFPP_EN.iso"
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

  sum=$(getMido "$id" "en" "sum")
  [ -n "$sum" ] && return 0

  return 1
}

isESD() {

  local id="$1"
  local lang="$2"

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
  local url

  isESD "$id" "$lang" && return 0
  isMido "$id" "$lang" && return 0

  for ((i=1;i<=MIRRORS;i++)); do

    url=$(getLink "$i" "$id" "$lang")
    [ -n "$url" ] && return 0

  done

  return 1
}

addFolder() {

  local src="$1"
  local folder="/oem"

  [ ! -d "$folder" ] && folder="/OEM"
  [ ! -d "$folder" ] && folder="$STORAGE/oem"
  [ ! -d "$folder" ] && folder="$STORAGE/OEM"
  [ ! -d "$folder" ] && return 0

  local msg="Adding OEM folder to image..."
  info "$msg" && html "$msg"

  local dest="$src/\$OEM\$/\$1/OEM"
  mkdir -p "$dest" || return 1
  cp -Lr "$folder/." "$dest" || return 1

  local file
  file=$(find "$dest" -maxdepth 1 -type f -iname install.bat  -print -quit)
  [ -f "$file" ] && unix2dos -q "$file"

  return 0
}

prepareInstall() {

  local pid=""
  local file=""
  local dir="$2"
  local desc="$3"
  local driver="$4"
  local drivers="/tmp/drivers"

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

  if [[ "${driver,,}" == "xp" ]] || [[ "${driver,,}" == "2k3" ]]; then

    local msg="Adding drivers to image..."
    info "$msg" && html "$msg"

    rm -rf "$drivers"
    mkdir -p "$drivers"

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

    file=$(find "$target" -maxdepth 1 -type f -iname TXTSETUP.SIF -print -quit)

    if [ -z "$file" ]; then
      error "The file TXTSETUP.SIF could not be found!" && return 1
    fi

    sed -i '/^\[SCSI.Load\]/s/$/\nviostor=viostor.sys,4/' "$file"
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\nviostor.sys=1,,,,,,4_,4,1,,,1,4/' "$file"
    sed -i '/^\[SCSI\]/s/$/\nviostor=\"Red Hat VirtIO SCSI Disk Device\"/' "$file"
    sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00000000=\"viostor\"/' "$file"
    sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00020000=\"viostor\"/' "$file"
    sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00021AF4=\"viostor\"/' "$file"
    sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00000000=\"viostor\"/' "$file"

    if [ ! -d "$drivers/sata/xp/$arch" ]; then
      error "Failed to locate required SATA drivers!" && return 1
    fi

    mkdir -p "$dir/\$OEM\$/\$1/Drivers/sata" || return 1
    cp -Lr "$drivers/sata/xp/$arch/." "$dir/\$OEM\$/\$1/Drivers/sata" || return 1
    cp -Lr "$drivers/sata/xp/$arch/." "$target" || return 1

    sed -i '/^\[SCSI.Load\]/s/$/\niaStor=iaStor.sys,4/' "$file"
    sed -i '/^\[FileFlags\]/s/$/\niaStor.sys = 16/' "$file"
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.cat = 1,,,,,,,1,0,0/' "$file"
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.inf = 1,,,,,,,1,0,0/' "$file"
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.sys = 1,,,,,,4_,4,1,,,1,4/' "$file"
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.sys = 1,,,,,,,1,0,0/' "$file"
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaahci.cat = 1,,,,,,,1,0,0/' "$file"
    sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaAHCI.inf = 1,,,,,,,1,0,0/' "$file"
    sed -i '/^\[SCSI\]/s/$/\niaStor=\"Intel\(R\) SATA RAID\/AHCI Controller\"/' "$file"
    sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_8086\&DEV_2922\&CC_0106=\"iaStor\"/' "$file"

    rm -rf "$drivers"

  fi

  local key setup
  setup=$(find "$target" -maxdepth 1 -type f -iname setupp.ini -print -quit)

  if [ -n "$setup" ] && [ -z "$KEY" ]; then

    pid=$(<"$setup")
    pid="${pid%$'\r'}"

    if [[ "$driver" == "2k" ]]; then

      echo "${pid:0:$((${#pid})) - 3}270" > "$setup"

    else

      if [[ "$pid" == *"270" ]]; then

        warn "this version of $desc requires a volume license key (VLK), it will ask for one during installation."

      else

        file=$(find "$target" -maxdepth 1 -type f -iname PID.INF -print -quit)

        if [ -n "$file" ]; then

          if [[ "$driver" == "2k3" ]]; then

            key=$(grep -i -A 2 "StagingKey" "$file" | tail -n 2 | head -n 1)

          else

            key="${pid:$((${#pid})) - 8:5}"
            if [[ "${pid^^}" == *"OEM" ]]; then
              key=$(grep -i -A 2 "$key" "$file" | tail -n 2 | head -n 1)
            else
              key=$(grep -i -m 1 -A 2 "$key" "$file" | tail -n 2 | head -n 1)
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

          echo "${pid:0:$((${#pid})) - 3}000" > "$setup"

        fi

      fi
    fi

  fi

  [ -n "$KEY" ] && KEY="ProductID=$KEY"

  mkdir -p "$dir/\$OEM\$"

  if ! addFolder "$dir"; then
    error "Failed to add OEM folder to image!" && return 1
  fi

  local oem=""
  local install="$dir/\$OEM\$/\$1/OEM/install.bat"
  [ -f "$install" ] && oem="\"Script\"=\"cmd /C start \\\"Install\\\" \\\"cmd /C C:\\\\OEM\\\\install.bat\\\"\""

  [ -z "$WIDTH" ] && WIDTH="1280"
  [ -z "$HEIGHT" ] && HEIGHT="720"

  XHEX=$(printf '%x\n' "$WIDTH")
  YHEX=$(printf '%x\n' "$HEIGHT")

  local username=""
  local password=""

  [ -n "$USERNAME" ] && username=$(echo "$USERNAME" | sed 's/[^[:alnum:]@!._-]//g')
  [ -z "$username" ] && username="Docker"

  [ -n "$PASSWORD" ] && password=$(echo "$PASSWORD" | sed 's/"//g')
  [ -z "$password" ] && password="admin"

  local ip="20.20.20.1"
  [ -n "${VM_NET_IP:-}" ] && ip="${VM_NET_IP%.*}.1"

  find "$target" -maxdepth 1 -type f -iname winnt.sif -exec rm {} \;

  {       echo "[Data]"
          echo "    AutoPartition=1"
          echo "    MsDosInitiated=\"0\""
          echo "    UnattendedInstall=\"Yes\""
          echo "    AutomaticUpdates=\"Yes\""
          echo ""
          echo "[Unattended]"
          echo "    UnattendSwitch=Yes"
          echo "    UnattendMode=FullUnattended"
          echo "    FileSystem=NTFS"
          echo "    OemSkipEula=Yes"
          echo "    OemPreinstall=Yes"
          echo "    Repartition=Yes"
          echo "    WaitForReboot=\"No\""
          echo "    DriverSigningPolicy=\"Ignore\""
          echo "    NonDriverSigningPolicy=\"Ignore\""
          echo "    OemPnPDriversPath=\"Drivers\viostor;Drivers\NetKVM;Drivers\sata\""
          echo "    NoWaitAfterTextMode=1"
          echo "    NoWaitAfterGUIMode=1"
          echo "    FileSystem-ConvertNTFS"
          echo "    ExtendOemPartition=0"
          echo "    Hibernation=\"No\""
          echo ""
          echo "[GuiUnattended]"
          echo "    OEMSkipRegional=1"
          echo "    OemSkipWelcome=1"
          echo "    AdminPassword=$password"
          echo "    TimeZone=0"
          echo "    AutoLogon=Yes"
          echo "    AutoLogonCount=65432"
          echo ""
          echo "[UserData]"
          echo "    FullName=\"$username\""
          echo "    ComputerName=\"*\""
          echo "    OrgName=\"Windows for Docker\""
          echo "    $KEY"
          echo ""
          echo "[Identification]"
          echo "    JoinWorkgroup = WORKGROUP"
          echo ""
          echo "[Display]"
          echo "    BitsPerPel=32"
          echo "    XResolution=$WIDTH"
          echo "    YResolution=$HEIGHT"
          echo ""
          echo "[Networking]"
          echo "    InstallDefaultComponents=Yes"
          echo ""
          echo "[Branding]"
          echo "    BrandIEUsingUnattended=Yes"
          echo ""
          echo "[URL]"
          echo "    Home_Page = http://www.google.com"
          echo "    Search_Page = http://www.google.com"
          echo ""
          echo "[TerminalServices]"
          echo "    AllowConnections=1"
          echo ""
  } | unix2dos > "$target/WINNT.SIF"

  if [[ "$driver" == "2k3" ]]; then
    {       echo "[Components]"
            echo "    TerminalServer=On"
            echo ""
            echo "[LicenseFilePrintData]"
            echo "    AutoMode=PerServer"
            echo "    AutoUsers=5"
            echo ""
    } | unix2dos >> "$target/WINNT.SIF"
  fi

  {       echo "Windows Registry Editor Version 5.00"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Security]"
          echo "\"FirstRunDisabled\"=dword:00000001"
          echo "\"UpdatesDisableNotify\"=dword:00000001"
          echo "\"FirewallDisableNotify\"=dword:00000001"
          echo "\"AntiVirusDisableNotify\"=dword:00000001"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\wscsvc]"
          echo "\"Start\"=dword:00000004"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile\GloballyOpenPorts\List]"
          echo "\"3389:TCP\"=\"3389:TCP:*:Enabled:@xpsp2res.dll,-22009\""
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Applets\Tour]"
          echo "\"RunCount\"=dword:00000000"
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]"
          echo "\"HideFileExt\"=dword:00000000"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer]"
          echo "\"NoWelcomeScreen\"=\"1\""
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Internet Connection Wizard]"
          echo "\"Completed\"=\"1\""
          echo "\"Desktopchanged\"=\"1\""
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]"
          echo "\"AutoAdminLogon\"=\"1\""
          echo "\"DefaultUserName\"=\"$username\""
          echo "\"DefaultPassword\"=\"$password\""
          echo "\"DefaultDomainName\"=\"Dockur\""
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Video\{23A77BF7-ED96-40EC-AF06-9B1F4867732A}\0000]"
          echo "\"DefaultSettings.BitsPerPel\"=dword:00000020"
          echo "\"DefaultSettings.XResolution\"=dword:00000$XHEX"
          echo "\"DefaultSettings.YResolution\"=dword:00000$YHEX"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Control\VIDEO\{23A77BF7-ED96-40EC-AF06-9B1F4867732A}\0000]"
          echo "\"DefaultSettings.BitsPerPel\"=dword:00000020"
          echo "\"DefaultSettings.XResolution\"=dword:00000$XHEX"
          echo "\"DefaultSettings.YResolution\"=dword:00000$YHEX"
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce]"
          echo "\"ScreenSaver\"=\"reg add \\\"HKCU\\\\Control Panel\\\\Desktop\\\" /f /v \\\"SCRNSAVE.EXE\\\" /t REG_SZ /d \\\"off\\\"\""
          echo "\"ScreenSaverOff\"=\"reg add \\\"HKCU\\\\Control Panel\\\\Desktop\\\" /f /v \\\"ScreenSaveActive\\\" /t REG_SZ /d \\\"0\\\"\""
          echo "$oem"
          echo ""
  } | unix2dos > "$dir/\$OEM\$/install.reg"

  if [[ "$driver" == "2k" ]]; then
    {       echo "[HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Runonce]"
            echo "\"^SetupICWDesktop\"=-"
            echo ""
    } | unix2dos >> "$dir/\$OEM\$/install.reg"
  fi

  if [[ "$driver" == "2k3" ]]; then
    {       echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\srvWiz]"
            echo "@=dword:00000000"
            echo ""
            echo "[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\ServerOOBE\SecurityOOBE]"
            echo "\"DontLaunchSecurityOOBE\"=dword:00000000"
            echo ""
    } | unix2dos >> "$dir/\$OEM\$/install.reg"
  fi

  {       echo "Set WshShell = WScript.CreateObject(\"WScript.Shell\")"
          echo "Set WshNetwork = WScript.CreateObject(\"WScript.Network\")"
          echo "Set Domain = GetObject(\"WinNT://\" & WshNetwork.ComputerName)"
          echo ""
          echo "Function DecodeSID(binSID)"
          echo "  ReDim o(LenB(binSID))"
          echo ""
          echo "  For i = 1 To LenB(binSID)"
          echo "    o(i-1) = AscB(MidB(binSID, i, 1))"
          echo "  Next"
          echo ""
          echo "  sid = \"S-\" & CStr(o(0)) & \"-\" & OctetArrayToString _"
          echo "        (Array(o(2), o(3), o(4), o(5), o(6), o(7)))"
          echo "  For i = 8 To (4 * o(1) + 4) Step 4"
          echo "    sid = sid & \"-\" & OctetArrayToString _"
          echo "          (Array(o(i+3), o(i+2), o(i+1), o(i)))"
          echo "  Next"
          echo ""
          echo "  DecodeSID = sid"
          echo "End Function"
          echo ""
          echo "Function OctetArrayToString(arr)"
          echo "  v = 0"
          echo "  For i = 0 To UBound(arr)"
          echo "    v = v * 256 + arr(i)"
          echo "  Next"
          echo ""
          echo "  OctetArrayToString = CStr(v)"
          echo "End Function"
          echo ""
          echo "For Each DomainItem in Domain"
          echo "  If DomainItem.Class = \"User\" Then"
          echo "    sid = DecodeSID(DomainItem.Get(\"objectSID\"))"
          echo "    If Left(sid, 9) = \"S-1-5-21-\" And Right(sid, 4) = \"-500\" Then"
          echo "      LocalAdminADsPath = DomainItem.ADsPath"
          echo "      Exit For"
          echo "    End If"
          echo "  End If"
          echo "Next"
          echo ""
          echo "Call Domain.MoveHere(LocalAdminADsPath, \"$username\")"
          echo ""
          echo "With (CreateObject(\"Scripting.FileSystemObject\"))"
          echo "  SysRoot = WshShell.ExpandEnvironmentStrings(\"%SystemRoot%\")"
          echo "  Set oFile = .OpenTextFile(SysRoot & \"\system32\drivers\etc\hosts\", 8, true)"
          echo "  oFile.Write(\"$ip      host.lan\")"
          echo "  oFile.Close()"
          echo "  Set oFile = Nothing"
          echo "End With"
          echo ""
  } | unix2dos > "$dir/\$OEM\$/admin.vbs"

  {       echo "[COMMANDS]"
          echo "\"REGEDIT /s install.reg\""
          echo "\"Wscript admin.vbs\""
          echo ""
  } | unix2dos > "$dir/\$OEM\$/cmdlines.txt"

  return 0
}

prepareLegacy() {

  local iso="$1"
  local dir="$2"
  local desc="$3"

  ETFS="boot.img"

  [ -f "$dir/$ETFS" ] && [ -s "$dir/$ETFS" ] && return 0
  rm -f "$dir/$ETFS"

  local len offset
  len=$(isoinfo -d -i "$iso" | grep "Nsect " | grep -o "[^ ]*$")
  offset=$(isoinfo -d -i "$iso" | grep "Bootoff " | grep -o "[^ ]*$")

  if ! dd "if=$iso" "of=$dir/$ETFS" bs=2048 "count=$len" "skip=$offset" status=none; then
    error "Failed to extract boot image from $desc ISO!" && return 1
  fi

  [ -f "$dir/$ETFS" ] && [ -s "$dir/$ETFS" ] && return 0

  error "Failed to locate file \"$ETFS\" in $desc ISO image!"
  return 1
}

detectLegacy() {

  local dir="$1"
  local find

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
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51IS -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51AA -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51AD -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51AS -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51MA -print -quit)
    [ -z "$find" ] && find=$(find "$dir" -maxdepth 1 -type f -iname WIN51MD -print -quit)
    [ -n "$find" ] && DETECTED="win2003r2" && return 0

  fi

  return 1
}

skipVersion() {

  local id="$1"

  case "${id,,}" in
    "win9"* | "winxp"* | "win2k"* | "win2003"* )
      return 0 ;;
  esac

  return 1
}

setMachine() {

  local id="$1"
  local iso="$2"
  local dir="$3"
  local desc="$4"

  case "${id,,}" in
    "win9"* )
      ETFS="[BOOT]/Boot-1.44M.img" ;;
    "win2k"* )
      if ! prepareInstall "$iso" "$dir" "$desc" "2k"; then
        error "Failed to prepare $desc ISO!" && return 1
      fi ;;
    "winxp"* )
      if ! prepareInstall "$iso" "$dir" "$desc" "xp"; then
        error "Failed to prepare $desc ISO!" && return 1
      fi ;;
    "win2003"* )
      if ! prepareInstall "$iso" "$dir" "$desc" "2k3"; then
        error "Failed to prepare $desc ISO!" && return 1
      fi ;;
  esac

  case "${id,,}" in
    "win9"* )
      USB="no"
      VGA="cirrus"
      DISK_TYPE="auto"
      ADAPTER="rtl8139"
      MACHINE="pc-i440fx-2.4"
      BOOT_MODE="windows_legacy" ;;
    "win2k"* )
      VGA="cirrus"
      MACHINE="pc"
      USB="pci-ohci"
      DISK_TYPE="auto"
      ADAPTER="rtl8139"
      BOOT_MODE="windows_legacy" ;;
    "winxp"* | "win2003"* )
      DISK_TYPE="blk"
      BOOT_MODE="windows_legacy" ;;
    "winvista"* | "win7"* | "win2008"* )
      BOOT_MODE="windows_legacy" ;;
  esac

  case "${id,,}" in
    "winxp"* | "win2003"* | "winvistax86"* | "win7x86"* | "win2008r2x86"* )
      # Prevent bluescreen if 64 bit PCI hole size is >2G.
      ARGS="-global q35-pcihost.x-pci-hole64-fix=false" ;;
  esac

  return 0
}

return 0
