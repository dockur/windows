#!/usr/bin/env bash
set -Eeuo pipefail

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

MIRRORS=5
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

  [ -n "$edition" ] && result="$result $edition"

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
      size=4821989376
      sum="e8f1431c4e6289b3997c20eadbb2576670300bb6e1cf8948b5d7af179010a962"
      url="26100.1.240331-1435.ge_release_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win11x64-ltsc" | "win11x64-enterprise-ltsc-eval" )
      [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0
      size=4821989376
      sum="e8f1431c4e6289b3997c20eadbb2576670300bb6e1cf8948b5d7af179010a962"
      url="26100.1.240331-1435.ge_release_CLIENT_ENTERPRISES_OEM_x64FRE_en-us.iso"
      ;;
    "win10x64" | "win10x64-enterprise" | "win10x64-enterprise-eval" )
      size=5675616256
      sum="99c13b3afb1375661fc79496025cabe3f9ef5a555fc8ea767a48937b0f4bcace"
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

  local id="$1"
  local lang="$2"
  local ret="$3"
  local url=""
  local sum=""
  local size=""
  local host="https://file.cnxiaobai.com/Windows"

  [[ "${lang,,}" != "en" ]] && [[ "${lang,,}" != "en-us" ]] && return 0

  case "${id,,}" in
    "core11" )
      size=2159738880
      sum="78f0f44444ff95b97125b43e560a72e0d6ce0a665cf9f5573bf268191e5510c1"
      url="%E7%B3%BB%E7%BB%9F%E5%AE%89%E8%A3%85%E5%8C%85/Tiny%2010_11/tiny11%20core%20x64%20beta%201.iso"
      ;;
    "tiny11" )
      size=3788177408
      sum="a028800a91addc35d8ae22dce7459b67330f7d69d2f11c70f53c0fdffa5b4280"
      url="%E7%B3%BB%E7%BB%9F%E5%AE%89%E8%A3%85%E5%8C%85/Tiny%2010_11/tiny11%202311%20x64.iso"
      ;;
    "tiny10" )
      size=3839819776
      sum="a11116c0645d892d6a5a7c585ecc1fa13aa66f8c7cc6b03bf1f27bd16860cc35"
      url="%E7%B3%BB%E7%BB%9F%E5%AE%89%E8%A3%85%E5%8C%85/Tiny%2010_11/tiny10%2023H2%20x64.iso"
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

  # Fallbacks for users who cannot connect to the Microsoft servers

  local id="$1"
  local lang="$2"
  local ret="$3"
  local url=""
  local sum=""
  local size=""
  local host="https://drive.massgrave.dev"

  culture=$(getLanguage "$lang" "culture")

  case "${id,,}" in
    "win11x64" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar-sa_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "bg" | "bg-"* ) url="bg-bg_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "cs" | "cs-"* ) url="cs-cz_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "da" | "da-"* ) url="da-dk_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "de" | "de-"* ) url="de-de_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "el" | "el-"* ) url="el-gr_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "gb" | "en-gb" ) url="en-gb_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "en" | "en-"* )
          size=7004780544
          sum="a6c21313210182e0315054789a2b658b77394d5544b69b5341075492f89f51e5"
          url="en-us_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "mx" | "es-mx" ) url="es-mx_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "es" | "es-"* ) url="es-es_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "et" | "et-"* ) url="et-ee_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "fi" | "fi-"* ) url="fi-fi_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "ca" | "fr-ca" ) url="fr-ca_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "he" | "he-"* ) url="he-il_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "hr" | "hr-"* ) url="hr-hr_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "it" | "it-"* ) url="it-it_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "lt" | "lt-"* ) url="lt-lt_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "lv" | "lv-"* ) url="lv-lv_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "nb" | "nb-"* ) url="nb-no_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "br" | "pt-br" ) url="pt-br_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "ro" | "ro-"* ) url="ro-ro_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "sk" | "sk-"* ) url="sk-sk_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "sl" | "sl-"* ) url="sl-si_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "sr" | "sr-"* ) url="sr-latn-rs_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "sv" | "sv-"* ) url="sv-se_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "th" | "th-"* ) url="th-th_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "uk" | "uk-"* ) url="uk-ua_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_windows_11_consumer_editions_version_23h2_updated_april_2024_x64_dvd_d986680b.iso" ;;
      esac
      ;;
    "win11x64-enterprise" | "win11x64-enterprise-eval" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar-sa_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_7c2ed97c.iso" ;;
        "bg" | "bg-"* ) url="bg-bg_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_b04d691c.iso" ;;
        "cs" | "cs-"* ) url="cs-cz_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_a03b763a.iso" ;;
        "da" | "da-"* ) url="da-dk_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_b7b16bf7.iso" ;;
        "de" | "de-"* ) url="de-de_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_b8a95188.iso" ;;
        "el" | "el-"* ) url="el-gr_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_c80dd818.iso" ;;
        "gb" | "en-gb" ) url="en-gb_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_0716ab50.iso" ;;
        "en" | "en-"* )
          size=6879023104
          sum="3d4d388d6ffa371956304fa7401347b4535fd10e3137978a8f7750b790a43521"
          url="en-us_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_349cd577.iso" ;;
        "mx" | "es-mx" ) url="es-mx_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_79352ef9.iso" ;;
        "es" | "es-"* ) url="es-es_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_252a527a.iso" ;;
        "et" | "et-"* ) url="et-ee_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_3952b855.iso" ;;
        "fi" | "fi-"* ) url="fi-fi_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_a90c9768.iso" ;;
        "ca" | "fr-ca" ) url="fr-ca_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_f4e143d8.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_9f143fd4.iso" ;;
        "he" | "he-"* ) url="he-il_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_767966f8.iso" ;;
        "hr" | "hr-"* ) url="hr-hr_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_dcc7bb81.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_305a2313.iso" ;;
        "it" | "it-"* ) url="it-it_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_f0af2584.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_1b3949b3.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_b34a9c97.iso" ;;
        "lt" | "lt-"* ) url="lt-lt_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_dbab7eb4.iso" ;;
        "lv" | "lv-"* ) url="lv-lv_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_55d75975.iso" ;;
        "nb" | "nb-"* ) url="nb-no_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_7baab32f.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_d223773d.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_55984e5b.iso" ;;
        "br" | "pt-br" ) url="pt-br_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_151a4636.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_37cc9525.iso" ;;
        "ro" | "ro-"* ) url="ro-ro_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_9a2982f1.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_a81ee700.iso" ;;
        "sk" | "sk-"* ) url="sk-sk_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_e71e6779.iso" ;;
        "sl" | "sl-"* ) url="sl-si_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_d48dc41a.iso" ;;
        "sr" | "sr-"* ) url="sr-latn-rs_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_86a8483f.iso" ;;
        "sv" | "sv-"* ) url="sv-se_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_96fc11d1.iso" ;;
        "th" | "th-"* ) url="th-th_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_282dc814.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_26e6c580.iso" ;;
        "uk" | "uk-"* ) url="uk-ua_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_b2d33085.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_6aa057e6.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_windows_11_business_editions_version_23h2_updated_april_2024_x64_dvd_3db5a62b.iso" ;;
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
        "ar" | "ar-"* ) url="ar-sa_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "bg" | "bg-"* ) url="bg-bg_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "cs" | "cs-"* ) url="cs-cz_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "da" | "da-"* ) url="da-dk_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "de" | "de-"* ) url="de-de_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "el" | "el-"* ) url="el-gr_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "gb" | "en-gb" ) url="en-gb_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "en" | "en-"* )
          size=6605459456
          sum="b072627c9b8d9f62af280faf2a8b634376f91dc73ea1881c81943c151983aa4a"
          url="en-us_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "mx" | "es-mx" ) url="es-mx_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "es" | "es-"* ) url="es-es_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "et" | "et-"* ) url="et-ee_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "fi" | "fi-"* ) url="fi-fi_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "ca" | "fr-ca" ) url="fr-ca_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "he" | "he-"* ) url="he-il_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "hr" | "hr-"* ) url="hr-hr_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "it" | "it-"* ) url="it-it_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "lt" | "lt-"* ) url="lt-lt_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "lv" | "lv-"* ) url="lv-lv_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "nb" | "nb-"* ) url="nb-no_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "br" | "pt-br" ) url="pt-br_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "ro" | "ro-"* ) url="ro-ro_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "sk" | "sk-"* ) url="sk-sk_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "sl" | "sl-"* ) url="sl-si_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "sr" | "sr-"* ) url="sr-latn-rs_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "sv" | "sv-"* ) url="sv-se_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "th" | "th-"* ) url="th-th_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "uk" | "uk-"* ) url="uk-ua_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_windows_10_consumer_editions_version_22h2_updated_april_2024_x64_dvd_9a92dc89.iso" ;;
      esac
      ;;
    "win10x64-enterprise" | "win10x64-enterprise-eval" )
      case "${culture,,}" in
        "ar" | "ar-"* ) url="ar-sa_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_4453f818.iso" ;;
        "bg" | "bg-"* ) url="bg-bg_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_1777c1d1.iso" ;;
        "cs" | "cs-"* ) url="cs-cz_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_c57cc386.iso" ;;
        "da" | "da-"* ) url="da-dk_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_45f3ae0c.iso" ;;
        "de" | "de-"* ) url="de-de_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_8042d5ca.iso" ;;
        "el" | "el-"* ) url="el-gr_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_60cc062b.iso" ;;
        "gb" | "en-gb" ) url="en-gb_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_da84fbf3.iso" ;;
        "en" | "en-"* )
          size=6428377088
          sum="05fe9de04c2626bd00fbe69ad19129b2dbb75a93a2fe030ebfb2256d937ceab8"
          url="en-us_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_c00090a7.iso" ;;
        "mx" | "es-mx" ) url="es-mx_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_87806b10.iso" ;;
        "es" | "es-"* ) url="es-es_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_a464088d.iso" ;;
        "et" | "et-"* ) url="et-ee_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_bd09a0ce.iso" ;;
        "fi" | "fi-"* ) url="fi-fi_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_4d76cfbd.iso" ;;
        "ca" | "fr-ca" ) url="fr-ca_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_40643c76.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_8ca89ac8.iso" ;;
        "he" | "he-"* ) url="he-il_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_804bcaf0.iso" ;;
        "hr" | "hr-"* ) url="hr-hr_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_4c4f5b26.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_43302dfb.iso" ;;
        "it" | "it-"* ) url="it-it_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_73996e82.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_0aaece93.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_37654eaa.iso" ;;
        "lt" | "lt-"* ) url="lt-lt_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_83c6a9b7.iso" ;;
        "lv" | "lv-"* ) url="lv-lv_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_2b80cd3c.iso" ;;
        "nb" | "nb-"* ) url="nb-no_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_2a274012.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_5eae56c5.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_6497a429.iso" ;;
        "br" | "pt-br" ) url="pt-br_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_de63f2f7.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_a95933fb.iso" ;;
        "ro" | "ro-"* ) url="ro-ro_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_d008e588.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_12b02d35.iso" ;;
        "sk" | "sk-"* ) url="sk-sk_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_7caf6b4f.iso" ;;
        "sl" | "sl-"* ) url="sl-si_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_e1e76668.iso" ;;
        "sr" | "sr-"* ) url="sr-latn-rs_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_b72c40ce.iso" ;;
        "sv" | "sv-"* ) url="sv-se_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_4800fcd8.iso" ;;
        "th" | "th-"* ) url="th-th_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_5077fb45.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_7703a6c4.iso" ;;
        "uk" | "uk-"* ) url="uk-ua_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_37caf402.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_35f0e5a7.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_windows_10_business_editions_version_22h2_updated_april_2024_x64_dvd_a2873093.iso" ;;
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
        "cs" | "cs-"* ) url="cs-cz_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "de" | "de-"* ) url="de-de_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "en" | "en-"* )
          size=5515755520
          sum="7f41d603224e8a0bf34ba957d3abf0a02437ab75000dd758b5ce3f050963e91f"
          url="en-us_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "es" | "es-"* ) url="es-es_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "fr" | "fr-"* ) url="fr-fr_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "hu" | "hu-"* ) url="hu-hu_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "it" | "it-"* ) url="it-it_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "ja" | "ja-"* ) url="ja-jp_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "ko" | "ko-"* ) url="ko-kr_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "nl" | "nl-"* ) url="nl-nl_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "pl" | "pl-"* ) url="pl-pl_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "br" | "pt-br" ) url="pt-br_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "pt" | "pt-"* ) url="pt-pt_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "ru" | "ru-"* ) url="ru-ru_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "sv" | "sv-"* ) url="sv-se_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "tr" | "tr-"* ) url="tr-tr_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "zh-hk" | "zh-tw" ) url="zh-tw_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
        "zh" | "zh-"* ) url="zh-cn_windows_server_2022_updated_april_2024_x64_dvd_164349f3.iso" ;;
      esac
      ;;
    "win2019" | "win2019-eval" )
      case "${culture,,}" in
        "cs" | "cs-"* ) url="cs_windows_server_2019_x64_dvd_65383121.iso" ;;
        "de" | "de-"* ) url="de_windows_server_2019_x64_dvd_17559a5b.iso" ;;
        "en" | "en-"* )
          size=4843268096
          sum="4c5dd63efee50117986a2e38d4b3a3fbaf3c1c15e2e7ea1d23ef9d8af148dd2d"
          url="en_windows_server_2019_x64_dvd_4cb967d8.iso" ;;
        "es" | "es-"* ) url="es_windows_server_2019_x64_dvd_dd6b7747.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_server_2019_x64_dvd_d936fc7a.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_server_2019_x64_dvd_c8f2c460.iso" ;;
        "it" | "it-"* ) url="it_windows_server_2019_x64_dvd_03c34df6.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_server_2019_x64_dvd_260a1d93.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_server_2019_x64_dvd_8778047d.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_server_2019_x64_dvd_82f9a152.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_server_2019_x64_dvd_2cd7adba.iso" ;;
        "br" | "pt-br" ) url="pt_windows_server_2019_x64_dvd_e078dea6.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_server_2019_x64_dvd_e8fadd22.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_server_2019_x64_dvd_3411c84a.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_server_2019_x64_dvd_ce3d1a8d.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_server_2019_x64_dvd_475b2d44.iso" ;;
        "zh-hk" | "zh-tw" ) url="ct_windows_server_2019_x64_dvd_b776f44b.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_server_2019_x64_dvd_4de40f33.iso" ;;
      esac
      ;;
    "win2016" | "win2016-eval" )
      case "${culture,,}" in
        "cs" | "cs-"* ) url="cs_windows_server_2016_x64_dvd_9327749.iso" ;;
        "de" | "de-"* ) url="de_windows_server_2016_x64_dvd_9327757.iso" ;;
        "en" | "en-"* )
          size=5653628928
          sum="4caeb24b661fcede81cd90661aec31aa69753bf49a5ac247253dd021bc1b5cbb"
          url="en_windows_server_2016_x64_dvd_9327751.iso" ;;
        "es" | "es-"* ) url="es_windows_server_2016_x64_dvd_9327767.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_server_2016_x64_dvd_9327754.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_server_2016_x64_dvd_9327759.iso" ;;
        "it" | "it-"* ) url="it_windows_server_2016_x64_dvd_9327760.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_server_2016_x64_dvd_9327761.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_server_2016_x64_dvd_9327762.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_server_2016_x64_dvd_9327750.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_server_2016_x64_dvd_9327763.iso" ;;
        "br" | "pt-br" ) url="pt_windows_server_2016_x64_dvd_9327764.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_server_2016_x64_dvd_9327765.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_server_2016_x64_dvd_9327766.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_server_2016_x64_dvd_9327768.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_server_2016_x64_dvd_9327769.iso" ;;
        "zh-hk" | "zh-tw" ) url="ct_windows_server_2016_x64_dvd_9327748.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_server_2016_x64_dvd_9327743.iso" ;;
      esac
      ;;
    "win2012r2" | "win2012r2-eval" )
      case "${culture,,}" in
        "cs" | "cs-"* ) url="cs_windows_server_2012_r2_with_update_x64_dvd_6052695.iso" ;;
        "de" | "de-"* ) url="de_windows_server_2012_r2_with_update_x64_dvd_6052720.iso" ;;
        "en" | "en-"* )
          size=5397889024
          sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
          url="en_windows_server_2012_r2_with_update_x64_dvd_6052708.iso" ;;
        "es" | "es-"* ) url="es_windows_server_2012_r2_with_update_x64_dvd_6052769.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_server_2012_r2_with_update_x64_dvd_6052713.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_server_2012_r2_with_update_x64_dvd_6052727.iso" ;;
        "it" | "it-"* ) url="it_windows_server_2012_r2_with_update_x64_dvd_6052734.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_server_2012_r2_with_update_x64_dvd_6052738.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_server_2012_r2_with_update_x64_dvd_6052743.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_server_2012_r2_with_update_x64_dvd_6052701.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_server_2012_r2_with_update_x64_dvd_6052749.iso" ;;
        "br" | "pt-br" ) url="pt_windows_server_2012_r2_with_update_x64_dvd_6052754.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_server_2012_r2_with_update_x64_dvd_6052758.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_server_2012_r2_with_update_x64_dvd_6052763.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_server_2012_r2_with_update_x64_dvd_6052773.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_server_2012_r2_with_update_x64_dvd_6052778.iso" ;;
        "zh-hk" ) url="hk_windows_server_2012_r2_with_update_x64_dvd_6052731.iso" ;;
        "zh-tw" ) url="tw_windows_server_2012_r2_with_update_x64_dvd_6052736.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_server_2012_r2_with_update_x64_dvd_6052725.iso" ;;
      esac
      ;;
    "win2008r2" | "win2008r2-eval" )
      case "${culture,,}" in
        "cs" | "cs-"* ) url="cs_windows_server_2008_r2_with_sp1_x64_dvd_617602.iso" ;;
        "de" | "de-"* ) url="de_windows_server_2008_r2_with_sp1_x64_dvd_617380.iso" ;;
        "en" | "en-"* )
          size=3166584832
          sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
          url="en_windows_server_2008_r2_with_sp1_x64_dvd_617601.iso" ;;
        "es" | "es-"* ) url="es_windows_server_2008_r2_with_sp1_x64_dvd_617398.iso" ;;
        "fr" | "fr-"* ) url="fr_windows_server_2008_r2_with_sp1_x64_dvd_617591.iso" ;;
        "hu" | "hu-"* ) url="hu_windows_server_2008_r2_with_sp1_x64_dvd_617383.iso" ;;
        "it" | "it-"* ) url="it_windows_server_2008_r2_with_sp1_x64_dvd_617391.iso" ;;
        "ja" | "ja-"* ) url="ja_windows_server_2008_r2_with_sp1_x64_dvd_617387.iso" ;;
        "ko" | "ko-"* ) url="ko_windows_server_2008_r2_with_sp1_x64_dvd_617385.iso" ;;
        "nl" | "nl-"* ) url="nl_windows_server_2008_r2_with_sp1_x64_dvd_617597.iso" ;;
        "pl" | "pl-"* ) url="pl_windows_server_2008_r2_with_sp1_x64_dvd_617388.iso" ;;
        "br" | "pt-br" ) url="pt_windows_server_2008_r2_with_sp1_x64_dvd_617599.iso" ;;
        "pt" | "pt-"* ) url="pp_windows_server_2008_r2_with_sp1_x64_dvd_617382.iso" ;;
        "ru" | "ru-"* ) url="ru_windows_server_2008_r2_with_sp1_x64_dvd_617389.iso" ;;
        "sv" | "sv-"* ) url="sv_windows_server_2008_r2_with_sp1_x64_dvd_617393.iso" ;;
        "tr" | "tr-"* ) url="tr_windows_server_2008_r2_with_sp1_x64_dvd_617390.iso" ;;
        "zh-hk" ) url="hk_windows_server_2008_r2_with_sp1_x64_dvd_617586.iso" ;;
        "zh-tw" ) url="tw_windows_server_2008_r2_with_sp1_x64_dvd_617595.iso" ;;
        "zh" | "zh-"* ) url="cn_windows_server_2008_r2_with_sp1_x64_dvd_617598.iso" ;;
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

getLink5() {

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

skipVersion() {

  local version="$1"

  case "${version,,}" in
    "win2003"* | "win2k"* | "winxp"* | "win9"* )
      return 0
      ;;
  esac

  return 1
}

detectLegacy() {

  local dir="$1"
  local find find2 desc

  find=$(find "$dir" -maxdepth 1 -type d -iname win95 | head -n 1)

  if [ -n "$find" ]; then
    DETECTED="win95"
    desc=$(printEdition "$DETECTED" "Windows 95")
    info "Detected: $desc" && return 0
  fi

  find=$(find "$dir" -maxdepth 1 -type d -iname win98 | head -n 1)

  if [ -n "$find" ]; then
    DETECTED="win98"
    desc=$(printEdition "$DETECTED" "Windows 98")
    info "Detected: $desc" && return 0
  fi

  find=$(find "$dir" -maxdepth 1 -type d -iname win9x | head -n 1)

  if [ -n "$find" ]; then
    DETECTED="win9x"
    desc=$(printEdition "$DETECTED" "Windows ME")
    info "Detected: $desc" && return 0
  fi

  find=$(find "$dir" -maxdepth 1 -type d -iname win51 | head -n 1)
  find2=$(find "$dir" -maxdepth 1 -type f -iname setupxp.htm | head -n 1)

  if [ -n "$find" ] || [ -n "$find2" ] || [ -f "$dir/WIN51AP" ] || [ -f "$dir/WIN51IC" ]; then
    [ -d "$dir/AMD64" ] && DETECTED="winxpx64" || DETECTED="winxpx86"
    desc=$(printEdition "$DETECTED" "Windows XP")
    info "Detected: $desc" && return 0
  fi

  if [ -f "$dir/CDROM_NT.5" ]; then
    DETECTED="win2k"
    desc=$(printEdition "$DETECTED" "Windows 2000")
    info "Detected: $desc" && return 0
  fi

  if [ -f "$dir/WIN51AA" ] || [ -f "$dir/WIN51AD" ] || [ -f "$dir/WIN51AS" ] || [ -f "$dir/WIN51MA" ] || [ -f "$dir/WIN51MD" ]; then
    DETECTED="win2003r2"
    desc=$(printEdition "$DETECTED" "Windows Server 2003")
    info "Detected: $desc" && return 0
  fi

  if [ -f "$dir/WIN51IA" ] || [ -f "$dir/WIN51IB" ] || [ -f "$dir/WIN51ID" ] || [ -f "$dir/WIN51IL" ] || [ -f "$dir/WIN51IS" ]; then
    DETECTED="win2003r2"
    desc=$(printEdition "$DETECTED" "Windows Server 2003")
    info "Detected: $desc" && return 0
  fi

  return 1
}

prepareLegacy() {

  local iso="$1"
  local dir="$2"
  local file="$dir/boot.img"

  ETFS=$(basename "$file")
  [ -f "$file" ] && [ -s "$file" ] && return 0
  rm -f "$file"

  local len offset
  len=$(isoinfo -d -i "$iso" | grep "Nsect " | grep -o "[^ ]*$")
  offset=$(isoinfo -d -i "$iso" | grep "Bootoff " | grep -o "[^ ]*$")

  dd "if=$iso" "of=$file" bs=2048 "count=$len" "skip=$offset" status=none && return 0

  return 1
}

prepare9x() {

  local iso="$1"
  local dir="$2"
  local file="$dir/boot.img"

  ETFS=$(basename "$file")
  [ -f "$file" ] && [ -s "$file" ] && return 0
  rm -f "$file"

  local src="[BOOT]/Boot-1.44M.img"
  [ ! -f "$dir/$src" ] && error "Boot floppy not found!" && return 1

  cp "$dir/$src" "$file" && return 0

  return 1
}

prepare2k() {

  local dir="$2"
  ETFS="[BOOT]/Boot-NoEmul.img"

  return 0
}

prepare2k3() {

  local dir="$2"
  local arch="x86"
  local target="$dir/I386"
  local drivers="$TMP/drivers"

  ETFS="[BOOT]/Boot-NoEmul.img"

  if [ -d "$dir/AMD64" ]; then
    arch="amd64"
    target="$dir/AMD64"
  fi

  local msg="Adding drivers to image..."
  info "$msg" && html "$msg"

  mkdir -p "$drivers"

  if ! tar -xf /drivers.txz -C "$drivers" --warning=no-timestamp; then
    error "Failed to extract driver!" && return 1
  fi

  cp "$drivers/viostor/2k3/$arch/viostor.sys" "$target"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/2k3/$arch/viostor.cat" "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/2k3/$arch/viostor.inf" "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/2k3/$arch/viostor.sys" "$dir/\$OEM\$/\$1/Drivers/viostor"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/2k3/$arch/netkvm.cat" "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/2k3/$arch/netkvm.inf" "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/2k3/$arch/netkvm.sys" "$dir/\$OEM\$/\$1/Drivers/NetKVM"

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

  local key pid file setup
  setup=$(find "$target" -maxdepth 1 -type f -iname setupp.ini | head -n 1)
  pid=$(<"$setup")
  pid="${pid:(-4)}"
  pid="${pid:0:3}"

  if [[ "$pid" == "270" ]]; then
    warn "this version of Windows Server 2003 requires a volume license key (VLK), it will ask for one during installation."
  fi

  if [[ "${arch,,}" == "x86" ]]; then
    # Windows Server 2003 Standard x86 generic key (no activation, trial-only)
    # This is not a pirated key, it comes from the official MS documentation.
    key="QKDCQ-TP2JM-G4MDG-VR6F2-P9C48"
  else
    # Windows Server 2003 Standard x64 generic key (no activation, trial-only)
    # This is not a pirated key, it comes from the official MS documentation.
    key="P4WJG-WK3W7-3HM8W-RWHCK-8JTRY"
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
          echo "\"DefaultSettings.XResolution\"=dword:00000780"
          echo "\"DefaultSettings.YResolution\"=dword:00000438"
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce]"
          echo "\"ScreenSaver\"=\"reg add \\\"HKCU\\\\Control Panel\\\\Desktop\\\" /f /v \\\"SCRNSAVE.EXE\\\" /t REG_SZ /d \\\"off\\\"\""
          echo "\"ScreenSaverOff\"=\"reg add \\\"HKCU\\\\Control Panel\\\\Desktop\\\" /f /v \\\"ScreenSaveActive\\\" /t REG_SZ /d \\\"0\\\"\""
          echo "$oem"
  } | unix2dos > "$dir/\$OEM\$/install.reg"

  {       echo "Set WshShell = WScript.CreateObject(\"WScript.Shell\")"
          echo "Set WshNetwork = WScript.CreateObject(\"WScript.Network\")"
          echo "Set oMachine = GetObject(\"WinNT://\" & WshNetwork.ComputerName)"
          echo "Set oInfoUser = GetObject(\"WinNT://\" & WshNetwork.ComputerName & \"/Administrator,user\")"
          echo "Set oUser = oMachine.MoveHere(oInfoUser.ADsPath,\"$username\")"
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

prepareXP() {

  local dir="$2"
  local arch="x86"
  local target="$dir/I386"
  local drivers="$TMP/drivers"

  ETFS="[BOOT]/Boot-NoEmul.img"

  if [ -d "$dir/AMD64" ]; then
    arch="amd64"
    target="$dir/AMD64"
  fi

  local msg="Adding drivers to image..."
  info "$msg" && html "$msg"

  mkdir -p "$drivers"

  if ! tar -xf /drivers.txz -C "$drivers" --warning=no-timestamp; then
    error "Failed to extract driver!" && return 1
  fi

  cp "$drivers/viostor/xp/$arch/viostor.sys" "$target"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/xp/$arch/viostor.cat" "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/xp/$arch/viostor.inf" "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/xp/$arch/viostor.sys" "$dir/\$OEM\$/\$1/Drivers/viostor"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/xp/$arch/netkvm.cat" "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/xp/$arch/netkvm.inf" "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/xp/$arch/netkvm.sys" "$dir/\$OEM\$/\$1/Drivers/NetKVM"

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

  local key pid file setup
  setup=$(find "$target" -maxdepth 1 -type f -iname setupp.ini | head -n 1)
  pid=$(<"$setup")
  pid="${pid:(-4)}"
  pid="${pid:0:3}"

  if [[ "$pid" == "270" ]]; then
    warn "this version of Windows XP requires a volume license key (VLK), it will ask for one during installation."
  fi

  if [[ "${arch,,}" == "x86" ]]; then
    # Windows XP Professional x86 generic key (no activation, trial-only)
    # This is not a pirated key, it comes from the official MS documentation.
    key="DR8GV-C8V6J-BYXHG-7PYJR-DB66Y"
  else
    # Windows XP Professional x64 generic key (no activation, trial-only)
    # This is not a pirated key, it comes from the official MS documentation.
    key="B2RBK-7KPT9-4JP6X-QQFWM-PJD6G"
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
          echo "\"DefaultSettings.XResolution\"=dword:00000780"
          echo "\"DefaultSettings.YResolution\"=dword:00000438"
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce]"
          echo "\"ScreenSaver\"=\"reg add \\\"HKCU\\\\Control Panel\\\\Desktop\\\" /f /v \\\"SCRNSAVE.EXE\\\" /t REG_SZ /d \\\"off\\\"\""
          echo "\"ScreenSaverOff\"=\"reg add \\\"HKCU\\\\Control Panel\\\\Desktop\\\" /f /v \\\"ScreenSaveActive\\\" /t REG_SZ /d \\\"0\\\"\""
          echo "$oem"
  } | unix2dos > "$dir/\$OEM\$/install.reg"

  {       echo "Set WshShell = WScript.CreateObject(\"WScript.Shell\")"
          echo "Set WshNetwork = WScript.CreateObject(\"WScript.Network\")"
          echo "Set oMachine = GetObject(\"WinNT://\" & WshNetwork.ComputerName)"
          echo "Set oInfoUser = GetObject(\"WinNT://\" & WshNetwork.ComputerName & \"/Administrator,user\")"
          echo "Set oUser = oMachine.MoveHere(oInfoUser.ADsPath,\"$username\")"
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

return 0
