#!/usr/bin/env bash
set -Eeuo pipefail

: "${XRES:=""}"
: "${YRES:=""}"
: "${VERIFY:=""}"
: "${REGION:=""}"
: "${MANUAL:=""}"
: "${REMOVE:=""}"
: "${VERSION:=""}"
: "${DETECTED:=""}"
: "${KEYBOARD:=""}"
: "${LANGUAGE:=""}"
: "${USERNAME:=""}"
: "${PASSWORD:=""}"

MIRRORS=4
PLATFORM="x64"

parseVersion() {

  if [[ "${VERSION}" == \"*\" || "${VERSION}" == \'*\' ]]; then
    VERSION="${VERSION:1:-1}"
  fi

  [ -z "$VERSION" ] && VERSION="win11"

  case "${VERSION,,}" in
    "11" | "11p" | "win11" | "win11p" | "windows11" | "windows 11" )
      VERSION="win11x64"
      ;;
    "11e" | "win11e" | "windows11e" | "windows 11e" )
      VERSION="win11x64-enterprise-eval"
      ;;
    "10" | "10p" | "win10" | "win10p" | "windows10" | "windows 10" )
      VERSION="win10x64"
      ;;
    "10e" | "win10e" | "windows10e" | "windows 10e" )
      VERSION="win10x64-enterprise-eval"
      ;;
    "8" | "8p" | "81" | "81p" | "8.1" | "win8" | "win8p" | "win81" | "win81p" | "windows 8" )
      VERSION="win81x64"
      ;;
    "8e" | "81e" | "8.1e" | "win8e" | "win81e" | "windows 8e" )
      VERSION="win81x64-enterprise-eval"
      ;;
    "7" | "7e" | "win7" | "win7e" | "windows7" | "windows 7" )
      VERSION="win7x64"
      [ -z "$DETECTED" ] && DETECTED="win7x64-enterprise"
      ;;
    "7u" | "win7u" | "windows7u" | "windows 7u" )
      VERSION="win7x64-ultimate"
      ;;
    "7x86" | "win7x86" | "windows7x86"  | "win7x86-enterprise" )
      VERSION="win7x86"
      [ -z "$DETECTED" ] && DETECTED="win7x86-enterprise"
      ;;
    "vista" | "winvista" | "windowsvista" | "windows vista" )
      VERSION="winvistax64"
      [ -z "$DETECTED" ] && DETECTED="winvistax64-enterprise"
      ;;
    "vistu" | "winvistu" | "windowsvistu" | "windows vistu" )
      VERSION="winvistax64-ultimate"
      ;;
    "vistax86" | "winvistax86" | "windowsvistax86"  | "winvistax86-enterprise" )
      VERSION="winvistax86"
      [ -z "$DETECTED" ] && DETECTED="winvistax86-enterprise"
      ;;
    "xp" | "xp32" | "xpx86" | "winxp" | "winxp86" | "windowsxp" | "windows xp" )
      VERSION="winxpx86"
      ;;
    "xp64" | "xpx64" | "winxp64" | "winxpx64" | "windowsxp64" | "windowsxpx64" )
      VERSION="winxpx64"
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
    "iot11" | "11iot" | "win11-iot" | "win11x64-iot" | "win11x64-enterprise-iot-eval" )
      VERSION="win11x64-enterprise-iot-eval"
      [ -z "$DETECTED" ] && DETECTED="win11x64-iot"
      ;;
    "iot10" | "10iot" | "win10-iot" | "win10x64-iot" | "win10x64-enterprise-iot-eval" )
      VERSION="win10x64-enterprise-iot-eval"
      [ -z "$DETECTED" ] && DETECTED="win10x64-iot"
      ;;
    "ltsc11" | "11ltsc" | "win11-ltsc" | "win11x64-ltsc" | "win11x64-enterprise-ltsc-eval" )
      VERSION="win11x64-enterprise-ltsc-eval"
      [ -z "$DETECTED" ] && DETECTED="win11x64-iot"
      ;;
    "ltsc10" | "10ltsc" | "win10-ltsc" | "win10x64-ltsc" | "win10x64-enterprise-ltsc-eval" )
      VERSION="win10x64-enterprise-ltsc-eval"
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
  local culture=""

  case "${id,,}" in
    "ar" | "ar-"* )
      lang="Arabic"
      desc="$lang"
      culture="ar-SA" ;;
    "bg" | "bg-"* )
      lang="Bulgarian"
      desc="$lang"
      culture="bg-BG" ;;
    "cs" | "cs-"* | "cz" | "cz-"* )
      lang="Czech"
      desc="$lang"
      culture="cs-CZ" ;;
    "da" | "da-"* | "dk" | "dk-"* )
      lang="Danish"
      desc="$lang"
      culture="da-DK" ;;
    "de" | "de-"* )
      lang="German"
      desc="$lang"
      culture="de-DE" ;;
    "el" | "el-"* | "gr" | "gr-"* )
      lang="Greek"
      desc="$lang"
      culture="el-GR" ;;
    "gb" | "en-gb" )
      lang="English International"
      desc="English"
      culture="en-GB" ;;
    "en" | "en-"* )
      lang="English (United States)"
      desc="English"
      culture="en-US" ;;
    "mx" | "es-mx" )
      lang="Spanish (Mexico)"
      desc="Spanish"
      culture="es-MX" ;;
    "es" | "es-"* )
      lang="Spanish"
      desc="$lang"
      culture="es-ES" ;;
    "et" | "et-"* )
      lang="Estonian"
      desc="$lang"
      culture="et-EE" ;;
    "fi" | "fi-"* )
      lang="Finnish"
      desc="$lang"
      culture="fi-FI" ;;
    "ca" | "fr-ca" )
      lang="French Canadian"
      desc="French"
      culture="fr-CA" ;;
    "fr" | "fr-"* )
      lang="French"
      desc="$lang"
      culture="fr-FR" ;;
    "he" | "he-"* | "il" | "il-"* )
      lang="Hebrew"
      desc="$lang"
      culture="he-IL" ;;
    "hr" | "hr-"* | "cr" | "cr-"* )
      lang="Croatian"
      desc="$lang"
      culture="hr-HR" ;;
    "hu" | "hu-"* )
      lang="Hungarian"
      desc="$lang"
      culture="hu-HU" ;;
    "it" | "it-"* )
      lang="Italian"
      desc="$lang"
      culture="it-IT" ;;
    "ja" | "ja-"* | "jp" | "jp-"* )
      lang="Japanese"
      desc="$lang"
      culture="ja-JP" ;;
    "ko" | "ko-"* | "kr" | "kr-"* )
      lang="Korean"
      desc="$lang"
      culture="ko-KR" ;;
    "lt" | "lt-"* )
      lang="Lithuanian"
      desc="$lang"
      culture="lv-LV" ;;
    "lv" | "lv-"* )
      lang="Latvian"
      desc="$lang"
      culture="lt-LT" ;;
    "nb" | "nb-"* |"nn" | "nn-"* | "no" | "no-"* )
      lang="Norwegian"
      desc="$lang"
      culture="nb-NO" ;;
    "nl" | "nl-"* )
      lang="Dutch"
      desc="$lang"
      culture="nl-NL" ;;
    "pl" | "pl-"* )
      lang="Polish"
      desc="$lang"
      culture="pl-PL" ;;
    "br" | "pt-br" )
      lang="Brazilian Portuguese"
      desc="Portuguese"
      culture="pt-BR" ;;
    "pt" | "pt-"* )
      lang="Portuguese"
      desc="$lang"
      culture="pt-BR" ;;
    "ro" | "ro-"* )
      lang="Romanian"
      desc="$lang"
      culture="ro-RO" ;;
    "ru" | "ru-"* )
      lang="Russian"
      desc="$lang"
      culture="ru-RU" ;;
    "sk" | "sk-"* )
      lang="Slovak"
      desc="$lang"
      culture="sk-SK" ;;
    "sl" | "sl-"* | "si" | "si-"* )
      lang="Slovenian"
      desc="$lang"
      culture="sl-SI" ;;
    "sr" | "sr-"* )
      lang="Serbian Latin"
      desc="Serbian"
      culture="sr-Latn-RS" ;;
    "sv" | "sv-"* | "se" | "se-"* )
      lang="Swedish"
      desc="$lang"
      culture="sv-SE" ;;
    "th" | "th-"* )
      lang="Thai"
      desc="$lang"
      culture="th-TH" ;;
    "tr" | "tr-"* )
      lang="Turkish"
      desc="$lang"
      culture="tr-TR" ;;
    "ua" | "ua-"* | "uk" | "uk-"* )
      lang="Ukrainian"
      desc="$lang"
      culture="uk-UA" ;;
    "hk" | "zh-hk" | "cn-hk" )
      lang="Chinese Traditional"
      desc="Chinese HK"
      culture="zh-TW" ;;
    "tw" | "zh-tw" | "cn-tw" )
      lang="Chinese Traditional"
      desc="Chinese TW"
      culture="zh-TW" ;;
    "zh" | "zh-"* | "cn" | "cn-"* )
      lang="Chinese Simplified"
      desc="Chinese"
      culture="zh-CN" ;;
  esac

  case "${ret,,}" in
    "desc" ) echo "$desc" ;;
    "name" ) echo "$lang" ;;
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
    [[ "${PLATFORM,,}" != "x64" ]] && desc="$desc for ${PLATFORM}"
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
    *"-iot" | *"-iot-eval" )
      edition="IoT"
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
    "win2025"* | "win2022"* | "win2019"* | "win2016"* )
      edition="Standard"
      ;;
    "win2012"* | "win2008"* | "win2003"* )
      edition="Standard"
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

  case "${file// /_}" in
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

  case "${file// /_}" in
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
    *"server2025"* | *"server_2025"* )
      id="win2025"
      ;;
    *"server2022"* | *"server_2022"* )
      id="win2022"
      ;;
    *"server2019"* | *"server_2019"* )
      id="win2019"
      ;;
    *"server2016"* | *"server_2016"* )
      id="win2016"
      ;;
    *"server2012"* | *"server_2012"* )
      id="win2012r2"
      ;;
    *"server2008"* | *"server_2008"* )
      id="win2008r2"
      ;;
    *"server2003"* | *"server_2003"* )
      id="win2003r2"
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

  case "${name,,}" in
    *"server 2025"* ) id="win2025" ;;
    *"server 2022"* ) id="win2022" ;;
    *"server 2019"* ) id="win2019" ;;
    *"server 2016"* ) id="win2016" ;;
    *"server 2012"* ) id="win2012r2" ;;
    *"server 2008"* ) id="win2008r2" ;;
    *"windows 7"* ) id="win7${arch}" ;;
    *"windows 8"* ) id="win81${arch}" ;;
    *"windows 10"* ) id="win10${arch}" ;;
    *"windows 11"* ) id="win11${arch}" ;;
    *"windows vista"* ) id="winvista${arch}" ;;
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
    "win2025"* | "win2022"* | "win2019"* | "win2016"* | "win2012"* | "win2008"* )
       case "${name,,}" in
          *" evaluation"* ) id="$id-eval" ;;
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
  local sum=""
  local size=""

  [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "win11x64" )
      size=6812706816
      sum="36de5ecb7a0daa58dce68c03b9465a543ed0f5498aa8ae60ab45fb7c8c4ae402"
      ;;
    "win11x64-enterprise-eval" )
      size=6209064960
      sum="c8dbc96b61d04c8b01faf6ce0794fdf33965c7b350eaa3eb1e6697019902945c"
      ;;
    "win11x64-enterprise-ltsc-eval" )
      size=4428627968
      sum="8abf91c9cd408368dc73aab3425d5e3c02dae74900742072eb5c750fc637c195"
      ;;
    "win11x64-enterprise-iot-eval" )
      size=4428627968
      sum="8abf91c9cd408368dc73aab3425d5e3c02dae74900742072eb5c750fc637c195"
      ;;
    "win10x64" )
      size=6140975104
      sum="a6f470ca6d331eb353b815c043e327a347f594f37ff525f17764738fe812852e"
      ;;
    "win10x64-enterprise-eval" )
      size=5550497792
      sum="ef7312733a9f5d7d51cfa04ac497671995674ca5e1058d5164d6028f0938d668"
      ;;
    "win10x64-enterprise-ltsc-eval" )
      size=4898582528
      sum="e4ab2e3535be5748252a8d5d57539a6e59be8d6726345ee10e7afd2cb89fefb5"
      ;;
    "win81x64" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      ;;
    "win81x64-enterprise-eval" )
      size=3961473024
      sum="2dedd44c45646c74efc5a028f65336027e14a56f76686a4631cf94ffe37c72f2"
      ;;
    "win2025-eval" )
      size=5307996160
      sum="16442d1c0509bcbb25b715b1b322a15fb3ab724a42da0f384b9406ca1c124ed4"
      ;;
    "win2022-eval" )
      size=5044094976
      sum="3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325"
      ;;
    "win2019-eval" )
      size=5652088832
      sum="6dae072e7f78f4ccab74a45341de0d6e2d45c39be25f1f5920a2ab4f51d7bcbb"
     ;;
    "win2016-eval" )
      size=6972221440
      sum="1ce702a578a3cb1ac3d14873980838590f06d5b7101c5daaccbac9d73f1fb50f"
      ;;
    "win2012r2-eval" )
      size=4542291968
      sum="6612b5b1f53e845aacdf96e974bb119a3d9b4dcb5b82e65804ab7e534dc7b4d5"
      ;;
    "win2008r2" )
      size=3166840832
      sum="30832ad76ccfa4ce48ccb936edefe02079d42fb1da32201bf9e3a880c8ed6312"
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) echo "";;
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
      size=5946128384
      sum="5bb1459034f50766ee480d895d751af73a4af30814240ae32ebc5633546a5af7"
      url="11/en-us_windows_11_23h2_x64.iso"
      ;;
    "win11x64-iot" | "win11x64-enterprise-iot-eval" )
      [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0
      size=4501397504
      sum="aaa4bd3254c1af5f9ce07f50db68fdead7a305878f2425c059ecd6b062a855b3"
      url="11/26100.1.240331-1435.ge_release_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win11x64-ltsc" | "win11x64-enterprise-ltsc-eval" )
      [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0
      size=4501397504
      sum="aaa4bd3254c1af5f9ce07f50db68fdead7a305878f2425c059ecd6b062a855b3"
      url="11/26100.1.240331-1435.ge_release_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win10x64" | "win10x64-enterprise" | "win10x64-enterprise-eval" )
      size=5623582720
      sum="57371545d752a79a8a8b163b209c7028915da661de83516e06ddae913290a855"
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
    "win7x64" | "win7x64-enterprise" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="7/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
      ;;
    "win7x64-ultimate" )
      size=3320836096
      sum="0b738b55a5ea388ad016535a5c8234daf2e5715a0638488ddd8a228a836055a1"
      url="7/en_windows_7_with_sp1_x64.iso"
      ;;
    "win7x86" | "win7x86-enterprise" )
      size=2434502656
      sum="8bdd46ff8cb8b8de9c4aba02706629c8983c45e87da110e64e13be17c8434dad"
      url="7/en_windows_7_enterprise_with_sp1_x86_dvd_u_677710.iso"
      ;;
    "win7x86-ultimate" )
      size=2564411392
      sum="99f3369c90160816be07093dbb0ac053e0a84e52d6ed1395c92ae208ccdf67e5"
      url="7/en_windows_7_with_sp1_x86.iso"
      ;;
    "winvistax64-ultimate" )
      size=3861460992
      sum="edf9f947c5791469fd7d2d40a5dcce663efa754f91847aa1d28ed7f585675b78"
      url="vista/en_windows_vista_sp2_x64_dvd_342267.iso"
      ;;
    "winvistax86-ultimate" )
      size=3243413504
      sum="9c36fed4255bd05a8506b2da88f9aad73643395e155e609398aacd2b5276289c"
      url="vista/en_windows_vista_with_sp2_x86_dvd_342266.iso"
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
    "win7x64" | "win7x64-enterprise" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="Windows%207/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
      ;;
    "win7x64-ultimate" )
      size=3320903680
      sum="36f4fa2416d0982697ab106e3a72d2e120dbcdb6cc54fd3906d06120d0653808"
      url="Windows%207/en_windows_7_ultimate_with_sp1_x64_dvd_u_677332.iso"
      ;;
    "win7x86" | "win7x86-enterprise" )
      size=2434502656
      sum="8bdd46ff8cb8b8de9c4aba02706629c8983c45e87da110e64e13be17c8434dad"
      url="Windows%207/en_windows_7_enterprise_with_sp1_x86_dvd_u_677710.iso"
      ;;
    "win7x86-ultimate" )
      size=2564476928
      sum="e2c009a66d63a742941f5087acae1aa438dcbe87010bddd53884b1af6b22c940"
      url="Windows%207/en_windows_7_ultimate_with_sp1_x86_dvd_u_677460.iso"
      ;;
    "winvistax64" | "winvistax64-enterprise" )
      size=3205953536
      sum="0a0cd511b3eac95c6f081419c9c65b12317b9d6a8d9707f89d646c910e788016"
      url="Windows%20Vista/en_windows_vista_enterprise_sp2_x64_dvd_342332.iso"
      ;;
    "winvistax64-ultimate" )
      size=3861460992
      sum="edf9f947c5791469fd7d2d40a5dcce663efa754f91847aa1d28ed7f585675b78"
      url="Windows%20Vista/en_windows_vista_sp2_x64_dvd_342267.iso"
      ;;
    "winvistax86" | "winvistax86-enterprise" )
      size=2420981760
      sum="54e2720004041e7db988a391543ea5228b0affc28efcf9303d2d0ff9402067f5"
      url="Windows%20Vista/en_windows_vista_enterprise_sp2_x86_dvd_342329.iso"
      ;;
    "winvistax86-ultimate" )
      size=3243413504
      sum="9c36fed4255bd05a8506b2da88f9aad73643395e155e609398aacd2b5276289c"
      url="Windows%20Vista/en_windows_vista_with_sp2_x86_dvd_342266.iso"
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

  # Fallbacks for users who cannot connect to the Microsoft servers

  local id="$1"
  local lang="$2"
  local ret="$3"
  local url=""
  local sum=""
  local size=""
  local host="https://drive.massgrave.dev"
  local s22="windows_server_2022_updated_aug_2024_x64_dvd_17b2bb17"  
  local c11="windows_11_consumer_editions_version_23h2_updated_aug_2024_x64_dvd_d3e1c088"
  local b11="windows_11_business_editions_version_23h2_updated_aug_2024_x64_dvd"
  local c10="windows_10_consumer_editions_version_22h2_updated_aug_2024_x86_dvd_2454bb57"
  local b10="windows_10_business_editions_version_22h2_updated_aug_2024_x64_dvd"

  culture=$(getLanguage "$lang" "culture")

  case "${id,,}" in
    "win11x64" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar-sa_${c11}.iso" ;;
        "bg" | "bg-"* ) url="bg-bg_${c11}.iso" ;;
        "cs" | "cs-"* ) url="cs-cz_${c11}.iso" ;;
        "da" | "da-"* ) url="da-dk_${c11}.iso" ;;
        "de" | "de-"* ) url="de-de_${c11}.iso" ;;
        "el" | "el-"* ) url="el-gr_${c11}.iso" ;;
        "gb" | "en-gb" ) url="en-gb_${c11}.iso" ;;
        "en" | "en-"* )
          size=7174344704
          sum="c37962a65405106323ccd9c8b26a148959413a8b4cae22be315338f283a25e60"
          url="en-us_${c11}.iso" ;;
        "mx" | "es-mx" ) url="es-mx_${c11}.iso" ;;
        "es" | "es-"* ) url="es-es_${c11}.iso" ;;
        "et" | "et-"* ) url="et-ee_${c11}.iso" ;;
        "fi" | "fi-"* ) url="fi-fi_${c11}.iso" ;;
        "ca" | "fr-ca" ) url="fr-ca_${c11}.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_${c11}.iso" ;;
        "he" | "he-"* ) url="he-il_${c11}.iso" ;;
        "hr" | "hr-"* ) url="hr-hr_${c11}.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_${c11}.iso" ;;
        "it" | "it-"* ) url="it-it_${c11}.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_${c11}.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_${c11}.iso" ;;
        "lt" | "lt-"* ) url="lt-lt_${c11}.iso" ;;
        "lv" | "lv-"* ) url="lv-lv_${c11}.iso" ;;
        "nb" | "nb-"* ) url="nb-no_${c11}.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_${c11}.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_${c11}.iso" ;;
        "br" | "pt-br" ) url="pt-br_${c11}.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_${c11}.iso" ;;
        "ro" | "ro-"* ) url="ro-ro_${c11}.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_${c11}.iso" ;;
        "sk" | "sk-"* ) url="sk-sk_${c11}.iso" ;;
        "sl" | "sl-"* ) url="sl-si_${c11}.iso" ;;
        "sr" | "sr-"* ) url="sr-latn-rs_${c11}.iso" ;;
        "sv" | "sv-"* ) url="sv-se_${c11}.iso" ;;
        "th" | "th-"* ) url="th-th_${c11}.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_${c11}.iso" ;;
        "uk" | "uk-"* ) url="uk-ua_${c11}.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_${c11}.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_${c11}.iso" ;;
      esac
      ;;
    "win11x64-enterprise" | "win11x64-enterprise-eval" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar-sa_${b11}_e8f50c77.iso" ;;
        "bg" | "bg-"* ) url="bg-bg_${b11}_4917d646.iso" ;;
        "cs" | "cs-"* ) url="cs-cz_${b11}_7423efd7.iso" ;;
        "da" | "da-"* ) url="da-dk_${b11}_320e7939.iso" ;;
        "de" | "de-"* ) url="de-de_${b11}_0a30ec34.iso" ;;
        "el" | "el-"* ) url="el-gr_${b11}_8094f396.iso" ;;
        "gb" | "en-gb" ) url="en-gb_${b11}_d2bfefb8.iso" ;;
        "en" | "en-"* )
          size=7058937856
          sum="16366a1970d98b590295f5858eb2aae5577ef870a148de42bd3ed051e78010fb"
          url="en-us_${b11}_4b6aa6b4.iso" ;;
        "mx" | "es-mx" ) url="es-mx_${b11}_a3ff371e.iso" ;;
        "es" | "es-"* ) url="es-es_${b11}_49584d0f.iso" ;;
        "et" | "et-"* ) url="et-ee_${b11}_9418af12.iso" ;;
        "fi" | "fi-"* ) url="fi-fi_${b11}_f99ef6d3.iso" ;;
        "ca" | "fr-ca" ) url="fr-ca_${b11}_3b3e23dc.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_${b11}_e5a1eeb4.iso" ;;
        "he" | "he-"* ) url="he-il_${b11}_52d76f40.iso" ;;
        "hr" | "hr-"* ) url="hr-hr_${b11}_c93171de.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_${b11}_0ac31337.iso" ;;
        "it" | "it-"* ) url="it-it_${b11}_d1670509.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_${b11}_6394f8d8.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_${b11}_ad04a091.iso" ;;
        "lt" | "lt-"* ) url="lt-lt_${b11}_75df52ae.iso" ;;
        "lv" | "lv-"* ) url="lv-lv_${b11}_f498cffc.iso" ;;
        "nb" | "nb-"* ) url="nb-no_${b11}_a4cdddfc.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_${b11}_03c01555.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_${b11}_d5274f4d.iso" ;;
        "br" | "pt-br" ) url="pt-br_${b11}_662860be.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_${b11}_ec70d402.iso" ;;
        "ro" | "ro-"* ) url="ro-ro_${b11}_d76af266.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_${b11}_689ea9dc.iso" ;;
        "sk" | "sk-"* ) url="sk-sk_${b11}_358e8bce.iso" ;;
        "sl" | "sl-"* ) url="sl-si_${b11}_69a9feb3.iso" ;;
        "sr" | "sr-"* ) url="sr-latn-rs_${b11}_23247970.iso" ;;
        "sv" | "sv-"* ) url="sv-se_${b11}_2b228b50.iso" ;;
        "th" | "th-"* ) url="th-th_${b11}_6914e97f.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_${b11}_20dd43f1.iso" ;;
        "uk" | "uk-"* ) url="uk-ua_${b11}_ed5be63e.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_${b11}_beaade88.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_${b11}_6ca91c94.iso" ;;
      esac
      ;;
    "win11x64-iot" | "win11x64-enterprise-iot-eval" )
      [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0
      size=4821989376
      sum="e8f1431c4e6289b3997c20eadbb2576670300bb6e1cf8948b5d7af179010a962"
      url="26100.1.240331-1435.ge_release_CLIENTENTERPRISE_OEM_x64FRE_en-us.iso"
      ;;
    "win11x64-ltsc" | "win11x64-enterprise-ltsc-eval" )
      [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0
      size=4821989376
      sum="e8f1431c4e6289b3997c20eadbb2576670300bb6e1cf8948b5d7af179010a962"
      url="26100.1.240331-1435.ge_release_CLIENTENTERPRISE_OEM_x64FRE_en-us.iso"
      ;;
    "win10x64" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar-sa_${c10}.iso" ;;
        "bg" | "bg-"* ) url="bg-bg_${c10}.iso" ;;
        "cs" | "cs-"* ) url="cs-cz_${c10}.iso" ;;
        "da" | "da-"* ) url="da-dk_${c10}.iso" ;;
        "de" | "de-"* ) url="de-de_${c10}.iso" ;;
        "el" | "el-"* ) url="el-gr_${c10}.iso" ;;
        "gb" | "en-gb" ) url="en-gb_${c10}.iso" ;;
        "en" | "en-"* )
          size=4950300672
          sum="bbe2caba5ae2562166ed1ed0d7b54678c7cb9a3fe25dcb1e27c8f6993a95b498"
          url="en-us_${c10}.iso" ;;
        "mx" | "es-mx" ) url="es-mx_${c10}.iso" ;;
        "es" | "es-"* ) url="es-es_${c10}.iso" ;;
        "et" | "et-"* ) url="et-ee_${c10}.iso" ;;
        "fi" | "fi-"* ) url="fi-fi_${c10}.iso" ;;
        "ca" | "fr-ca" ) url="fr-ca_${c10}.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_${c10}.iso" ;;
        "he" | "he-"* ) url="he-il_${c10}.iso" ;;
        "hr" | "hr-"* ) url="hr-hr_${c10}.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_${c10}.iso" ;;
        "it" | "it-"* ) url="it-it_${c10}.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_${c10}.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_${c10}.iso" ;;
        "lt" | "lt-"* ) url="lt-lt_${c10}.iso" ;;
        "lv" | "lv-"* ) url="lv-lv_${c10}.iso" ;;
        "nb" | "nb-"* ) url="nb-no_${c10}.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_${c10}.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_${c10}.iso" ;;
        "br" | "pt-br" ) url="pt-br_${c10}.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_${c10}.iso" ;;
        "ro" | "ro-"* ) url="ro-ro_${c10}.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_${c10}.iso" ;;
        "sk" | "sk-"* ) url="sk-sk_${c10}.iso" ;;
        "sl" | "sl-"* ) url="sl-si_${c10}.iso" ;;
        "sr" | "sr-"* ) url="sr-latn-rs_${c10}.iso" ;;
        "sv" | "sv-"* ) url="sv-se_${c10}.iso" ;;
        "th" | "th-"* ) url="th-th_${c10}.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_${c10}.iso" ;;
        "uk" | "uk-"* ) url="uk-ua_${c10}.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_${c10}.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_${c10}.iso" ;;
      esac
      ;;
    "win10x64-enterprise" | "win10x64-enterprise-eval" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar-sa_${b10}_92a8794f.iso" ;;
        "bg" | "bg-"* ) url="bg-bg_${b10}_5c7ee697.iso" ;;
        "cs" | "cs-"* ) url="cs-cz_${b10}_c8ad70aa.iso" ;;
        "da" | "da-"* ) url="da-dk_${b10}_5a51835f.iso" ;;
        "de" | "de-"* ) url="de-de_${b10}_e24c9809.iso" ;;
        "el" | "el-"* ) url="el-gr_${b10}_a340838b.iso" ;;
        "gb" | "en-gb" ) url="en-gb_${b10}_e758d63e.iso" ;;
        "en" | "en-"* )
          size=6976530432
          sum="290cdbfe5f9b9a76dad12981e5f27eba353c535ffd8c83fdc4691a925f93f487"
          url="en-us_${b10}_633dcd07.iso" ;;
        "mx" | "es-mx" ) url="es-mx_${b10}_0c82aba5.iso" ;;
        "es" | "es-"* ) url="es-es_${b10}_d12d0e1a.iso" ;;
        "et" | "et-"* ) url="et-ee_${b10}_021c20ff.iso" ;;
        "fi" | "fi-"* ) url="fi-fi_${b10}_8fcefb87.iso" ;;
        "ca" | "fr-ca" ) url="fr-ca_${b10}_b0588c68.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_${b10}_8766236b.iso" ;;
        "he" | "he-"* ) url="he-il_${b10}_e34ccebf.iso" ;;
        "hr" | "hr-"* ) url="hr-hr_${b10}_ea8c7c60.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_${b10}_8381df72.iso" ;;
        "it" | "it-"* ) url="it-it_${b10}_1e265790.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_${b10}_6334dde3.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_${b10}_092c4fe2.iso" ;;
        "lt" | "lt-"* ) url="lt-lt_${b10}_5425bdce.iso" ;;
        "lv" | "lv-"* ) url="lv-lv_${b10}_5426a93f.iso" ;;
        "nb" | "nb-"* ) url="nb-no_${b10}_67cd70cf.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_${b10}_43418e31.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_${b10}_7d9fc23a.iso" ;;
        "br" | "pt-br" ) url="pt-br_${b10}_159a147c.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_${b10}_003df1d7.iso" ;;
        "ro" | "ro-"* ) url="ro-ro_${b10}_068fb76e.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_${b10}_71cdb226.iso" ;;
        "sk" | "sk-"* ) url="sk-sk_${b10}_22793411.iso" ;;
        "sl" | "sl-"* ) url="sl-si_${b10}_91ae3317.iso" ;;
        "sr" | "sr-"* ) url="sr-latn-rs_${b10}_4f8045aa.iso" ;;
        "sv" | "sv-"* ) url="sv-se_${b10}_fe117cac.iso" ;;
        "th" | "th-"* ) url="th-th_${b10}_15986f75.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_${b10}_71319f58.iso" ;;
        "uk" | "uk-"* ) url="uk-ua_${b10}_0555f2a3.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_${b10}_ebffe3cd.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_${b10}_2dce9717.iso" ;;
      esac
      ;;
    "win10x64-ltsc" | "win10x64-enterprise-ltsc-eval" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar-sa_windows_10_enterprise_ltsc_2021_x64_dvd_60bc2a7a.iso" ;;
        "bg" | "bg-"* ) url="bg-bg_windows_10_enterprise_ltsc_2021_x64_dvd_b0887275.iso" ;;
        "cs" | "cs-"* ) url="cs-cz_windows_10_enterprise_ltsc_2021_x64_dvd_d624c653.iso" ;;
        "da" | "da-"* ) url="da-dk_windows_10_enterprise_ltsc_2021_x64_dvd_6ec511bb.iso" ;;
        "de" | "de-"* ) url="de-de_windows_10_enterprise_ltsc_2021_x64_dvd_71796d33.iso" ;;
        "el" | "el-"* ) url="el-gr_windows_10_enterprise_ltsc_2021_x64_dvd_c83eab34.iso" ;;
        "gb" | "en-gb" ) url="en-gb_windows_10_enterprise_ltsc_2021_x64_dvd_7fe51fe8.iso" ;;
        "en" | "en-"* )
          size=4899461120
          sum="c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d"
          url="en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso" ;;
        "mx" | "es-mx" ) url="es-mx_windows_10_enterprise_ltsc_2021_x64_dvd_f6aaf384.iso" ;;
        "es" | "es-"* ) url="es-es_windows_10_enterprise_ltsc_2021_x64_dvd_51d721ea.iso" ;;
        "et" | "et-"* ) url="et-ee_windows_10_enterprise_ltsc_2021_x64_dvd_012a5c50.iso" ;;
        "fi" | "fi-"* ) url="fi-fi_windows_10_enterprise_ltsc_2021_x64_dvd_551582d9.iso" ;;
        "ca" | "fr-ca" ) url="fr-ca_windows_10_enterprise_ltsc_2021_x64_dvd_2770e649.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_windows_10_enterprise_ltsc_2021_x64_dvd_bda01eb0.iso" ;;
        "he" | "he-"* ) url="he-il_windows_10_enterprise_ltsc_2021_x64_dvd_3a55ecd6.iso" ;;
        "hr" | "hr-"* ) url="hr-hr_windows_10_enterprise_ltsc_2021_x64_dvd_f5085b75.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_windows_10_enterprise_ltsc_2021_x64_dvd_d541ddb3.iso" ;;
        "it" | "it-"* ) url="it-it_windows_10_enterprise_ltsc_2021_x64_dvd_0c1aa034.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_windows_10_enterprise_ltsc_2021_x64_dvd_ef58c6a1.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_windows_10_enterprise_ltsc_2021_x64_dvd_6d26f398.iso" ;;
        "lt" | "lt-"* ) url="lt-lt_windows_10_enterprise_ltsc_2021_x64_dvd_9ffbbd5b.iso" ;;
        "lv" | "lv-"* ) url="lv-lv_windows_10_enterprise_ltsc_2021_x64_dvd_6c89d2e0.iso" ;;
        "nb" | "nb-"* ) url="nb-no_windows_10_enterprise_ltsc_2021_x64_dvd_c65c51a5.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_windows_10_enterprise_ltsc_2021_x64_dvd_88f53466.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_windows_10_enterprise_ltsc_2021_x64_dvd_eff40776.iso" ;;
        "br" | "pt-br" ) url="pt-br_windows_10_enterprise_ltsc_2021_x64_dvd_f318268e.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_windows_10_enterprise_ltsc_2021_x64_dvd_f2e9b6a0.iso" ;;
        "ro" | "ro-"* ) url="ro-ro_windows_10_enterprise_ltsc_2021_x64_dvd_ae2284d6.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_windows_10_enterprise_ltsc_2021_x64_dvd_5044a1e7.iso" ;;
        "sk" | "sk-"* ) url="sk-sk_windows_10_enterprise_ltsc_2021_x64_dvd_d6c64c5f.iso" ;;
        "sl" | "sl-"* ) url="sl-si_windows_10_enterprise_ltsc_2021_x64_dvd_ec090386.iso" ;;
        "sr" | "sr-"* ) url="sr-latn-rs_windows_10_enterprise_ltsc_2021_x64_dvd_2d2f8815.iso" ;;
        "sv" | "sv-"* ) url="sv-se_windows_10_enterprise_ltsc_2021_x64_dvd_9a28bb6b.iso" ;;
        "th" | "th-"* ) url="th-th_windows_10_enterprise_ltsc_2021_x64_dvd_b7ed34d6.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_windows_10_enterprise_ltsc_2021_x64_dvd_e55b1896.iso" ;;
        "uk" | "uk-"* ) url="uk-ua_windows_10_enterprise_ltsc_2021_x64_dvd_816da3c3.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_windows_10_enterprise_ltsc_2021_x64_dvd_80dba877.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso" ;;
      esac
      ;;
    "win10x64-iot" | "win10x64-enterprise-iot-eval" )
      [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0
      size=4851668992
      sum="a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
      url="en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
      ;;
    "win81x64-enterprise" | "win81x64-enterprise-eval" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_8.1_enterprise_with_update_x64_dvd_6050360.iso" ;;
        "bg" | "bg-"* ) url="bg_windows_8.1_enterprise_with_update_x64_dvd_6050367.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_8.1_enterprise_with_update_x64_dvd_6050393.iso" ;;
        "da" | "da-"* ) url="da_windows_8.1_enterprise_with_update_x64_dvd_6050394.iso" ;;
        "de" | "de-"* ) url="de_windows_8.1_enterprise_with_update_x64_dvd_6050501.iso" ;;
        "el" | "el-"* ) url="el_windows_8.1_enterprise_with_update_x64_dvd_6050503.iso" ;;
        "gb" | "en-gb" ) url="en-gb_windows_8.1_enterprise_with_update_x64_dvd_6054383.iso" ;;
        "en" | "en-"* )
          size=4139163648
          sum="c3c604c03677504e8905090a8ce5bb1dde76b6fd58e10f32e3a25bef21b2abe1"
          url="en_windows_8.1_enterprise_with_update_x64_dvd_6054382.iso" ;;
        "es" | "es-"* ) url="es_windows_8.1_enterprise_with_update_x64_dvd_6050578.iso" ;;
        "et" | "et-"* ) url="et_windows_8.1_enterprise_with_update_x64_dvd_6054384.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_8.1_enterprise_with_update_x64_dvd_6050497.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_8.1_enterprise_with_update_x64_dvd_6050499.iso" ;;
        "he" | "he-"* ) url="he_windows_8.1_enterprise_with_update_x64_dvd_6050504.iso" ;;
        "hr" | "hr-"* ) url="hr_windows_8.1_enterprise_with_update_x64_dvd_6050391.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_8.1_enterprise_with_update_x64_dvd_6050505.iso" ;;
        "it" | "it-"* ) url="it_windows_8.1_enterprise_with_update_x64_dvd_6050507.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_8.1_enterprise_with_update_x64_dvd_6050508.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_8.1_enterprise_with_update_x64_dvd_6050509.iso" ;;
        "lt" | "lt-"* ) url="lt_windows_8.1_enterprise_with_update_x64_dvd_6050511.iso" ;;
        "lv" | "lv-"* ) url="lv_windows_8.1_enterprise_with_update_x64_dvd_6050510.iso" ;;
        "nb" | "nb-"* ) url="nb_windows_8.1_enterprise_with_update_x64_dvd_6050512.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_8.1_enterprise_with_update_x64_dvd_6054381.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_8.1_enterprise_with_update_x64_dvd_6050515.iso" ;;
        "br" | "pt-br" ) url="pt_windows_8.1_enterprise_with_update_x64_dvd_6050521.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_8.1_enterprise_with_update_x64_dvd_6050526.iso" ;;
        "ro" | "ro-"* ) url="ro_windows_8.1_enterprise_with_update_x64_dvd_6050534.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_8.1_enterprise_with_update_x64_dvd_6050542.iso" ;;
        "sk" | "sk-"* ) url="sk_windows_8.1_enterprise_with_update_x64_dvd_6050562.iso" ;;
        "sl" | "sl-"* ) url="sl_windows_8.1_enterprise_with_update_x64_dvd_6050570.iso" ;;
        "sr" | "sr-"* ) url="sr-latn_windows_8.1_enterprise_with_update_x64_dvd_6050553.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_8.1_enterprise_with_update_x64_dvd_6050590.iso" ;;
        "th" | "th-"* ) url="th_windows_8.1_enterprise_with_update_x64_dvd_6050602.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_8.1_enterprise_with_update_x64_dvd_6050609.iso" ;;
        "uk" | "uk-"* ) url="uk_windows_8.1_enterprise_with_update_x64_dvd_6050618.iso" ;;
        "zh-hk" ) url="hk_windows_8.1_enterprise_with_update_x64_dvd_6050380.iso" ;;
        "zh-tw" ) url="tw_windows_8.1_enterprise_with_update_x64_dvd_6050387.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_8.1_enterprise_with_update_x64_dvd_6050374.iso" ;;
      esac
      ;;
    "win2025" | "win2025-eval" )
      case "${culture,,}" in
        "cs" | "cs-"* ) url="cs-cz_windows_server_2025_preview_x64_dvd_8b1f5b49.iso" ;;
        "de" | "de-"* ) url="de-de_windows_server_2025_preview_x64_dvd_1c3dfe1c.iso" ;;
        "en" | "en-"* )
          size=5307176960
          sum="2293897341febdcea599f5412300b470b5288c6fd2b89666a7b27d283e8d3cf3"
          url="en-us_windows_server_2025_preview_x64_dvd_ce9eb1a5.iso" ;;
        "es" | "es-"* ) url="es-es_windows_server_2025_preview_x64_dvd_b07cc858.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_windows_server_2025_preview_x64_dvd_036e8a78.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_windows_server_2025_preview_x64_dvd_2d5d77e5.iso" ;;
        "it" | "it-"* ) url="it-it_windows_server_2025_preview_x64_dvd_eaccac73.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_windows_server_2025_preview_x64_dvd_62f802be.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_windows_server_2025_preview_x64_dvd_e2c3e8f0.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_windows_server_2025_preview_x64_dvd_314b4ed1.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_windows_server_2025_preview_x64_dvd_be4b099e.iso" ;;
        "br" | "pt-br" ) url="pt-br_windows_server_2025_preview_x64_dvd_993c803a.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_windows_server_2025_preview_x64_dvd_869aa534.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_windows_server_2025_preview_x64_dvd_5ada1817.iso" ;;
        "sv" | "sv-"* ) url="sv-se_windows_server_2025_preview_x64_dvd_5fafd4f7.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_windows_server_2025_preview_x64_dvd_3aab7fda.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_windows_server_2025_preview_x64_dvd_9b147dcd.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_windows_server_2025_preview_x64_dvd_a12bb0bf.iso" ;;
      esac
      ;;
    "win2022" | "win2022-eval" )
      case "${culture,,}" in
        "cs" | "cs-"* ) url="cs-cz_${s22}.iso" ;;
        "de" | "de-"* ) url="de-de_${s22}.iso" ;;
        "en" | "en-"* )
          size=5966127104
          sum="0b70ea0e3969ad63dfe7e819d76d37ea37582e9f29e0f8d70b38e6b978406ee9"
          url="en-us_${s22}.iso" ;;
        "es" | "es-"* ) url="es-es_${s22}.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_${s22}.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_${s22}.iso" ;;
        "it" | "it-"* ) url="it-it_${s22}.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_${s22}.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_${s22}.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_${s22}.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_${s22}.iso" ;;
        "br" | "pt-br" ) url="pt-br_${s22}.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_${s22}.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_${s22}.iso" ;;
        "sv" | "sv-"* ) url="sv-se_${s22}.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_${s22}.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_${s22}.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_${s22}.iso" ;;
      esac
      ;;
    "win2019" | "win2019-eval" )
      case "${culture,,}" in
        "cs" | "cs-"* ) url="cs-cz_windows_server_2019_x64_dvd_3781c31c.iso" ;;
        "de" | "de-"* ) url="de-de_windows_server_2019_x64_dvd_132f7aa4.iso" ;;
        "en" | "en-"* )
          size=5651695616
          sum="ea247e5cf4df3e5829bfaaf45d899933a2a67b1c700a02ee8141287a8520261c"
          url="en-us_windows_server_2019_x64_dvd_f9475476.iso" ;;
        "es" | "es-"* ) url="es-es_windows_server_2019_x64_dvd_3ce0fd9e.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_windows_server_2019_x64_dvd_f6f6acf6.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_windows_server_2019_x64_dvd_1d834c46.iso" ;;
        "it" | "it-"* ) url="it-it_windows_server_2019_x64_dvd_454267de.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_windows_server_2019_x64_dvd_3899c3a3.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_windows_server_2019_x64_dvd_84101c0a.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_windows_server_2019_x64_dvd_f69d914e.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_windows_server_2019_x64_dvd_a50263e1.iso" ;;
        "br" | "pt-br" ) url="pt-br_windows_server_2019_x64_dvd_aee8c1c2.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_windows_server_2019_x64_dvd_464373e8.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_windows_server_2019_x64_dvd_e02b76ba.iso" ;;
        "sv" | "sv-"* ) url="sv-se_windows_server_2019_x64_dvd_48c1aeff.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_windows_server_2019_x64_dvd_b51af600.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_windows_server_2019_x64_dvd_a4c80409.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_windows_server_2019_x64_dvd_19d65722.iso" ;;
      esac
      ;;
    "win7x64" | "win7x64-enterprise" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_7_enterprise_with_sp1_x64_dvd_u_677643.iso" ;;
        "bg" | "bg-"* ) url="bg_windows_7_enterprise_with_sp1_x64_dvd_u_677644.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_7_enterprise_with_sp1_x64_dvd_u_677646.iso" ;;
        "da" | "da-"* ) url="da_windows_7_enterprise_with_sp1_x64_dvd_u_677648.iso" ;;
        "de" | "de-"* ) url="de_windows_7_enterprise_with_sp1_x64_dvd_u_677649.iso" ;;
        "el" | "el-"* ) url="el_windows_7_enterprise_with_sp1_x64_dvd_u_677650.iso" ;;
        "en" | "en-"* )
          size=3182604288
          sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
          url="en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso" ;;
        "es" | "es-"* ) url="es_windows_7_enterprise_with_sp1_x64_dvd_u_677652.iso" ;;
        "et" | "et-"* ) url="et_windows_7_enterprise_with_sp1_x64_dvd_u_677653.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_7_enterprise_with_sp1_x64_dvd_u_677655.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_7_enterprise_with_sp1_x64_dvd_u_677656.iso" ;;
        "he" | "he-"* ) url="he_windows_7_enterprise_with_sp1_x64_dvd_u_677657.iso" ;;
        "hr" | "hr-"* ) url="hr_windows_7_enterprise_with_sp1_x64_dvd_u_677658.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_7_enterprise_with_sp1_x64_dvd_u_677659.iso" ;;
        "it" | "it-"* ) url="it_windows_7_enterprise_with_sp1_x64_dvd_u_677660.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_7_enterprise_with_sp1_x64_dvd_u_677662.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_7_enterprise_k_with_sp1_x64_dvd_u_677728.iso" ;;
        "lt" | "lt-"* ) url="lt_windows_7_enterprise_with_sp1_x64_dvd_u_677663.iso" ;;
        "lv" | "lv-"* ) url="lv_windows_7_enterprise_with_sp1_x64_dvd_u_677664.iso" ;;
        "nb" | "nb-"* ) url="no_windows_7_enterprise_with_sp1_x64_dvd_u_677665.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_7_enterprise_with_sp1_x64_dvd_u_677666.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_7_enterprise_with_sp1_x64_dvd_u_677667.iso" ;;
        "br" | "pt-br" ) url="pt_windows_7_enterprise_with_sp1_x64_dvd_u_677668.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_7_enterprise_with_sp1_x64_dvd_u_677669.iso" ;;
        "ro" | "ro-"* ) url="ro_windows_7_enterprise_with_sp1_x64_dvd_u_677670.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_7_enterprise_with_sp1_x64_dvd_u_677671.iso" ;;
        "sk" | "sk-"* ) url="sk_windows_7_enterprise_with_sp1_x64_dvd_u_677673.iso" ;;
        "sl" | "sl-"* ) url="sl_windows_7_enterprise_with_sp1_x64_dvd_u_677674.iso" ;;
        "sr" | "sr-"* ) url="sr_windows_7_enterprise_with_sp1_x64_dvd_u_677675.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_7_enterprise_with_sp1_x64_dvd_u_677676.iso" ;;
        "th" | "th-"* ) url="th_windows_7_enterprise_with_sp1_x64_dvd_u_677678.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_7_enterprise_with_sp1_x64_dvd_u_677681.iso" ;;
        "uk" | "uk-"* ) url="uk_windows_7_enterprise_with_sp1_x64_dvd_u_677683.iso" ;;
        "zh-hk" ) url="hk_windows_7_enterprise_with_sp1_x64_dvd_u_677687.iso" ;;
        "zh-tw" ) url="tw_windows_7_enterprise_with_sp1_x64_dvd_u_677689.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_7_enterprise_with_sp1_x64_dvd_u_677685.iso" ;;
      esac
      ;;
    "win7x64-ultimate" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_7_ultimate_with_sp1_x64_dvd_u_677345.iso" ;;
        "bg" | "bg-"* ) url="bg_windows_7_ultimate_with_sp1_x64_dvd_u_677363.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_7_ultimate_with_sp1_x64_dvd_u_677376.iso" ;;
        "da" | "da-"* ) url="da_windows_7_ultimate_with_sp1_x64_dvd_u_677294.iso" ;;
        "de" | "de-"* ) url="de_windows_7_ultimate_with_sp1_x64_dvd_u_677306.iso" ;;
        "el" | "el-"* ) url="el_windows_7_ultimate_with_sp1_x64_dvd_u_677318.iso" ;;
        "en" | "en-"* )
          size=3320903680
          sum="36f4fa2416d0982697ab106e3a72d2e120dbcdb6cc54fd3906d06120d0653808"
          url="en_windows_7_ultimate_with_sp1_x64_dvd_u_677332.iso" ;;
        "es" | "es-"* ) url="es_windows_7_ultimate_with_sp1_x64_dvd_u_677350.iso" ;;
        "et" | "et-"* ) url="et_windows_7_ultimate_with_sp1_x64_dvd_u_677368.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_7_ultimate_with_sp1_x64_dvd_u_677378.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_7_ultimate_with_sp1_x64_dvd_u_677299.iso" ;;
        "he" | "he-"* ) url="he_windows_7_ultimate_with_sp1_x64_dvd_u_677312.iso" ;;
        "hr" | "hr-"* ) url="hr_windows_7_ultimate_with_sp1_x64_dvd_u_677324.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_7_ultimate_with_sp1_x64_dvd_u_677338.iso" ;;
        "it" | "it-"* ) url="it_windows_7_ultimate_with_sp1_x64_dvd_u_677356.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_7_ultimate_with_sp1_x64_dvd_u_677372.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_7_ultimate_k_with_sp1_x64_dvd_u_677502.iso" ;;
        "lt" | "lt-"* ) url="lt_windows_7_ultimate_with_sp1_x64_dvd_u_677379.iso" ;;
        "lv" | "lv-"* ) url="lv_windows_7_ultimate_with_sp1_x64_dvd_u_677302.iso" ;;
        "nb" | "nb-"* ) url="no_windows_7_ultimate_with_sp1_x64_dvd_u_677314.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_7_ultimate_with_sp1_x64_dvd_u_677325.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_7_ultimate_with_sp1_x64_dvd_u_677341.iso" ;;
        "br" | "pt-br" ) url="pt_windows_7_ultimate_with_sp1_x64_dvd_u_677358.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_7_ultimate_with_sp1_x64_dvd_u_677373.iso" ;;
        "ro" | "ro-"* ) url="ro_windows_7_ultimate_with_sp1_x64_dvd_u_677380.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_7_ultimate_with_sp1_x64_dvd_u_677391.iso" ;;
        "sk" | "sk-"* ) url="sk_windows_7_ultimate_with_sp1_x64_dvd_u_677393.iso" ;;
        "sl" | "sl-"* ) url="sl_windows_7_ultimate_with_sp1_x64_dvd_u_677396.iso" ;;
        "sr" | "sr-"* ) url="sr_windows_7_ultimate_with_sp1_x64_dvd_u_677398.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_7_ultimate_with_sp1_x64_dvd_u_677400.iso" ;;
        "th" | "th-"* ) url="th_windows_7_ultimate_with_sp1_x64_dvd_u_677402.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_7_ultimate_with_sp1_x64_dvd_u_677404.iso" ;;
        "uk" | "uk-"* ) url="uk_windows_7_ultimate_with_sp1_x64_dvd_u_677406.iso" ;;
        "zh-hk" ) url="hk_windows_7_ultimate_with_sp1_x64_dvd_u_677411.iso" ;;
        "zh-tw" ) url="tw_windows_7_ultimate_with_sp1_x64_dvd_u_677414.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso" ;;
      esac
      ;;
    "win7x86" | "win7x86-enterprise" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_7_enterprise_with_sp1_x86_dvd_u_677691.iso" ;;
        "bg" | "bg-"* ) url="bg_windows_7_enterprise_with_sp1_x86_dvd_u_677693.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_7_enterprise_with_sp1_x86_dvd_u_677695.iso" ;;
        "da" | "da-"* ) url="da_windows_7_enterprise_with_sp1_x86_dvd_u_677698.iso" ;;
        "de" | "de-"* ) url="de_windows_7_enterprise_with_sp1_x86_dvd_u_677702.iso" ;;
        "el" | "el-"* ) url="el_windows_7_enterprise_with_sp1_x86_dvd_u_677706.iso" ;;
        "en" | "en-"* )
          size=2434502656
          sum="8bdd46ff8cb8b8de9c4aba02706629c8983c45e87da110e64e13be17c8434dad"
          url="en_windows_7_enterprise_with_sp1_x86_dvd_u_677710.iso" ;;
        "es" | "es-"* ) url="es_windows_7_enterprise_with_sp1_x86_dvd_u_677714.iso" ;;
        "et" | "et-"* ) url="et_windows_7_enterprise_with_sp1_x86_dvd_u_677718.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_7_enterprise_with_sp1_x86_dvd_u_677722.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_7_enterprise_with_sp1_x86_dvd_u_677727.iso" ;;
        "he" | "he-"* ) url="he_windows_7_enterprise_with_sp1_x86_dvd_u_677733.iso" ;;
        "hr" | "hr-"* ) url="hr_windows_7_enterprise_with_sp1_x86_dvd_u_677739.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_7_enterprise_with_sp1_x86_dvd_u_677744.iso" ;;
        "it" | "it-"* ) url="it_windows_7_enterprise_with_sp1_x86_dvd_u_677749.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_7_enterprise_with_sp1_x86_dvd_u_677757.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_7_enterprise_k_with_sp1_x86_dvd_u_677732.iso" ;;
        "lt" | "lt-"* ) url="lt_windows_7_enterprise_with_sp1_x86_dvd_u_677764.iso" ;;
        "lv" | "lv-"* ) url="lv_windows_7_enterprise_with_sp1_x86_dvd_u_677677.iso" ;;
        "nb" | "nb-"* ) url="no_windows_7_enterprise_with_sp1_x86_dvd_u_677679.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_7_enterprise_with_sp1_x86_dvd_u_677682.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_7_enterprise_with_sp1_x86_dvd_u_677684.iso" ;;
        "br" | "pt-br" ) url="pt_windows_7_enterprise_with_sp1_x86_dvd_u_677686.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_7_enterprise_with_sp1_x86_dvd_u_677688.iso" ;;
        "ro" | "ro-"* ) url="ro_windows_7_enterprise_with_sp1_x86_dvd_u_677690.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_7_enterprise_with_sp1_x86_dvd_u_677692.iso" ;;
        "sk" | "sk-"* ) url="sk_windows_7_enterprise_with_sp1_x86_dvd_u_677694.iso" ;;
        "sl" | "sl-"* ) url="sl_windows_7_enterprise_with_sp1_x86_dvd_u_677696.iso" ;;
        "sr" | "sr-"* ) url="sr_windows_7_enterprise_with_sp1_x86_dvd_u_677699.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_7_enterprise_with_sp1_x86_dvd_u_677701.iso" ;;
        "th" | "th-"* ) url="th_windows_7_enterprise_with_sp1_x86_dvd_u_677705.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_7_enterprise_with_sp1_x86_dvd_u_677708.iso" ;;
        "uk" | "uk-"* ) url="uk_windows_7_enterprise_with_sp1_x86_dvd_u_677712.iso" ;;
        "zh-hk" ) url="hk_windows_7_enterprise_with_sp1_x86_dvd_u_677720.iso" ;;
        "zh-tw" ) url="tw_windows_7_enterprise_with_sp1_x86_dvd_u_677723.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_7_enterprise_with_sp1_x86_dvd_u_677716.iso" ;;
      esac
      ;;
    "win7x86-ultimate" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_7_ultimate_with_sp1_x86_dvd_u_677448.iso" ;;
        "bg" | "bg-"* ) url="bg_windows_7_ultimate_with_sp1_x86_dvd_u_677450.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_7_ultimate_with_sp1_x86_dvd_u_677452.iso" ;;
        "da" | "da-"* ) url="da_windows_7_ultimate_with_sp1_x86_dvd_u_677454.iso" ;;
        "de" | "de-"* ) url="de_windows_7_ultimate_with_sp1_x86_dvd_u_677456.iso" ;;
        "el" | "el-"* ) url="el_windows_7_ultimate_with_sp1_x86_dvd_u_677458.iso" ;;
        "en" | "en-"* )
          size=2564476928
          sum="e2c009a66d63a742941f5087acae1aa438dcbe87010bddd53884b1af6b22c940"
          url="en_windows_7_ultimate_with_sp1_x86_dvd_u_677460.iso" ;;
        "es" | "es-"* ) url="es_windows_7_ultimate_with_sp1_x86_dvd_u_677462.iso" ;;
        "et" | "et-"* ) url="et_windows_7_ultimate_with_sp1_x86_dvd_u_677464.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_7_ultimate_with_sp1_x86_dvd_u_677466.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_7_ultimate_with_sp1_x86_dvd_u_677434.iso" ;;
        "he" | "he-"* ) url="he_windows_7_ultimate_with_sp1_x86_dvd_u_677436.iso" ;;
        "hr" | "hr-"* ) url="hr_windows_7_ultimate_with_sp1_x86_dvd_u_677438.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_7_ultimate_with_sp1_x86_dvd_u_677441.iso" ;;
        "it" | "it-"* ) url="it_windows_7_ultimate_with_sp1_x86_dvd_u_677443.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_7_ultimate_with_sp1_x86_dvd_u_677445.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_7_ultimate_k_with_sp1_x86_dvd_u_677508.iso" ;;
        "lt" | "lt-"* ) url="lt_windows_7_ultimate_with_sp1_x86_dvd_u_677447.iso" ;;
        "lv" | "lv-"* ) url="lv_windows_7_ultimate_with_sp1_x86_dvd_u_677449.iso" ;;
        "nb" | "nb-"* ) url="no_windows_7_ultimate_with_sp1_x86_dvd_u_677451.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_7_ultimate_with_sp1_x86_dvd_u_677453.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_7_ultimate_with_sp1_x86_dvd_u_677455.iso" ;;
        "br" | "pt-br" ) url="pt_windows_7_ultimate_with_sp1_x86_dvd_u_677457.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_7_ultimate_with_sp1_x86_dvd_u_677459.iso" ;;
        "ro" | "ro-"* ) url="ro_windows_7_ultimate_with_sp1_x86_dvd_u_677461.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_7_ultimate_with_sp1_x86_dvd_u_677463.iso" ;;
        "sk" | "sk-"* ) url="sk_windows_7_ultimate_with_sp1_x86_dvd_u_677465.iso" ;;
        "sl" | "sl-"* ) url="sl_windows_7_ultimate_with_sp1_x86_dvd_u_677467.iso" ;;
        "sr" | "sr-"* ) url="sr_windows_7_ultimate_with_sp1_x86_dvd_u_677468.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_7_ultimate_with_sp1_x86_dvd_u_677482.iso" ;;
        "th" | "th-"* ) url="th_windows_7_ultimate_with_sp1_x86_dvd_u_677483.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_7_ultimate_with_sp1_x86_dvd_u_677484.iso" ;;
        "uk" | "uk-"* ) url="uk_windows_7_ultimate_with_sp1_x86_dvd_u_677485.iso" ;;
        "zh-hk" ) url="hk_windows_7_ultimate_with_sp1_x86_dvd_u_677487.iso" ;;
        "zh-tw" ) url="tw_windows_7_ultimate_with_sp1_x86_dvd_u_677488.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_7_ultimate_with_sp1_x86_dvd_u_677486.iso" ;;
      esac
      ;;
    "winvistax64" | "winvistax64-enterprise" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_vista_enterprise_with_sp2_x64_dvd_x15-40408.iso" ;;
        "bg" | "bg-"* ) url="bg_windows_vista_enterprise_with_sp2_x64_dvd_x15-40410.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_vista_enterprise_with_sp2_x64_dvd_x15-40412.iso" ;;
        "da" | "da-"* ) url="da_windows_vista_enterprise_with_sp2_x64_dvd_x15-40416.iso" ;;
        "de" | "de-"* ) url="de_windows_vista_enterprise_sp2_x64_dvd_342376.iso" ;;
        "el" | "el-"* ) url="el_windows_vista_enterprise_with_sp2_x64_dvd_x15-40423.iso" ;;
        "en" | "en-"* )
          size=3205953536
          sum="0a0cd511b3eac95c6f081419c9c65b12317b9d6a8d9707f89d646c910e788016"
          url="en_windows_vista_enterprise_sp2_x64_dvd_342332.iso" ;;
        "es" | "es-"* ) url="es_windows_vista_enterprise_sp2_x64_dvd_342415.iso" ;;
        "et" | "et-"* ) url="et_windows_vista_enterprise_with_sp2_x64_dvd_x15-40437.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_vista_enterprise_with_sp2_x64_dvd_x15-40451.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_vista_enterprise_sp2_x64_dvd_342355.iso" ;;
        "he" | "he-"* ) url="he_windows_vista_enterprise_with_sp2_x64_dvd_x15-40425.iso" ;;
        "hr" | "hr-"* ) url="hr_windows_vista_enterprise_with_sp2_x64_dvd_x15-40396.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_vista_enterprise_with_sp2_x64_dvd_x15-40427.iso" ;;
        "it" | "it-"* ) url="it_windows_vista_enterprise_with_sp2_x64_dvd_x15-40429.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_vista_enterprise_sp2_x64_dvd_342393.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_vista_enterprise_k_with_sp2_x64_dvd_x15-40433.iso" ;;
        "lt" | "lt-"* ) url="lt_windows_vista_enterprise_with_sp2_x64_dvd_x15-40394.iso" ;;
        "lv" | "lv-"* ) url="lv_windows_vista_enterprise_with_sp2_x64_dvd_x15-40392.iso" ;;
        "nb" | "nb-"* ) url="no_windows_vista_enterprise_with_sp2_x64_dvd_x15-40439.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_vista_enterprise_with_sp2_x64_dvd_x15-40441.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_vista_enterprise_with_sp2_x64_dvd_x15-40445.iso" ;;
        "br" | "pt-br" ) url="pt_windows_vista_enterprise_with_sp2_x64_dvd_x15-40400.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_vista_enterprise_with_sp2_x64_dvd_x15-40443.iso" ;;
        "ro" | "ro-"* ) url="ro_windows_vista_enterprise_with_sp2_x64_dvd_x15-40447.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_vista_enterprise_with_sp2_x64_dvd_x15-40455.iso" ;;
        "sk" | "sk-"* ) url="sk_windows_vista_enterprise_with_sp2_x64_dvd_x15-40453.iso" ;;
        "sl" | "sl-"* ) url="sl_windows_vista_enterprise_with_sp2_x64_dvd_x15-40435.iso" ;;
        "sr" | "sr-"* ) url="sr_windows_vista_enterprise_with_sp2_x64_dvd_x15-40406.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_vista_enterprise_with_sp2_x64_dvd_x15-40449.iso" ;;
        "th" | "th-"* ) url="th_windows_vista_enterprise_with_sp2_x64_dvd_x15-40457.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_vista_enterprise_with_sp2_x64_dvd_x15-40459.iso" ;;
        "uk" | "uk-"* ) url="uk_windows_vista_enterprise_with_sp2_x64_dvd_x15-40398.iso" ;;
        "zh-hk" ) url="hk_windows_vista_enterprise_with_sp2_x64_dvd_x15-40463.iso" ;;
        "zh-tw" ) url="tw_windows_vista_enterprise_with_sp2_x64_dvd_x15-40461.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_vista_enterprise_with_sp2_x64_dvd_x15-40402.iso" ;;
      esac
      ;;
    "winvistax64-ultimate" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_vista_with_sp2_x64_dvd_x15-36318.iso" ;;
        "bg" | "bg-"* ) url="bg_windows_vista_with_sp2_x64_dvd_x15-36321.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_vista_with_sp2_x64_dvd_x15-36327.iso" ;;
        "da" | "da-"* ) url="da_windows_vista_with_sp2_x64_dvd_x15-36329.iso" ;;
        "de" | "de-"* ) url="de_windows_vista_sp2_x64_dvd_342287.iso" ;;
        "el" | "el-"* ) url="el_windows_vista_with_sp2_x64_dvd_x15-36343.iso" ;;
        "en" | "en-"* )
          size=3861460992
          sum="edf9f947c5791469fd7d2d40a5dcce663efa754f91847aa1d28ed7f585675b78"
          url="en_windows_vista_sp2_x64_dvd_342267.iso" ;;
        "es" | "es-"* ) url="es_windows_vista_sp2_x64_dvd_342309.iso" ;;
        "et" | "et-"* ) url="et_windows_vista_with_sp2_x64_dvd_x15-36335.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_vista_with_sp2_x64_dvd_x15-36337.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_vista_sp2_x64_dvd_342277.iso" ;;
        "he" | "he-"* ) url="he_windows_vista_with_sp2_x64_dvd_x15-36344.iso" ;;
        "hr" | "hr-"* ) url="hr_windows_vista_with_sp2_x64_dvd_x15-36325.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_vista_with_sp2_x64_dvd_x15-36346.iso" ;;
        "it" | "it-"* ) url="it_windows_vista_with_sp2_x64_dvd_x15-36348.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_vista_sp2_x64_dvd_342298.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_vista_k_and_kn_with_sp2_x86_dvd_x15-36302.iso" ;;
        "lt" | "lt-"* ) url="lt_windows_vista_with_sp2_x64_dvd_x15-36355.iso" ;;
        "lv" | "lv-"* ) url="lv_windows_vista_with_sp2_x64_dvd_x15-36353.iso" ;;
        "nb" | "nb-"* ) url="no_windows_vista_with_sp2_x64_dvd_x15-36357.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_vista_with_sp2_x64_dvd_x15-36331.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_vista_with_sp2_x64_dvd_x15-36359.iso" ;;
        "br" | "pt-br" ) url="pt_windows_vista_with_sp2_x64_dvd_x15-36319.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_vista_with_sp2_x64_dvd_x15-36361.iso" ;;
        "ro" | "ro-"* ) url="ro_windows_vista_with_sp2_x64_dvd_x15-36363.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_vista_with_sp2_x64_dvd_x15-36364.iso" ;;
        "sk" | "sk-"* ) url="sk_windows_vista_with_sp2_x64_dvd_x15-36367.iso" ;;
        "sl" | "sl-"* ) url="sl_windows_vista_with_sp2_x64_dvd_x15-36369.iso" ;;
        "sr" | "sr-"* ) url="sr_windows_vista_with_sp2_x64_dvd_x15-36365.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_vista_with_sp2_x64_dvd_x15-36373.iso" ;;
        "th" | "th-"* ) url="th_windows_vista_with_sp2_x64_dvd_x15-36374.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_vista_with_sp2_x64_dvd_x15-36375.iso" ;;
        "uk" | "uk-"* ) url="uk_windows_vista_with_sp2_x64_dvd_x15-36376.iso" ;;
        "zh-hk" ) url="hk_windows_vista_with_sp2_x64_dvd_x15-36324.iso" ;;
        "zh-tw" ) url="tw_windows_vista_with_sp2_x64_dvd_x15-36323.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_vista_with_sp2_x64_dvd_x15-36322.iso" ;;
      esac
      ;;
    "winvistax86" | "winvistax86-enterprise" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_vista_enterprise_with_sp2_x86_dvd_x15-40263.iso" ;;
        "bg" | "bg-"* ) url="bg_windows_vista_enterprise_with_sp2_x86_dvd_x15-40265.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_vista_enterprise_with_sp2_x86_dvd_x15-40267.iso" ;;
        "da" | "da-"* ) url="da_windows_vista_enterprise_with_sp2_x86_dvd_x15-40271.iso" ;;
        "de" | "de-"* ) url="de_windows_vista_enterprise_sp2_x86_dvd_342373.iso" ;;
        "el" | "el-"* ) url="el_windows_vista_enterprise_with_sp2_x86_dvd_x15-40277.iso" ;;
        "en" | "en-"* )
          size=2420981760
          sum="54e2720004041e7db988a391543ea5228b0affc28efcf9303d2d0ff9402067f5"
          url="en_windows_vista_enterprise_sp2_x86_dvd_342329.iso" ;;
        "es" | "es-"* ) url="es_windows_vista_enterprise_sp2_x86_dvd_342413.iso" ;;
        "et" | "et-"* ) url="et_windows_vista_enterprise_with_sp2_x86_dvd_x15-40291.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_vista_enterprise_with_sp2_x86_dvd_x15-40305.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_vista_enterprise_sp2_x86_dvd_342352.iso" ;;
        "he" | "he-"* ) url="he_windows_vista_enterprise_with_sp2_x86_dvd_x15-40279.iso" ;;
        "hr" | "hr-"* ) url="hr_windows_vista_enterprise_with_sp2_x86_dvd_x15-40251.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_vista_enterprise_with_sp2_x86_dvd_x15-40281.iso" ;;
        "it" | "it-"* ) url="it_windows_vista_enterprise_with_sp2_x86_dvd_x15-40283.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_vista_enterprise_sp2_x86_dvd_342391.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_vista_enterprise_k_with_sp2_x86_dvd_x15-40287.iso" ;;
        "lt" | "lt-"* ) url="lt_windows_vista_enterprise_with_sp2_x86_dvd_x15-40249.iso" ;;
        "lv" | "lv-"* ) url="lv_windows_vista_enterprise_with_sp2_x86_dvd_x15-40247.iso" ;;
        "nb" | "nb-"* ) url="no_windows_vista_enterprise_with_sp2_x86_dvd_x15-40293.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_vista_enterprise_with_sp2_x86_dvd_x15-40295.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_vista_enterprise_with_sp2_x86_dvd_x15-40299.iso" ;;
        "br" | "pt-br" ) url="pt_windows_vista_enterprise_with_sp2_x86_dvd_x15-40255.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_vista_enterprise_with_sp2_x86_dvd_x15-40297.iso" ;;
        "ro" | "ro-"* ) url="ro_windows_vista_enterprise_with_sp2_x86_dvd_x15-40301.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_vista_enterprise_with_sp2_x86_dvd_x15-40309.iso" ;;
        "sk" | "sk-"* ) url="sk_windows_vista_enterprise_with_sp2_x86_dvd_x15-40307.iso" ;;
        "sl" | "sl-"* ) url="sl_windows_vista_enterprise_with_sp2_x86_dvd_x15-40289.iso" ;;
        "sr" | "sr-"* ) url="sr_windows_vista_enterprise_with_sp2_x86_dvd_x15-40261.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_vista_enterprise_with_sp2_x86_dvd_x15-40303.iso" ;;
        "th" | "th-"* ) url="th_windows_vista_enterprise_with_sp2_x86_dvd_x15-40311.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_vista_enterprise_with_sp2_x86_dvd_x15-40313.iso" ;;
        "uk" | "uk-"* ) url="uk_windows_vista_enterprise_with_sp2_x86_dvd_x15-40253.iso" ;;
        "zh-hk" ) url="hk_windows_vista_enterprise_with_sp2_x86_dvd_x15-40317.iso" ;;
        "zh-tw" ) url="tw_windows_vista_enterprise_with_sp2_x86_dvd_x15-40315.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_vista_enterprise_with_sp2_x86_dvd_x15-40257.iso" ;;
      esac
      ;;
    "winvistax86-ultimate" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_vista_with_sp2_x86_dvd_x15-36282.iso" ;;
        "bg" | "bg-"* ) url="bg_windows_vista_with_sp2_x86_dvd_x15-36284.iso" ;;
        "hr" | "hr-"* ) url="hr_windows_vista_with_sp2_x86_dvd_x15-36288.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_vista_with_sp2_x86_dvd_x15-36289.iso" ;;
        "da" | "da-"* ) url="da_windows_vista_with_sp2_x86_dvd_x15-36290.iso" ;;
        "de" | "de-"* ) url="de_windows_vista_sp2_x86_dvd_342286.iso" ;;
        "el" | "el-"* ) url="el_windows_vista_with_sp2_x86_dvd_x15-36297.iso" ;;
        "en" | "en-"* )
          size=3243413504
          sum="9c36fed4255bd05a8506b2da88f9aad73643395e155e609398aacd2b5276289c"
          url="en_windows_vista_with_sp2_x86_dvd_342266.iso" ;;
        "es" | "es-"* ) url="es_windows_vista_sp2_x86_dvd_342308.iso" ;;
        "et" | "et-"* ) url="et_windows_vista_with_sp2_x86_dvd_x15-36293.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_vista_with_sp2_x86_dvd_x15-36294.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_vista_sp2_x86_dvd_342276.iso" ;;
        "he" | "he-"* ) url="he_windows_vista_with_sp2_x86_dvd_x15-36298.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_vista_with_sp2_x86_dvd_x15-36299.iso" ;;
        "it" | "it-"* ) url="it_windows_vista_with_sp2_x86_dvd_x15-36300.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_vista_sp2_x86_dvd_342296.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_vista_k_with_sp2_x64_dvd_x15-36350.iso" ;;
        "lt" | "lt-"* ) url="lt_windows_vista_with_sp2_x86_dvd_x15-36304.iso" ;;
        "lv" | "lv-"* ) url="lv_windows_vista_with_sp2_x86_dvd_x15-36303.iso" ;;
        "nb" | "nb-"* ) url="no_windows_vista_with_sp2_x86_dvd_x15-36305.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_vista_with_sp2_x86_dvd_x15-36291.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_vista_with_sp2_x86_dvd_x15-36306.iso" ;;
        "br" | "pt-br" ) url="pt_windows_vista_with_sp2_x86_dvd_x15-36283.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_vista_with_sp2_x86_dvd_x15-36307.iso" ;;
        "ro" | "ro-"* ) url="ro_windows_vista_with_sp2_x86_dvd_x15-36308.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_vista_with_sp2_x86_dvd_x15-36309.iso" ;;
        "sk" | "sk-"* ) url="sk_windows_vista_with_sp2_x86_dvd_x15-36311.iso" ;;
        "sl" | "sl-"* ) url="sl_windows_vista_with_sp2_x86_dvd_x15-36312.iso" ;;
        "sr" | "sr-"* ) url="sr_windows_vista_with_sp2_x86_dvd_x15-36310.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_vista_with_sp2_x86_dvd_x15-36314.iso" ;;
        "th" | "th-"* ) url="th_windows_vista_with_sp2_x86_dvd_x15-36315.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_vista_with_sp2_x86_dvd_x15-36316.iso" ;;
        "uk" | "uk-"* ) url="uk_windows_vista_with_sp2_x86_dvd_x15-36317.iso" ;;
        "zh-hk" ) url="hk_windows_vista_with_sp2_x86_dvd_x15-36287.iso" ;;
        "zh-tw" ) url="tw_windows_vista_with_sp2_x86_dvd_x15-36286.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_vista_with_sp2_x86_dvd_x15-36285.iso" ;;
      esac
      ;;
    "winxpx86" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74065.iso" ;;
        "cs" | "cs-"* ) url="cs_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73965.iso" ;;
        "da" | "da-"* ) url="da_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73968.iso" ;;
        "de" | "de-"* ) url="de_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73985.iso" ;;
        "el" | "el-"* ) url="el_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73988.iso" ;;
        "es" | "es-"* ) url="es_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74009.iso" ;;
        "fi" | "fi-"* ) url="fi_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73979.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73982.iso" ;;
        "he" | "he-"* ) url="he_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74143.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73991.iso" ;;
        "it" | "it-"* ) url="it_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73994.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_xp_professional_with_service_pack_3_x86_dvd_vl_x14-74058.iso" ;;
        "nb" | "nb-"* ) url="no_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74000.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73971.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74003.iso" ;;
        "br" | "pt-br" ) url="pt-br_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74137.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74006.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74146.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74012.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74085.iso" ;;
        "zh-hk" ) url="zh-hk_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74075.iso" ;;
        "zh-tw" ) url="zh-tw_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74140.iso" ;;
        "zh" | "zh-"* ) url="zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74070.iso" ;;
      esac
      ;;
    "winxpx64" )
      [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0
      size=628168704
      sum="b641514c2265ba6c0a9ddbcfa4a6daaac6539db8d1ce704366cdfe5a516e0495"
      url="en_win_xp_pro_x64_with_sp2_vl_x13-41611.iso"
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
    "winxpx86" )
      size=617756672
      sum="62b6c91563bad6cd12a352aa018627c314cfc5162d8e9f8af0756a642e602a46"
      url="XPPRO_SP3_ENU/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
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

migrateFiles() {

  local base="$1"
  local version="$2"
  local file=""

  [ -f "$base" ] && return 0

  [[ "${version,,}" == "tiny10" ]] && file="tiny10_x64_23h2.iso"
  [[ "${version,,}" == "tiny11" ]] && file="tiny11_2311_x64.iso"
  [[ "${version,,}" == "core11" ]] && file="tiny11_core_x64_beta_1.iso"
  [[ "${version,,}" == "winxpx86" ]] && file="en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
  [[ "${version,,}" == "winvistax64" ]] && file="en_windows_vista_sp2_x64_dvd_342267.iso"
  [[ "${version,,}" == "win7x64" ]] && file="en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"

  [ ! -f "$STORAGE/$file" ] && return 0
  ! mv -f "$STORAGE/$file" "$base" && return 1

  return 0
}

prepareInstall() {

  local dir="$2"
  local desc="$3"
  local arch="$4"
  local key="$5"
  local driver="$6"
  local drivers="$TMP/drivers"

  ETFS="[BOOT]/Boot-NoEmul.img"

  if [ ! -f "$dir/$ETFS" ] || [ ! -s "$dir/$ETFS" ]; then
    error "Failed to locate file \"$ETFS\" in $desc ISO image!" && return 1
  fi

  local msg="Adding drivers to image..."
  info "$msg" && html "$msg"

  mkdir -p "$drivers"

  if ! tar -xf /drivers.txz -C "$drivers" --warning=no-timestamp; then
    error "Failed to extract drivers!" && return 1
  fi

  local target
  [[ "${arch,,}" == "x86" ]] && target="$dir/I386" || target="$dir/AMD64"

  cp "$drivers/viostor/$driver/$arch/viostor.sys" "$target"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/$driver/$arch/viostor.cat" "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/$driver/$arch/viostor.inf" "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/$driver/$arch/viostor.sys" "$dir/\$OEM\$/\$1/Drivers/viostor"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/$driver/$arch/netkvm.cat" "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/$driver/$arch/netkvm.inf" "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/$driver/$arch/netkvm.sys" "$dir/\$OEM\$/\$1/Drivers/NetKVM"

  if [ ! -f "$target/TXTSETUP.SIF" ]; then
    error "The file TXTSETUP.SIF could not be found!" && return 1
  fi

  sed -i '/^\[SCSI.Load\]/s/$/\nviostor=viostor.sys,4/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\nviostor.sys=1,,,,,,4_,4,1,,,1,4/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SCSI\]/s/$/\nviostor=\"Red Hat VirtIO SCSI Disk Device\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00000000=\"viostor\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00020000=\"viostor\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00021AF4=\"viostor\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00000000=\"viostor\"/' "$target/TXTSETUP.SIF"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/sata"

  cp -a "$drivers/sata/xp/$arch/." "$dir/\$OEM\$/\$1/Drivers/sata"
  cp -a "$drivers/sata/xp/$arch/." "$target"

  sed -i '/^\[SCSI.Load\]/s/$/\niaStor=iaStor.sys,4/' "$target/TXTSETUP.SIF"
  sed -i '/^\[FileFlags\]/s/$/\niaStor.sys = 16/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.cat = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.inf = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.sys = 1,,,,,,4_,4,1,,,1,4/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.sys = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaahci.cat = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaAHCI.inf = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SCSI\]/s/$/\niaStor=\"Intel\(R\) SATA RAID\/AHCI Controller\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_8086\&DEV_2922\&CC_0106=\"iaStor\"/' "$target/TXTSETUP.SIF"

  rm -rf "$drivers"

  local pid file setup
  setup=$(find "$target" -maxdepth 1 -type f -iname setupp.ini | head -n 1)
  pid=$(<"$setup")
  pid="${pid:(-4)}"
  pid="${pid:0:3}"

  if [[ "$pid" == "270" ]]; then
    warn "this version of $desc requires a volume license key (VLK), it will ask for one during installation."
  fi

  local oem=""
  local folder="/oem"

  [ ! -d "$folder" ] && folder="/OEM"
  [ ! -d "$folder" ] && folder="$STORAGE/oem"
  [ ! -d "$folder" ] && folder="$STORAGE/OEM"

  if [ -d "$folder" ]; then

    file=$(find "$folder" -maxdepth 1 -type f -iname install.bat | head -n 1)

    if [ -f "$file" ]; then
      unix2dos -q "$file"
      oem="\"Script\"=\"cmd /C start \\\"Install\\\" \\\"cmd /C C:\\\\OEM\\\\install.bat\\\"\""
    fi
  fi

  [ -z "$YRES" ] && YRES="720"
  [ -z "$XRES" ] && XRES="1280"

  XHEX=$(printf '%x\n' "$XRES")
  YHEX=$(printf '%x\n' "$YRES")

  local username="Docker"
  local password="*"

  [ -n "$PASSWORD" ] && password="$PASSWORD"
  [ -n "$USERNAME" ] && username=$(echo "$USERNAME" | sed 's/[^[:alnum:]@!._-]//g')

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
          echo "    ProductKey=$key"
          echo ""
          echo "[Identification]"
          echo "    JoinWorkgroup = WORKGROUP"
          echo ""
          echo "[Display]"
          echo "    BitsPerPel=32"
          echo "    XResolution=$XRES"
          echo "    YResolution=$YRES"
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
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa]"
          echo "\"LimitBlankPasswordUse\"=dword:00000000"
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Applets\Tour]"
          echo "\"RunCount\"=dword:00000000"
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]"
          echo "\"HideFileExt\"=dword:00000000"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]"
          echo "\"DefaultUserName\"=\"$username\""
          echo "\"DefaultDomainName\"=\"Dockur\""
          echo "\"AltDefaultUserName\"=\"$username\""
          echo "\"AltDefaultDomainName\"=\"Dockur\""
          echo "\"AutoAdminLogon\"=\"1\""
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

  if [[ "$driver" == "2k3" ]]; then
    {       echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\srvWiz]"
            echo "@=dword:00000000"
            echo ""
            echo "[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\ServerOOBE\SecurityOOBE]"
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
  } | unix2dos > "$dir/\$OEM\$/admin.vbs"

  {       echo "[COMMANDS]"
          echo "\"REGEDIT /s install.reg\""
          echo "\"Wscript admin.vbs\""
          echo ""
  } | unix2dos > "$dir/\$OEM\$/cmdlines.txt"

  [ ! -d "$folder" ] && return 0

  msg="Adding OEM folder to image..."
  info "$msg" && html "$msg"

  local dest="$dir/\$OEM\$/\$1/"
  mkdir -p "$dest"

  if ! cp -r "$folder" "$dest"; then
    error "Failed to copy OEM folder!" && return 1
  fi

  return 0
}

prepare2k3() {

  local iso="$1"
  local dir="$2"
  local desc="$3"
  local driver="2k3"
  local arch key

  [ -d "$dir/AMD64" ] && arch="amd64" || arch="x86"

  if [[ "${arch,,}" == "x86" ]]; then
    # Windows Server 2003 Standard x86 generic key (no activation, trial-only)
    # This is not a pirated key, it comes from the official MS documentation.
    key="QKDCQ-TP2JM-G4MDG-VR6F2-P9C48"
  else
    # Windows Server 2003 Standard x64 generic key (no activation, trial-only)
    # This is not a pirated key, it comes from the official MS documentation.
    key="P4WJG-WK3W7-3HM8W-RWHCK-8JTRY"
  fi

  ! prepareInstall "$iso" "$dir" "$desc" "$arch" "$key" "$driver" && return 1

  return 0
}

prepareXP() {

  local iso="$1"
  local dir="$2"
  local desc="$3"
  local driver="xp"
  local arch key

  [ -d "$dir/AMD64" ] && arch="amd64" || arch="x86"

  if [[ "${arch,,}" == "x86" ]]; then
    # Windows XP Professional x86 generic key (no activation, trial-only)
    # This is not a pirated key, it comes from the official MS documentation.
    key="DR8GV-C8V6J-BYXHG-7PYJR-DB66Y"
  else
    # Windows XP Professional x64 generic key (no activation, trial-only)
    # This is not a pirated key, it comes from the official MS documentation.
    key="B2RBK-7KPT9-4JP6X-QQFWM-PJD6G"
  fi

  ! prepareInstall "$iso" "$dir" "$desc" "$arch" "$key" "$driver" && return 1

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
  local find find2

  find=$(find "$dir" -maxdepth 1 -type d -iname win95 | head -n 1)
  [ -n "$find" ] && DETECTED="win95" && return 0

  find=$(find "$dir" -maxdepth 1 -type d -iname win98 | head -n 1)
  [ -n "$find" ] && DETECTED="win98" && return 0

  find=$(find "$dir" -maxdepth 1 -type d -iname win9x | head -n 1)
  [ -n "$find" ] && DETECTED="win9x" && return 0

  find=$(find "$dir" -maxdepth 1 -type f -iname cdrom_nt.5 | head -n 1)
  [ -n "$find" ] && DETECTED="win2k" && return 0

  find=$(find "$dir" -maxdepth 1 -type d -iname win51 | head -n 1)
  find2=$(find "$dir" -maxdepth 1 -type f -iname setupxp.htm | head -n 1)

  if [ -n "$find" ] || [ -n "$find2" ] || [ -f "$dir/WIN51AP" ] || [ -f "$dir/WIN51IC" ]; then
    [ -d "$dir/AMD64" ] && DETECTED="winxpx64" && return 0
    DETECTED="winxpx86" && return 0
  fi

  if [ -f "$dir/WIN51IA" ] || [ -f "$dir/WIN51IB" ] || [ -f "$dir/WIN51ID" ] || [ -f "$dir/WIN51IL" ] || [ -f "$dir/WIN51IS" ]; then
    DETECTED="win2003r2" && return 0
  fi

  if [ -f "$dir/WIN51AA" ] || [ -f "$dir/WIN51AD" ] || [ -f "$dir/WIN51AS" ] || [ -f "$dir/WIN51MA" ] || [ -f "$dir/WIN51MD" ]; then
    DETECTED="win2003r2" && return 0
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
    "win9"* | "win2k"* )
      MACHINE="pc-i440fx-2.4" ;;
    "winxp"* | "win2003"* | "winvistax86"* | "win7x86"* )
      MACHINE="pc-q35-2.10" ;;
  esac

  case "${id,,}" in
    "win9"* | "win2k"* | "winxp"* | "win2003"* )
      HV="N"
      BOOT_MODE="windows_legacy" ;;
    "winvista"* | "win7"* | "win2008"* )
      BOOT_MODE="windows_legacy" ;;
  esac

  case "${id,,}" in
    "win9"* )
      DISK_TYPE="auto"
      ETFS="[BOOT]/Boot-1.44M.img" ;;
    "win2k"* )
      DISK_TYPE="auto"
      ETFS="[BOOT]/Boot-NoEmul.img" ;;
    "winxp"* )
      DISK_TYPE="blk"
      if ! prepareXP "$iso" "$dir" "$desc"; then
        error "Failed to prepare $desc ISO!" && return 1
      fi ;;
    "win2003"* )
      DISK_TYPE="blk"
      if ! prepare2k3 "$iso" "$dir" "$desc"; then
        error "Failed to prepare $desc ISO!" && return 1
      fi ;;
    "win2025"* | "win11x64-iot"* | "win11x64-ltsc"* )
      # Temporary: Use IDE CD to workaround install bug
      MEDIA_TYPE="ide" ;;
  esac

  return 0
}

return 0
