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
EDITION=$(strip "$EDITION")
KEYBOARD=$(strip "$KEYBOARD")
LANGUAGE=$(strip "$LANGUAGE")
USERNAME=$(strip "$USERNAME")
DOMAIN_OU=$(strip "$DOMAIN_OU")
WORKGROUP=$(strip "$WORKGROUP")

MIRRORS=4

parseVersion() {

  DETECTED=""
  VERSION=$(strip "$VERSION")
  [ -z "$VERSION" ] && VERSION="win11"

  case "${VERSION,,}" in
    "11" | "11p" | "win11" | "pro11" | "win11p" | "windows11" | "windows 11" )
      VERSION="win11x64" ;;
    "11e" | "win11e" | "windows11e" | "windows 11e" )
      VERSION="win11x64-enterprise-eval" ;;
    "11l" | "11ltsc" | "ltsc11" | "win11l" | "win11-ltsc" | "win11x64-ltsc" )
      VERSION="win11x64-enterprise-ltsc-eval" ;;
    "11i" | "11iot" | "iot11" | "win11i" | "win11-iot" | "win11x64-iot" )
      VERSION="win11x64-enterprise-iot-eval" ;;
    "10" | "10p" | "win10" | "pro10" | "win10p" | "windows10" | "windows 10" )
      VERSION="win10x64" ;;
    "10e" | "win10e" | "windows10e" | "windows 10e" )
      VERSION="win10x64-enterprise-eval" ;;
    "10l" | "10ltsc" | "ltsc10" | "win10l" | "win10-ltsc" | "win10x64-ltsc" )
      VERSION="win10x64-enterprise-ltsc-eval" ;;
    "10i" | "10iot" | "iot10" | "win10i" | "win10-iot" | "win10x64-iot" )
      VERSION="win10x64-enterprise-iot-eval" ;;
    "8" | "8p" | "81" | "81p" | "pro8" | "8.1" | "win8" | "win8p" | "win81" | "win81p" | "windows 8" )
      VERSION="win81x64" ;;
    "8e" | "81e" | "8.1e" | "win8e" | "win81e" | "windows 8e" )
      VERSION="win81x64-enterprise-eval" ;;
    "7" | "win7" | "windows7" | "windows 7" )
      VERSION="win7x64" ;;
    "7u" | "win7u" | "windows7u" | "windows 7u" )
      VERSION="win7x64-ultimate" ;;
    "7e" | "win7e" | "windows7e" | "windows 7e" )
      VERSION="win7x64-enterprise" ;;
    "7x86" | "win7x86" | "win732" | "windows7x86" )
      VERSION="win7x86" ;;
    "7ux86" | "7u32" | "win7x86-ultimate" )
      VERSION="win7x86-ultimate" ;;
    "7ex86" | "7e32" | "win7x86-enterprise" )
      VERSION="win7x86-enterprise" ;;
    "vista" | "vs" | "6" | "winvista" | "windowsvista" | "windows vista" )
      VERSION="winvistax64" ;;
    "vistu" | "vu" | "6u" | "winvistu" )
      VERSION="winvistax64-ultimate" ;;
    "viste" | "ve" | "6e" | "winviste" )
      VERSION="winvistax64-enterprise" ;;
    "vistax86" | "vista32" | "6x86" | "winvistax86" | "windowsvistax86" )
      VERSION="winvistax86" ;;
    "vux86" | "vu32" | "winvistax86-ultimate" )
      VERSION="winvistax86-ultimate" ;;
    "vex86" | "ve32" | "winvistax86-enterprise" )
      VERSION="winvistax86-enterprise" ;;
    "xp" | "xp32" | "xpx86" | "5" | "5x86" | "winxp" | "winxp86" | "windowsxp" | "windows xp" )
      VERSION="winxpx86" ;;
    "xp64" | "xpx64" | "5x64" | "winxp64" | "winxpx64" | "windowsxp64" | "windowsxpx64" )
      VERSION="winxpx64" ;;
    "2k" | "2000" | "win2k" | "win2000" | "windows2k" | "windows2000" )
      VERSION="win2kx86" ;;
    "me" | "winme" | "win9x" | "windowsme" | "windows me" )
      VERSION="win9x" ;;
    "98" | "98se" | "win98" | "win98se" | "windows98" | "windows98se" | "windows 98" | "windows 98 se" )
      VERSION="win98" ;;
    "95" | "95c" | "win95" | "win95c" | "windows95" | "windows 95" )
      VERSION="win95" ;;
    "25" | "2025" | "win25" | "win2025" | "windows2025" | "windows 2025" )
      VERSION="win2025-eval" ;;
    "22" | "2022" | "win22" | "win2022" | "windows2022" | "windows 2022" )
      VERSION="win2022-eval" ;;
    "19" | "2019" | "win19" | "win2019" | "windows2019" | "windows 2019" )
      VERSION="win2019-eval" ;;
    "16" | "2016" | "win16" | "win2016" | "windows2016" | "windows 2016" )
      VERSION="win2016-eval" ;;
    "hv" | "hyperv" | "hyper v" | "hyper-v" | "19hv" | "2019hv" | "win2019hv" )
      VERSION="win2019-hv" ;;
    "2012" | "2012r2" | "win2012" | "win2012r2" | "windows2012" | "windows 2012" )
      VERSION="win2012r2-eval" ;;
    "2008" | "2008r2" | "win2008" | "win2008r2" | "windows2008" | "windows 2008" )
      VERSION="win2008r2" ;;
    "2003" | "2003r2" | "win2003" | "win2003r2" | "windows2003" | "windows 2003" )
      VERSION="win2003r2" ;;
    "core11" | "core 11" )
      VERSION="core11"
      DETECTED="win11x64" ;;
    "tiny11" | "tiny 11" )
      VERSION="tiny11"
      DETECTED="win11x64" ;;
    "tiny10" | "tiny 10" )
      VERSION="tiny10"
      DETECTED="win10x64-ltsc" ;;
    "reactos" | "react os" )
      VERSION="reactos" ;;
  esac

  return 0
}

getLanguage() {

  local source="$1"
  local input="${1,,}"
  local ret="$2"

  local id="$source" lang="" desc="" short="" culture=""

  case "$input" in
    "ar" | "ar-"* | "arabic" | "arab" )
      [[ "$input" == "arabic" || "$input" == "arab" ]] && id="ar"
      short="ar"
      lang="Arabic"
      culture="ar-SA" ;;
    "bg" | "bg-"* | "bulgarian" | "bu" )
      [[ "$input" == "bulgarian" || "$input" == "bu" ]] && id="bg"
      short="bg"
      lang="Bulgarian"
      culture="bg-BG" ;;
    "cs" | "cs-"* | "cz" | "cz-"* | "czech" | "cesky" )
      [[ "$input" == "cz" || "$input" == "czech" || "$input" == "cesky" ]] && id="cs"
      short="cs"
      lang="Czech"
      culture="cs-CZ" ;;
    "da" | "da-"* | "dk" | "dk-"* | "danish" | "danske" )
      [[ "$input" == "dk" || "$input" == "danish" || "$input" == "danske" ]] && id="da"
      short="da"
      lang="Danish"
      culture="da-DK" ;;
    "de" | "de-"* | "german" | "deutsch" )
      [[ "$input" == "german" || "$input" == "deutsch" ]] && id="de"
      short="de"
      lang="German"
      culture="de-DE" ;;
    "el" | "el-"* | "gr" | "gr-"* | "greek" )
      [[ "$input" == "gr" || "$input" == "greek" ]] && id="el"
      short="el"
      lang="Greek"
      culture="el-GR" ;;
    "gb" | "en-gb" | "british" )
      [[ "$input" == "gb" || "$input" == "british" ]] && id="en-gb"
      short="en-gb"
      lang="English International"
      desc="English"
      culture="en-GB" ;;
    "en" | "en-"* | "english" )
      [[ "$input" == "english" ]] && id="en"
      short="en"
      lang="English"
      culture="en-US" ;;
    "mx" | "es-mx" )
      short="mx"
      lang="Spanish (Mexico)"
      desc="Spanish"
      culture="es-MX" ;;
    "es" | "es-"* | "spanish" | "espanol" | "español" )
      [[ "$input" == "spanish" || "$input" == "espanol" || "$input" == "español" ]] && id="es"
      short="es"
      lang="Spanish"
      culture="es-ES" ;;
    "et" | "et-"* | "estonian" | "eesti" )
      [[ "$input" == "estonian" || "$input" == "eesti" ]] && id="et"
      short="et"
      lang="Estonian"
      culture="et-EE" ;;
    "fi" | "fi-"* | "finnish" | "suomi" )
      [[ "$input" == "finnish" || "$input" == "suomi" ]] && id="fi"
      short="fi"
      lang="Finnish"
      culture="fi-FI" ;;
    "ca" | "fr-ca" )
      short="ca"
      lang="French Canadian"
      desc="French"
      culture="fr-CA" ;;
    "fr" | "fr-"* | "french" | "français" | "francais" )
      [[ "$input" == "french" || "$input" == "français" || "$input" == "francais" ]] && id="fr"
      short="fr"
      lang="French"
      culture="fr-FR" ;;
    "he" | "he-"* | "il" | "il-"* | "hebrew" )
      [[ "$input" == "il" || "$input" == "hebrew" ]] && id="he"
      short="he"
      lang="Hebrew"
      culture="he-IL" ;;
    "hr" | "hr-"* | "cr" | "cr-"* | "croatian" | "hrvatski" )
      [[ "$input" == "cr" || "$input" == "croatian" || "$input" == "hrvatski" ]] && id="hr"
      short="hr"
      lang="Croatian"
      culture="hr-HR" ;;
    "hu" | "hu-"* | "hungarian" | "magyar" )
      [[ "$input" == "hungarian" || "$input" == "magyar" ]] && id="hu"
      short="hu"
      lang="Hungarian"
      culture="hu-HU" ;;
    "it" | "it-"* | "italian" | "italiano" )
      [[ "$input" == "italian" || "$input" == "italiano" ]] && id="it"
      short="it"
      lang="Italian"
      culture="it-IT" ;;
    "ja" | "ja-"* | "jp" | "jp-"* | "japanese" )
      [[ "$input" == "jp" || "$input" == "japanese" ]] && id="ja"
      short="ja"
      lang="Japanese"
      culture="ja-JP" ;;
    "ko" | "ko-"* | "kr" | "kr-"* | "korean" )
      [[ "$input" == "kr" || "$input" == "korean" ]] && id="ko"
      short="ko"
      lang="Korean"
      culture="ko-KR" ;;
    "lt" | "lt-"* | "lithuanian" | "lietuvos" )
      [[ "$input" == "lithuanian" || "$input" == "lietuvos" ]] && id="lt"
      short="lt"
      lang="Lithuanian"
      culture="lt-LT" ;;
    "lv" | "lv-"* | "latvian" | "latvijas" )
      [[ "$input" == "latvian" || "$input" == "latvijas" ]] && id="lv"
      short="lv"
      lang="Latvian"
      culture="lv-LV" ;;
    "nb" | "nb-"* | "nn" | "nn-"* | "no" | "no-"* | "norwegian" | "norsk" )
      [[ "$input" == "nb" || "$input" == "no" || "$input" == "norwegian" || "$input" == "norsk" ]] && id="nn"
      short="no"
      lang="Norwegian"
      culture="nb-NO" ;;
    "nl" | "nl-"* | "dutch" | "nederlands" )
      [[ "$input" == "dutch" || "$input" == "nederlands" ]] && id="nl"
      short="nl"
      lang="Dutch"
      culture="nl-NL" ;;
    "pl" | "pl-"* | "polish" | "polski" )
      [[ "$input" == "polish" || "$input" == "polski" ]] && id="pl"
      short="pl"
      lang="Polish"
      culture="pl-PL" ;;
    "br" | "pt" | "pt-br" | "portuguese" | "português" | "portugues" )
      [[ "$input" == "pt-br" ]] || id="pt-br"
      short="pt"
      lang="Brazilian Portuguese"
      desc="Portuguese"
      culture="pt-BR" ;;
    "pt-"* )
      short="pp"
      lang="Portuguese"
      culture="pt-PT" ;;
    "ro" | "ro-"* | "romanian" | "română" | "romana" )
      [[ "$input" == "romanian" || "$input" == "română" || "$input" == "romana" ]] && id="ro"
      short="ro"
      lang="Romanian"
      culture="ro-RO" ;;
    "ru" | "ru-"* | "russian" | "ruski" )
      [[ "$input" == "russian" || "$input" == "ruski" ]] && id="ru"
      short="ru"
      lang="Russian"
      culture="ru-RU" ;;
    "sk" | "sk-"* | "slovak" | "slovenský" | "slovensky" )
      [[ "$input" == "slovak" || "$input" == "slovenský" || "$input" == "slovensky" ]] && id="sk"
      short="sk"
      lang="Slovak"
      culture="sk-SK" ;;
    "sl" | "sl-"* | "si" | "si-"* | "slovenian" | "slovenski" )
      [[ "$input" == "si" || "$input" == "slovenian" || "$input" == "slovenski" ]] && id="sl"
      short="sl"
      lang="Slovenian"
      culture="sl-SI" ;;
    "sr" | "sr-"* | "serbian" | "serbian latin" )
      [[ "$input" == "serbian" || "$input" == "serbian latin" ]] && id="sr"
      short="sr"
      lang="Serbian Latin"
      desc="Serbian"
      culture="sr-Latn-RS" ;;
    "sv" | "sv-"* | "se" | "se-"* | "swedish" | "svenska" )
      [[ "$input" == "se" || "$input" == "swedish" || "$input" == "svenska" ]] && id="sv"
      short="sv"
      lang="Swedish"
      culture="sv-SE" ;;
    "th" | "th-"* | "thai" )
      [[ "$input" == "thai" ]] && id="th"
      short="th"
      lang="Thai"
      culture="th-TH" ;;
    "tr" | "tr-"* | "turkish" | "türk" | "turk" )
      [[ "$input" == "turkish" || "$input" == "türk" || "$input" == "turk" ]] && id="tr"
      short="tr"
      lang="Turkish"
      culture="tr-TR" ;;
    "ua" | "ua-"* | "uk" | "uk-"* | "ukrainian" )
      [[ "$input" == "ua" || "$input" == "ukrainian" ]] && id="uk"
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
    "zh" | "zh-"* | "cn" | "cn-"* | "chinese" )
      [[ "$input" == "cn" || "$input" == "chinese" ]] && id="zh"
      short="cn"
      lang="Chinese (Simplified)"
      desc="Chinese"
      culture="zh-CN" ;;
  esac

  [ -z "$lang" ] && return 0
  [ -z "$desc" ] && desc="$lang"

  case "${ret,,}" in
    "id" ) echo "$id" ;;
    "desc" ) echo "$desc" ;;
    "name" ) echo "$lang" ;;
    "code" ) echo "$short" ;;
    "culture" ) echo "$culture" ;;
    * ) echo "$desc";;
  esac

  return 0
}

parseLanguage() {

  REGION="${REGION//_/-}"
  KEYBOARD="${KEYBOARD//_/-}"
  LANGUAGE="${LANGUAGE//_/-}"

  [ -z "$LANGUAGE" ] && LANGUAGE="en"

  local id
  id=$(getLanguage "$LANGUAGE" "id")

  if [ -z "$id" ]; then
    error "Invalid LANGUAGE specified, value \"$LANGUAGE\" is not recognized!"
    return 1
  fi

  LANGUAGE="$id"
  return 0
}

printVersion() {

  local id="$1"
  local desc="$2"

  case "${id,,}" in
    "tiny11"* ) desc="Tiny 11" ;;
    "tiny10"* ) desc="Tiny 10" ;;
    "core11"* ) desc="Core 11" ;;
    "reactos"* ) desc="ReactOS" ;;
    "win7"* ) desc="Windows 7" ;;
    "win8"* ) desc="Windows 8" ;;
    "win10"* ) desc="Windows 10" ;;
    "win11"* ) desc="Windows 11" ;;
    "winxp"* ) desc="Windows XP" ;;
    "win9x"* ) desc="Windows ME" ;;
    "win98"* ) desc="Windows 98" ;;
    "win95"* ) desc="Windows 95" ;;
    "winnt4"* ) desc="Windows NT 4" ;;
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
    isPlatform "x64" || desc+=" for ${PLATFORM}"
  fi

  echo "$desc"
  return 0
}

printVariant() {

  local id="$1"
  local desc="$2"
  local show_eval="${3:-N}"

  desc=$(printVersion "$id" "$desc") || return 1

  case "${id,,}" in
    *"-iot" | *"-iot-eval" )
      desc+=" IoT" ;;
    *"-ltsc" | *"-ltsc-eval" )
      desc+=" LTSC" ;;
    *"-enterprise" | *"-enterprise-eval" )
      desc+=" Enterprise" ;;
  esac

  if enabled "$show_eval" && [[ "${id,,}" == *"-eval" ]]; then
    desc+=" (Evaluation)"
  fi

  echo "$desc"
  return 0
}

formatEdition() {

  local edition="${1//-/ }"
  local result="" word

  for word in $edition; do
    if [ "$word" == "for" ]; then
      word="for"
    elif [ "${#word}" -eq 1 ]; then
      word="${word^^}"
    else
      word="${word^}"
    fi

    result+="${result:+ }$word"
  done

  echo "$result"
  return 0
}

printEdition() {

  local id="$1"
  local desc="$2"
  local show_eval="${3:-N}"

  local normalized="${id,,}"
  local result edition="" suffix=""

  result=$(printVersion "$id" "x")
  [[ "$result" == "x" ]] && echo "$desc" && return 0

  normalized="${normalized%-eval}"

  case "$normalized" in
    "winvista"* | "win7"* | "win8"* | "win10"* | "win11"* )
      [[ "$normalized" == *"-"* ]] && suffix="${normalized#*-}"

      case "$suffix" in
        "" )
          case "$normalized" in
            "winvista"* ) edition="Business" ;;
            "win7"* ) edition="Professional" ;;
            * ) edition="Pro" ;;
          esac
          ;;
        "home" )
          edition="Home" ;;
        "starter" )
          edition="Starter" ;;
        "ultimate" )
          edition="Ultimate" ;;
        "enterprise" )
          edition="Enterprise" ;;
        "education" )
          edition="Education" ;;
        "n" )
          case "$normalized" in
            "win7"* ) edition="Professional N" ;;
            * ) edition="Pro N" ;;
          esac
          ;;
        "iot" | "enterprise-iot" )
          edition="IoT Enterprise LTSC" ;;
        "ltsc" | "enterprise-ltsc" )
          edition="Enterprise LTSC" ;;
        * )
          edition=$(formatEdition "$suffix")
          ;;
      esac
      ;;
    "winxp"* )
      edition="Professional" ;;
    "win2019-hv"* )
      edition="2019" ;;
    "win20"* )
      [[ "$normalized" == *"-"* ]] && suffix="${normalized#*-}"

      if [ -n "$suffix" ]; then
        edition=$(formatEdition "$suffix")
      else
        case "${EDITION^^}" in
          *"DATACENTER"* ) edition="Datacenter" ;;
          "CORE" | "STANDARDCORE" ) edition="Core" ;;
          * ) edition="Standard" ;;
        esac
      fi
      ;;
  esac

  [ -n "$edition" ] && result+=" $edition"

  if enabled "$show_eval" && [[ "${id,,}" == *"-eval" ]]; then
    result+=" (Evaluation)"
  fi

  echo "$result"
  return 0
}

fromFile() {

  local desc="$1"
  local file="${1,,}"

  local id="" arch="${PLATFORM,,}"

  file="${file//-/_}"
  file="${file// /_}"

  case "$file" in
    *"_x64_"* | *"_x64."*)
      arch="x64" ;;
    *"_x86_"* | *"_x86."*)
      arch="x86" ;;
    *"_arm64_"* | *"_arm64."*)
      arch="arm64" ;;
  esac

  local add=""
  [[ "$arch" != "x64" ]] && add="$arch"

  case "$file" in
    "win7"* | "win_7"* | *"windows7"* | *"windows_7"* )
      id="win7${arch}" ;;
    "win8"* | "win_8"* | *"windows8"* | *"windows_8"* )
      id="win81${arch}" ;;
    "win10"*| "win_10"* | *"windows10"* | *"windows_10"* )
      id="win10${arch}" ;;
    "win11"* | "win_11"* | *"windows11"* | *"windows_11"* )
      id="win11${arch}" ;;
    *"winxp"* | *"win_xp"* | *"windowsxp"* | *"windows_xp"* )
      id="winxpx86" ;;
    *"winme"* | *"win_me"* | *"win9x"* | *"windowsme"* | *"windows_me"* )
      id="win9x" ;;
    *"win98"* | *"win_98"* | *"windows98"* | *"windows_98"* )
      id="win98" ;;
    *"win95"* | *"win_95"* | *"windows95"* | *"windows_95"* )
      id="win95" ;;
    *"winnt4"* | *"win_nt4"* | *"windowsnt4"* | *"windows_nt4"* | *"windows_nt_4"* )
      id="winnt4" ;;
    *"winvista"* | *"win_vista"* | *"windowsvista"* | *"windows_vista"* )
      id="winvista${arch}" ;;
    "tiny11core"* | "tiny11_core"* | "tiny_11_core"* )
      id="core11" ;;
    "tiny11"* | "tiny_11"* )
      id="tiny11" ;;
    "tiny10"* | "tiny_10"* )
      id="tiny10" ;;
    "reactos"* )
      id="reactos" ;;
    *"_serverhypercore_"* )
      id="win2019${add}-hv" ;;
    *"server2025"* | *"server_2025"* )
      id="win2025${add}" ;;
    *"server2022"* | *"server_2022"* )
      id="win2022${add}" ;;
    *"server2019"* | *"server_2019"* )
      id="win2019${add}" ;;
    *"server2016"* | *"server_2016"* )
      id="win2016${add}" ;;
    *"server2012"* | *"server_2012"* )
      id="win2012r2${add}" ;;
    *"server2008"* | *"server_2008"* )
      id="win2008r2${add}" ;;
    *"server2003"* | *"server_2003"* )
      id="win2003r2${add}" ;;
  esac

  if [ -n "$id" ]; then
    desc=$(printVersion "$id" "$desc")
  fi

  echo "$desc"
  return 0
}

fromName() {

  local name="$1"
  local arch="$2"

  local id=""

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

  local name="$1"
  local arch="$2"

  local id edition
  local evaluation=""

  id=$(fromName "$name" "$arch")
  [ -z "$id" ] && return 0

  [[ "${name,,}" == *"evaluation"* ]] && evaluation="-eval"

  case "${id,,}" in

    "win20"* )

      if [[ "${name,,}" == *"hyper-v server"* ]]; then
        id+="-hv"
      elif edition=$(getServerEditionID "$name" "$id"); then
        [ -n "$edition" ] && id+="-$edition"
        [ -n "$evaluation" ] && id+="$evaluation"
      fi ;;

    * )

      if edition=$(getEditionID "$name" "$id"); then
        [ -n "$edition" ] && id+="-$edition"
        [ -n "$evaluation" ] && id+="$evaluation"
      fi ;;

  esac

  echo "$id"
  return 0
}

isClientEdition() {

  case "${1,,}" in
    "pro" | "professional" | "business" | \
    "enterprise" | "ultimate" | "education" | \
    "home" | "homepremium" | "home-premium" | \
    "homebasic" | "home-basic" | "starter" | "core" )
      return 0 ;;
  esac

  return 1
}

getEditionRank() {

  local id="${1,,}"
  local base="${id%%-*}"
  local edition

  id="${id%-eval}"
  edition="${id#"$base"}"
  edition="${edition#-}"

  case "$base" in
    "win20"* )

      case "$edition" in
        "" ) echo 0 ;;
        "datacenter-azure-core" | "datacenter-azure-core-"* | \
        "datacenter-core" | "datacenter-core-"* ) echo 7 ;;
        "enterprise-core" | "enterprise-core-"* ) echo 8 ;;
        "web-core" | "web-core-"* ) echo 9 ;;
        "standard-core" | "standard-core-"* ) echo 6 ;;
        "datacenter" | "datacenter-"* ) echo 1 ;;
        "enterprise" | "enterprise-"* ) echo 2 ;;
        "web" | "web-"* ) echo 3 ;;
        "foundation" | "foundation-"* ) echo 4 ;;
        "essentials" | "essentials-"* ) echo 5 ;;
        "hv" | "hv-"* ) echo 10 ;;
        * ) echo 99 ;;
      esac ;;

    * )

      case "$edition" in
        "enterprise-iot" | "enterprise-iot-"* | "iot" | "iot-"* ) echo 3 ;;
        "enterprise-ltsc" | "enterprise-ltsc-"* | "ltsc" | "ltsc-"* ) echo 4 ;;
        "pro-education" | "pro-education-"* | "education" | "education-"* ) echo 5 ;;
        "enterprise" | "enterprise-"* ) echo 0 ;;
        "ultimate" | "ultimate-"* ) echo 1 ;;
        "" | "n" | "pro" | "pro-"* | "professional" | "professional-"* | \
        "business" | "business-"* ) echo 2 ;;
        "home" | "home-"* ) echo 6 ;;
        "starter" | "starter-"* ) echo 7 ;;
        * ) echo 99 ;;
      esac ;;

  esac

  return 0
}

getEditionPolicy() {

  local base="${1,,}"

  case "$base" in

    "win20"* )
      printf '%s\n' \
        "normalizeServerEditionID" \
        "" \
        "-datacenter" \
        "-datacenter-azure" \
        "-enterprise" \
        "-web" \
        "-foundation" \
        "-essentials" \
        "-standard-core" \
        "-datacenter-core" \
        "-datacenter-azure-core" \
        "-enterprise-core" \
        "-web-core" \
        "-hv" ;;

    * )

      printf '%s\n' \
        "normalizeEditionID" \
        "-enterprise" \
        "-ultimate" \
        "" \
        "-iot" \
        "-ltsc" \
        "-education" \
        "-home" \
        "-home-premium" \
        "-home-basic" \
        "-starter" ;;

  esac

  return 0
}

normalizeEdition() {

  local source="${1,,}"
  local edition transliterated

  source="${source//evaluation/}"

  if transliterated=$(printf '%s' "$source" |
    uconv -x 'Any-Latin; Latin-ASCII' 2>/dev/null); then
    source="$transliterated"
  fi

  edition=$(sed -E \
    -e 's/[^a-z0-9]+/-/g' \
    -e 's/^-+//' \
    -e 's/-+$//' \
    <<< "$source") || edition=""

  echo "$edition"
  return 0
}

normalizeEditionID() {

  local edition base
  local id="$2"

  edition=$(normalizeEdition "$1") || return 1

  case "$edition" in

    "pro" | "professional" | "business" )
      edition="" ;;

    "pro-n" | "pron" | "professional-n" | "professionaln" | "business-n" | "businessn" )
      edition="n" ;;

    * )

      if ! isClientEdition "$edition"; then
        case "$edition" in
          *"-n" ) base="${edition%-n}" ;;
          *"n" ) base="${edition%n}" ;;
          * ) base="" ;;
        esac

        if [ -n "$base" ] && isClientEdition "$base"; then
          edition="$base-n"
        fi

      fi ;;
  
  esac

  case "${id,,}" in

    "win10"* | "win11"* )

      case "$edition" in
        "iot-enterprise-ltsc" | \
        "iot-enterprise-ltsc-"[0-9][0-9][0-9][0-9] )
          edition="iot" ;;
        "enterprise-ltsc" | \
        "enterprise-ltsc-"[0-9][0-9][0-9][0-9] )
          edition="ltsc" ;;
      esac ;;

  esac

  echo "$edition"
  return 0
}

getEditionID() {

  local name="${1,,}"
  local id="${2,,}"

  local edition

  case "$id" in
    "winvista"* )
      edition="${name#*vista}" ;;
    "win7"* )
      edition="${name#*7}" ;;
    "win8"* )
      if [[ "$name" == *"8.1"* ]]; then
        edition="${name#*8.1}"
      else
        edition="${name#*8}"
      fi ;;
    "win10"* )
      edition="${name#*10}" ;;
    "win11"* )
      edition="${name#*11}" ;;
    * ) return 1 ;;
  esac

  edition=$(normalizeEditionID "$edition" "$id") || return 1

  echo "$edition"
  return 0
}

normalizeServerEdition() {

  local edition

  edition=$(normalizeEdition "$1") || return 1
  edition="${edition#r2-}"

  case "$edition" in
    "core" | "server-core" | "servercore" | \
    "core-installation" | "server-core-installation" )
      edition="standard-core" ;;
    "desktop-experience" | "server-with-a-gui" | "full-installation" )
      edition="standard" ;;
    *"-server-core-installation" | *"-core-installation" )
      edition="${edition%-server-core-installation}"
      edition="${edition%-core-installation}-core" ;;
    *"-desktop-experience" | *"-server-with-a-gui" | *"-full-installation" )
      edition="${edition%-desktop-experience}"
      edition="${edition%-server-with-a-gui}"
      edition="${edition%-full-installation}" ;;
  esac

  edition="${edition#server-}"
  edition="${edition#server}"

  echo "$edition"
  return 0
}

normalizeServerEditionID() {

  local edition

  edition=$(normalizeServerEdition "$1") || return 1

  case "$edition" in
    "standard" ) edition="" ;;
    "standardcore" | "datacentercore" | "enterprisecore" | "webcore" )
      edition="${edition%core}-core" ;;
    "datacenter-azure-edition" | "datacenterazureedition" )
      edition="datacenter-azure" ;;
    "datacenter-azure-edition-core" | "datacenterazureeditioncore" )
      edition="datacenter-azure-core" ;;
  esac

  echo "$edition"
  return 0
}

getServerEditionID() {

  local name="${1,,}"
  local id="${2,,}"

  local edition

  case "$id" in
    "win2025"* ) edition="${name#*server 2025}" ;;
    "win2022"* ) edition="${name#*server 2022}" ;;
    "win2019"* ) edition="${name#*server 2019}" ;;
    "win2016"* ) edition="${name#*server 2016}" ;;
    "win2012"* ) edition="${name#*server 2012}" ;;
    "win2008"* ) edition="${name#*server 2008}" ;;
    "win2003"* ) edition="${name#*server 2003}" ;;
    * ) return 1 ;;
  esac

  edition=$(normalizeServerEditionID "$edition") || return 1

  echo "$edition"
  return 0
}

getRequiredMemory() {

  local id="${1,,}"

  case "$id" in
    "win11"* )
      echo "2G" ;;
    "tiny11"* | "core11"* )
      echo "2G" ;;
    "win10"* | "tiny10"* )
      echo "2G" ;;
    "win2025"* | "win2022"* | "win2019"* | "win2016"* )
      echo "2G" ;;
    "win81"* | "win7x64"* )
      echo "2G" ;;
    "win7x86"* | "winvista"* | "win2012"* )
      echo "1G" ;;
    "win2008"* | "win2003"* )
      echo "512M" ;;
    "winxpx64"* )
      echo "256M" ;;
    "win9"* | "winnt4"* | "winxpx86"* | "win2k"* )
      echo "130M" ;;
    "reactos"* )
      echo "130M" ;;
    * )
      echo "130M" ;;
  esac

  return 0
}

getRequiredDisk() {

  local id="${1,,}"

  case "$id" in
    "win11"* )
      echo "32G" ;;
    "tiny11"* )
      echo "8G" ;;
    "core11"* )
      echo "4G" ;;
    "win10"* )
      echo "16G" ;;
    "tiny10"* )
      echo "10G" ;;
    "win2025"* | "win2022"* | "win2019"* | "win2016"* | "win2012"* )
      echo "32G" ;;
    "win81"* | "win7"* | "winvista"* )
      echo "16G" ;;
    "win2008"* )
      echo "10G" ;;
    "win2003"* )
      echo "4G" ;;
    "winxp"* )
      echo "2G" ;;
    "win2k"* )
      echo "1G" ;;
    "win9x"* )
      echo "512M" ;;
    "win98"* )
      echo "256M" ;;
    "win95"* )
      echo "100M" ;;
    "winnt4"* )
      echo "128M" ;;
    "reactos"* )
      echo "512M" ;;
    * )
      echo "100M" ;;
  esac

  return 0
}

isLegacy() {

  local id="$1"

  case "${id,,}" in
    "win9"* | "winnt4" | "win2k"* | "winxp"* | "win2003"* | \
    "winvista"* | "win7"* | "win2008"* | "reactos" )
      return 0 ;;
  esac

  return 1
}

supportsUnattended() {

  local id="$1"

  case "${id,,}" in
    "winnt4" | "reactos" )
      return 1 ;;
  esac

  return 0
}

supportsXML() {

  local id="$1"

  supportsSIF "$id" && return 1
  supportsUnattended "$id" || return 1

  case "${id,,}" in
    "win9"* )
      return 1 ;;
  esac

  return 0
}

supportsSIF() {

  local id="$1"

  case "${id,,}" in
    "win2k"* | "winxp"* | "win2003"* )
      return 0 ;;
  esac

  return 1
}

supportsACPI() {

  local id="$1"

  case "${id,,}" in

    "win9"* | "winnt4" )

      # Windows 9x does not respond to ACPI during setup,
      # so disable it during the first run of the container.
      hasBootMarker || return 1 ;;

    "reactos" )

      # If the ISO is a Live-CD it will ignore ACPI signals.
      hasSystemImage && return 1 ;;

  esac

  return 0
}

supportsBootKey() {

  local id="$1"

  case "${id,,}" in
    "win9"* | "winnt4" | "reactos" )
      return 1 ;;
    "win"* | "tiny"* | "core"* )
      return 0 ;;
  esac

  return 0
}

getDriverFolder() {

  local id="$1"

  case "${id,,}" in
    "win7x86"* )      echo "w7/x86" ;;
    "win7x64"* )      echo "w7/amd64" ;;
    "win81x64"* )     echo "w8.1/amd64" ;;
    "win10x64"* )     echo "w10/amd64" ;;
    "win11x64"* )     echo "w11/amd64" ;;
    "win2025"* )      echo "2k25/amd64" ;;
    "win2022"* )      echo "2k22/amd64" ;;
    "win2019"* )      echo "2k19/amd64" ;;
    "win2016"* )      echo "2k16/amd64" ;;
    "win2012"* )      echo "2k12R2/amd64" ;;
    "win2008"* )      echo "2k8R2/amd64" ;;
    "win10arm64"* )   echo "w10/ARM64" ;;
    "win11arm64"* )   echo "w11/ARM64" ;;
    "winvistax86"* )  echo "2k8/x86" ;;
    "winvistax64"* )  echo "2k8/amd64" ;;
    * )               return 1 ;;
  esac

  return 0
}

getMido() {

  local id="$1"
  local lang="$2"
  local ret="$3"

  local url="" sum="" size=""

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
    "win2008r2" | "win2008r2-eval" )
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

  local url="" sum="" size=""
  local host="https://dl.bobpony.com/windows"

  [[ "${lang,,}" != "en" && "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win11x64" | "win11x64-enterprise" )
      size=6927149056
      sum="f5ffe9313eebc6299fba9e6eeb2971007264e6c6be013073a89b5ae9bd85bfb3"
      url="11/en-us_windows_11_25h2_x64.iso"
      ;;
    "win11x64-ltsc" | "win11x64-enterprise-ltsc" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="11/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win11x64-iot" | "win11x64-enterprise-iot" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="11/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win10x64" | "win10x64-enterprise" )
      size=5723299840
      sum="316f718f21fc9b386d81dadd62dc60268a1cfd65b184ac6a052875a454c3431b"
      url="10/en-us_windows_10_22h2_x64.iso"
      ;;
    "win10x64-ltsc" | "win10x64-enterprise-ltsc" )
      size=4899461120
      sum="c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d"
      url="10/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso"
      ;;
    "win10x64-iot" | "win10x64-enterprise-iot" )
      size=4851668992
      sum="a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
      url="10/en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
      ;;
    "win81x64" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      url="8.x/8.1/en_windows_8.1_with_update_x64_dvd_6051480.iso"
      ;;
    "win81x64-enterprise" )
      size=4139163648
      sum="c3c604c03677504e8905090a8ce5bb1dde76b6fd58e10f32e3a25bef21b2abe1"
      url="8.x/8.1/en_windows_8.1_enterprise_with_update_x64_dvd_6054382.iso"
      ;;
    "win2025" )
      size=7571058688
      sum="d273d0a85565ffbc06a3d46313f619103e2830a3373306ddbb9a08b8824f509d"
      url="server/2025/en-us_windows_server_2025_updated_oct_2025_x64_dvd_6c0c5aa8.iso"
      ;;
    "win2022" )
      size=6023239680
      sum="5d6d91efa972cbdd6701d78db1dcf6a34c7024ca931c1718e7cb3d0c6dd54e88"
      url="server/2022/en-us_windows_server_2022_updated_oct_2025_x64_dvd_26e9af36.iso"
      ;;
    "win2019" )
      size=5575774208
      sum="0067afe7fdc4e61f677bd8c35a209082aa917df9c117527fc4b2b52a447e89bb"
      url="server/2019/en-us_windows_server_2019_updated_aug_2021_x64_dvd_a6431a28.iso"
      ;;
    "win2016" )
      size=6006587392
      sum="af06e5483c786c023123e325cea4775050324d9e1366f46850b515ae43f764be"
      url="server/2016/en_windows_server_2016_updated_feb_2018_x64_dvd_11636692.iso"
      ;;
    "win2012r2" )
      size=5397889024
      sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
      url="server/2012r2/en_windows_server_2012_r2_with_update_x64_dvd_6052708-004.iso"
      ;;
    "win2008r2" )
      size=3166584832
      sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
      url="server/2008r2/en_windows_server_2008_r2_with_sp1_x64_dvd_617601-018.iso"
      ;;
    "win7x64" | "win7x64-ultimate" )
      size=3320836096
      sum="0b738b55a5ea388ad016535a5c8234daf2e5715a0638488ddd8a228a836055a1"
      url="7/en_windows_7_with_sp1_x64.iso"
      ;;
    "win7x64-enterprise" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="7/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
      ;;
    "win7x86" | "win7x86-ultimate" )
      size=2564411392
      sum="99f3369c90160816be07093dbb0ac053e0a84e52d6ed1395c92ae208ccdf67e5"
      url="7/en_windows_7_with_sp1_x86.iso"
      ;;
    "win7x86-enterprise" )
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
    "win9x" )
      size=448957271
      sum="36e75592cf89e072e165da60100f91ca59b7667be90494f1aa4a78091011cfea"
      url="9x/me/Windows%20Me_en.zip"
      ;;
    "win98" )
      size=558263127
      sum="980bfc9abc93c3104d1a00690c5db702efda7a377de7e06cda61889a972e2e08"
      url="9x/98/se/Microsoft%20Windows%2098%20Second%20Edition%20%284.10.2222%29.rar"
      ;;
    "win95" )
      size=422127699
      sum="5456632a73a3c70f8e5ee566374876266a81f61968e623ef5500028dec8e2979"
      url="9x/95/Microsoft%20Windows%2095C%20%284.03.1216.osr2.5%29.zip"
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

  local url="" sum="" size=""
  local host="https://files.dog/MSDN"

  [[ "${lang,,}" != "en" && "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win81x64" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      url="Windows%208.1%20with%20Update/en_windows_8.1_with_update_x64_dvd_6051480.iso"
      ;;
    "win81x64-enterprise" )
      size=4139163648
      sum="c3c604c03677504e8905090a8ce5bb1dde76b6fd58e10f32e3a25bef21b2abe1"
      url="Windows%208.1%20with%20Update/en_windows_8.1_enterprise_with_update_x64_dvd_6054382.iso"
      ;;
    "win2012r2" )
      size=5397889024
      sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
      url="Windows%20Server%202012%20R2%20with%20Update/en_windows_server_2012_r2_with_update_x64_dvd_6052708.iso"
      ;;
    "win2008r2" )
      size=3166584832
      sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
      url="Windows%20Server%202008%20R2/en_windows_server_2008_r2_with_sp1_x64_dvd_617601.iso"
      ;;
    "win7x64" | "win7x64-ultimate" )
      size=3320903680
      sum="36f4fa2416d0982697ab106e3a72d2e120dbcdb6cc54fd3906d06120d0653808"
      url="Windows%207/en_windows_7_ultimate_with_sp1_x64_dvd_u_677332.iso"
      ;;
    "win7x64-enterprise" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="Windows%207/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
      ;;
    "win7x86" | "win7x86-ultimate" )
      size=2564476928
      sum="e2c009a66d63a742941f5087acae1aa438dcbe87010bddd53884b1af6b22c940"
      url="Windows%207/en_windows_7_ultimate_with_sp1_x86_dvd_u_677460.iso"
      ;;
    "win7x86-enterprise" )
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

  local url="" sum="" size=""
  local host="https://iso.reactos.org"

  [[ "${lang,,}" != "en" && "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "reactos" )
      size=0
      sum=""
      url="livecd/latest-x86-gcc-lin-rel"
      ;;
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

  local url="" sum="" size=""
  local host="https://archive.org/download"

  [[ "${lang,,}" != "en" && "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win11x64" )
      size=7736125440
      sum="d141f6030fed50f75e2b03e1eb2e53646c4b21e5386047cb860af5223f102a32"
      url="W11x64_26200.6584/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENT_CONSUMER_x64FRE_en-us.iso"
      ;;
    "win11x64-enterprise" )
      size=6209064960
      sum="c8dbc96b61d04c8b01faf6ce0794fdf33965c7b350eaa3eb1e6697019902945c"
      url="Windows11Enterprise23H2x64/22631.2428.231001-0608.23H2_NI_RELEASE_SVC_REFRESH_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
      ;;
    "win11x64-ltsc" | "win11x64-enterprise-ltsc" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="Windows11LTSC/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win11x64-iot" | "win11x64-enterprise-iot" )
      size=5144817664
      sum="4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a"
      url="Windows11LTSC/X23-81951_26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win10x64" | "win10x64-enterprise" )
      size=6985445376
      sum="2c23bc8b95a9314f15ebff881dcbea49651f52a96a0327d7aaf523aa66043765"
      url="windows-10-business-editions-version-22h2-updated-oct-2025-en-us/en-us_windows_10_business_editions_version_22h2_updated_oct_2025_x64_dvd_d2eef4b0.iso"
      ;;
    "win10x64-ltsc" | "win10x64-enterprise-ltsc" )
      size=4899461120
      sum="c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d"
      url="en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96_202302/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso"
      ;;
    "win10x64-iot" | "win10x64-enterprise-iot" )
      size=4851668992
      sum="a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
      url="en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f_202411/en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
      ;;
    "win81x64" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      url="en_windows_8.1_with_update_x64_dvd_6051480/en_windows_8.1_with_update_x64_dvd_6051480.iso"
      ;;
    "win81x64-enterprise" )
      size=4139163648
      sum="c3c604c03677504e8905090a8ce5bb1dde76b6fd58e10f32e3a25bef21b2abe1"
      url="en_windows_8.1_enterprise_with_update_x64_dvd/en_windows_8.1_enterprise_with_update_x64_dvd_6054382.iso"
      ;;
    "win2025" )
      size=8145395712
      sum="f3e277e75acdb793e6f08f4880b514ae0046cedf618c22f727890e54367075e6"
      url="en-us_windows_server_2025_updated_dec_2025_x64_dvd_c54ab58b/en-us_windows_server_2025_updated_dec_2025_x64_dvd_c54ab58b.iso"
      ;;
    "win2022" )
      size=5550684160
      sum="5a077ee2a95976ef9f3623eb4040e25cdf7f8f01dee3b8165a32a7626f39f025"
      url="en-us_windows_server_2022_x64_dvd_620d7eac_202405/en-us_windows_server_2022_x64_dvd_620d7eac.iso"
      ;;
    "win2019" )
      size=5651695616
      sum="ea247e5cf4df3e5829bfaaf45d899933a2a67b1c700a02ee8141287a8520261c"
      url="en-us_windows_server_2019_x64_dvd_f9475476_202603/en-us_windows_server_2019_x64_dvd_f9475476.iso"
      ;;
    "win2016" )
      size=6006587392
      sum="af06e5483c786c023123e325cea4775050324d9e1366f46850b515ae43f764be"
      url="en_windows_server_2016_updated_feb_2018_x64_dvd_11636692/en_windows_server_2016_updated_feb_2018_x64_dvd_11636692.iso"
      ;;
    "win2012r2" )
      size=5397889024
      sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
      url="en_windows_server_2012_r2_with_update_x64_dvd_6052708_202006/en_windows_server_2012_r2_with_update_x64_dvd_6052708.iso"
      ;;
    "win2008r2" )
      size=3166584832
      sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
      url="en_windows_server_2008_r2_with_sp1_x64_dvd_617601_202405/en_windows_server_2008_r2_with_sp1_x64_dvd_617601.iso"
      ;;
    "win7x64" | "win7x64-ultimate" )
      size=3320903680
      sum="36f4fa2416d0982697ab106e3a72d2e120dbcdb6cc54fd3906d06120d0653808"
      url="win7-ult-sp1-english/Win7_Ult_SP1_English_x64.iso"
      ;;
    "win7x64-enterprise" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="en_windows_7_enterprise_with_sp1_x64_dvd_u_677651_202006/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
      ;;
    "win7x86" | "win7x86-ultimate" )
      size=2564476928
      sum="e2c009a66d63a742941f5087acae1aa438dcbe87010bddd53884b1af6b22c940"
      url="win7-ult-sp1-english/Win7_Ult_SP1_English_x32.iso"
      ;;
    "win7x86-enterprise" )
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
      url="en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
    "win2kx86" )
      size=386859008
      sum="e3816f6e80b66ff686ead03eeafffe9daf020a5e4717b8bd4736b7c51733ba22"
      url="MicrosoftWindows2000BuildCollection/5.00.2195.6717_x86fre_client-professional_retail_en-us-ZRMPFPP_EN.iso"
      ;;
    "win9x" )
      size=523665408
      sum="bff3e9e69e625d2fdffd01b326988c45be8b9285465a4dabbae96ac550de611e"
      url="windows-me_202209/Windows%20ME.ISO"
      ;;
    "win98" )
      size=655591424
      sum="2adfb46df8a9c7bbd2f67bff07461cc2f9d9ec8e01f0e112cb044c9e3e62f607"
      url="windows-98-se-isofile/Windows%2098%20Second%20Edition.iso"
      ;;
    "win95" )
      size=618229760
      sum="493212b2a3cd391269e55a8fde5ee0a35e29ddece4b5910ec49df69ab62f5e26"
      url="win-95-osr-25_202103/Win95_OSR25.iso"
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
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) [ -n "$url" ] && echo "$host/$url";;
  esac

  return 0
}

getValue() {

  local id="$2"
  local lang="$3"
  local type="$4"
  local func="getLink$1"

  local val=""

  if [ "$1" -gt 0 ] && [ "$1" -le "$MIRRORS" ]; then
    val=$($func "$id" "$lang" "$type")
  fi

  echo "$val"
  return 0
}

getLink() {

  getValue "$1" "$2" "$3" ""
}

getHash() {

  getValue "$1" "$2" "$3" "sum"
}

getSize() {

  getValue "$1" "$2" "$3" "size"
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
    "win11${PLATFORM,,}" | \
    "win10${PLATFORM,,}" | \
    "win11${PLATFORM,,}-enterprise" | \
    "win10${PLATFORM,,}-enterprise" )
      return 0 ;;
  esac

  return 1
}

validVersion() {

  local id="$1"
  local lang="$2"
  local url i

  isMido "$id" "$lang" && return 0

  [[ "${id,,}" == *"-eval" ]] && id="${id::-5}"

  isESD "$id" "$lang" && return 0

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
