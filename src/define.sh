#!/usr/bin/env bash
set -Eeuo pipefail

: "${MANUAL:=""}"
: "${VERSION:=""}"
: "${DETECTED:=""}"
: "${PLATFORM:="x64"}"

getLink() {

  # Fallbacks for users who cannot connect to Microsoft servers

  local id="$1"
  local url=""
  local host="https://dl.bobpony.com"

  case "${id,,}" in
    "win11${PLATFORM,,}")
      url="$host/windows/11/en-us_windows_11_23h2_${PLATFORM,,}.iso"
      ;;
    "win10${PLATFORM,,}")
      url="$host/windows/10/en-us_windows_10_22h2_${PLATFORM,,}.iso"
      ;;
    "win10${PLATFORM,,}-iot" | "win10${PLATFORM,,}-enterprise-iot-eval")
      url="$host/windows/10/en-us_windows_10_iot_enterprise_ltsc_2021_${PLATFORM,,}_dvd_257ad90f.iso"
      ;;
    "win10${PLATFORM,,}-ltsc" | "win10${PLATFORM,,}-enterprise-ltsc-eval")
      url="$host/windows/10/en-us_windows_10_enterprise_ltsc_2021_${PLATFORM,,}_dvd_d289cf96.iso"
      ;;
    "win81${PLATFORM,,}")
      url="$host/windows/8.x/8.1/en_windows_8.1_with_update_${PLATFORM,,}_dvd_6051480.iso"
      ;;
    "win2022-eval")
      url="$host/windows/server/2022/en-us_windows_server_2022_updated_jan_2024_${PLATFORM,,}_dvd_2b7a0c9f.iso"
      ;;
    "win2019-eval")
      url="$host/windows/server/2019/en-us_windows_server_2019_updated_aug_2021_${PLATFORM,,}_dvd_a6431a28.iso"
      ;;
    "win2016-eval")
      url="$host/windows/server/2016/en_windows_server_2016_updated_feb_2018_${PLATFORM,,}_dvd_11636692.iso"
      ;;
    "win2012r2-eval")
      url="$host/windows/server/2012r2/en_windows_server_2012_r2_with_update_${PLATFORM,,}_dvd_6052708-004.iso"
      ;;
    "win2008r2")
      url="$host/windows/server/2008r2/en_windows_server_2008_r2_with_sp1_${PLATFORM,,}_dvd_617601-018.iso"
      ;;
    "win7${PLATFORM,,}")
      url="$host/windows/7/en_windows_7_enterprise_with_sp1_${PLATFORM,,}_dvd_u_677651.iso"
      ;;
    "winvista${PLATFORM,,}")
      url="$host/windows/vista/en_windows_vista_sp2_${PLATFORM,,}_dvd_342267.iso"
      ;;
    "winxpx86")
      url="$host/windows/xp/professional/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
    "core11")
      url="https://archive.org/download/tiny-11-core-x-64-beta-1/tiny11%20core%20${PLATFORM,,}%20beta%201.iso"
      ;;
    "tiny11")
      url="https://archive.org/download/tiny11-2311/tiny11%202311%20${PLATFORM,,}.iso"
      ;;
    "tiny10")
      url="https://archive.org/download/tiny-10-23-h2/tiny10%20${PLATFORM,,}%2023h2.iso"
      ;;
  esac

  echo "$url"
  return 0
}

migrateFiles() {

  local base="$1"
  local version="$2"
  local file=""

  [ -f "$STORAGE/$base" ] && return 0

  [[ "${version,,}" == "tiny10" ]] && file="tiny10_${PLATFORM,,}_23h2.iso"
  [[ "${version,,}" == "tiny11" ]] && file="tiny11_2311_${PLATFORM,,}.iso"
  [[ "${version,,}" == "core11" ]] && file="tiny11_core_${PLATFORM,,}_beta_1.iso"
  [[ "${version,,}" == "winxpx86" ]] && file="en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
  [[ "${version,,}" == "winvista${PLATFORM,,}" ]] && file="en_windows_vista_sp2_${PLATFORM,,}_dvd_342267.iso"
  [[ "${version,,}" == "win7${PLATFORM,,}" ]] && file="en_windows_7_enterprise_with_sp1_${PLATFORM,,}_dvd_u_677651.iso"    
    
  [ -z "$file" ] && return 0
  [ ! -f "$STORAGE/$file" ] && return 0

  ! mv "$STORAGE/$file" "$STORAGE/$base" && return 1

  return 0
}

parseVersion() {

  [ -z "$VERSION" ] && VERSION="win11"

  if [[ "${VERSION}" == \"*\" || "${VERSION}" == \'*\' ]]; then
    VERSION="${VERSION:1:-1}"
  fi

  case "${VERSION,,}" in
    "11" | "win11")
      VERSION="win11${PLATFORM,,}"
      ;;
    "11e" | "win11e")
      VERSION="win11${PLATFORM,,}-enterprise-eval"
      ;;
    "10" | "win10")
      VERSION="win10${PLATFORM,,}"
      ;;
    "10e" | "win10e")
      VERSION="win10${PLATFORM,,}-enterprise-eval"
      ;;
    "8" | "81" | "8.1" | "win8" | "win81")
      VERSION="win81${PLATFORM,,}"
      ;;
    "8e" | "81e" | "8.1e" | "win8e" | "win81e")
      VERSION="win81${PLATFORM,,}-enterprise-eval"
      ;;
    "7" | "7e" | "win7" | "win7e")
      VERSION="win7${PLATFORM,,}"
      ;;
    "vista" | "winvista")
      VERSION="winvista${PLATFORM,,}"
      ;;
    "xp" | "winxp")
      VERSION="winxpx86"
      ;;
    "22" | "2022" | "win22" | "win2022")
      VERSION="win2022-eval"
      ;;
    "19" | "2019" | "win19" | "win2019")
      VERSION="win2019-eval"
      ;;
    "16" | "2016" | "win16" | "win2016")
      VERSION="win2016-eval"
      ;;
    "2012" | "win2012")
      VERSION="win2012r2-eval"
      ;;
    "2008" | "win2008")
      VERSION="win2008r2"
      ;;
    "core11" | "tiny11")
      DETECTED="win11${PLATFORM,,}"
      ;;
   "tiny10")
      DETECTED="win10${PLATFORM,,}-ltsc"
      ;;
    "iot10" | "10iot" | "win10-iot" | "win10${PLATFORM,,}-iot" | "win10${PLATFORM,,}-enterprise-iot-eval")
      DETECTED="win10${PLATFORM,,}-iot"
      VERSION="win10${PLATFORM,,}-enterprise-iot-eval"
      ;;
    "ltsc10" | "10ltsc" | "win10-ltsc" | "win10${PLATFORM,,}-ltsc" | "win10${PLATFORM,,}-enterprise-ltsc-eval")
      DETECTED="win10${PLATFORM,,}-ltsc"
      VERSION="win10${PLATFORM,,}-enterprise-ltsc-eval"
      ;;
  esac

  return 0
}

isESD() {

  local id="$1"

  case "${id,,}" in
    "win11${PLATFORM,,}")
      return 0
      ;;
    "win10${PLATFORM,,}")
      return 0
      ;;
  esac

  return 1
}

isMido() {

  local id="$1"

  case "${id,,}" in
    "win11${PLATFORM,,}" | "win11${PLATFORM,,}-enterprise-eval")
      return 0
      ;;
    "win10${PLATFORM,,}" | "win10${PLATFORM,,}-enterprise-eval" | "win10${PLATFORM,,}-enterprise-ltsc-eval")
      return 0
      ;;
    "win81${PLATFORM,,}" | "win81${PLATFORM,,}-enterprise-eval")
      return 0
      ;;
    "win2022-eval")
      return 0
      ;;
    "win2019-eval")
      return 0
      ;;
    "win2016-eval")
      return 0
      ;;
    "win2012r2-eval")
      return 0
      ;;
    "win2008r2")
      return 0
      ;;
  esac

  return 1
}

printVersion() {

  local id="$1"
  local desc="$2"

  [[ "$id" == "win7"* ]] && desc="Windows 7"
  [[ "$id" == "win8"* ]] && desc="Windows 8"
  [[ "$id" == "win10"* ]] && desc="Windows 10"
  [[ "$id" == "win11"* ]] && desc="Windows 11"
  [[ "$id" == "winxp"* ]] && desc="Windows XP"
  [[ "$id" == "winvista"* ]] && desc="Windows Vista"
  [[ "$id" == "win2025"* ]] && desc="Windows Server 2025"
  [[ "$id" == "win2022"* ]] && desc="Windows Server 2022"
  [[ "$id" == "win2019"* ]] && desc="Windows Server 2019"
  [[ "$id" == "win2016"* ]] && desc="Windows Server 2016"
  [[ "$id" == "win2012"* ]] && desc="Windows Server 2012"
  [[ "$id" == "win2008"* ]] && desc="Windows Server 2008"

  [[ "$id" == "win10${PLATFORM,,}-iot" ]] && desc="Windows 10 IoT"
  [[ "$id" == "win11${PLATFORM,,}-iot" ]] && desc="Windows 11 IoT"
  [[ "$id" == "win10${PLATFORM,,}-ltsc" ]] && desc="Windows 10 LTSC"
  [[ "$id" == "win11${PLATFORM,,}-ltsc" ]] && desc="Windows 11 LTSC"
  [[ "$id" == "win10${PLATFORM,,}-enterprise-iot-eval" ]] && desc="Windows 10 IoT"
  [[ "$id" == "win11${PLATFORM,,}-enterprise-iot-eval" ]] && desc="Windows 11 IoT"
  [[ "$id" == "win10${PLATFORM,,}-enterprise-ltsc-eval" ]] && desc="Windows 10 LTSC"
  [[ "$id" == "win11${PLATFORM,,}-enterprise-ltsc-eval" ]] && desc="Windows 11 LTSC"
  [[ "$id" == "win81${PLATFORM,,}-enterprise-eval" ]] && desc="Windows 8 Enterprise"
  [[ "$id" == "win10${PLATFORM,,}-enterprise-eval" ]] && desc="Windows 10 Enterprise"
  [[ "$id" == "win11${PLATFORM,,}-enterprise-eval" ]] && desc="Windows 11 Enterprise"

  [ -z "$desc" ] && desc="Windows"

  echo "$desc"
  return 0
}

getName() {

  local file="$1"
  local desc="$2"

  [[ "${file,,}" == "win11"* ]] && desc="Windows 11"
  [[ "${file,,}" == "win10"* ]] && desc="Windows 10"
  [[ "${file,,}" == "win8"* ]] && desc="Windows 8"
  [[ "${file,,}" == "win7"* ]] && desc="Windows 7"
  [[ "${file,,}" == "winxp"* ]] && desc="Windows XP"
  [[ "${file,,}" == "winvista"* ]] && desc="Windows Vista"
  [[ "${file,,}" == "tiny10"* ]] && desc="Tiny 10"
  [[ "${file,,}" == "tiny11"* ]] && desc="Tiny 11"
  [[ "${file,,}" == "tiny11_core"* ]] && desc="Tiny 11 Core"
  [[ "${file,,}" == *"windows11"* ]] && desc="Windows 11"
  [[ "${file,,}" == *"windows10"* ]] && desc="Windows 10"
  [[ "${file,,}" == *"windows8"* ]] && desc="Windows 8"
  [[ "${file,,}" == *"windows7"* ]] && desc="Windows 7"
  [[ "${file,,}" == *"windowsxp"* ]] && desc="Windows XP"
  [[ "${file,,}" == *"windowsvista"* ]] && desc="Windows Vista"
  [[ "${file,,}" == *"windows_11"* ]] && desc="Windows 11"
  [[ "${file,,}" == *"windows_10"* ]] && desc="Windows 10"
  [[ "${file,,}" == *"windows_8"* ]] && desc="Windows 8"
  [[ "${file,,}" == *"windows_7"* ]] && desc="Windows 7"
  [[ "${file,,}" == *"windows_xp"* ]] && desc="Windows XP"
  [[ "${file,,}" == *"windows_vista"* ]] && desc="Windows Vista"
  [[ "${file,,}" == *"server2008"* ]] && desc="Windows Server 2008"
  [[ "${file,,}" == *"server2012"* ]] && desc="Windows Server 2012"
  [[ "${file,,}" == *"server2016"* ]] && desc="Windows Server 2016"
  [[ "${file,,}" == *"server2019"* ]] && desc="Windows Server 2019"
  [[ "${file,,}" == *"server2022"* ]] && desc="Windows Server 2022"
  [[ "${file,,}" == *"server2025"* ]] && desc="Windows Server 2025"
  [[ "${file,,}" == *"server_2008"* ]] && desc="Windows Server 2008"
  [[ "${file,,}" == *"server_2012"* ]] && desc="Windows Server 2012"
  [[ "${file,,}" == *"server_2016"* ]] && desc="Windows Server 2016"
  [[ "${file,,}" == *"server_2019"* ]] && desc="Windows Server 2019"
  [[ "${file,,}" == *"server_2022"* ]] && desc="Windows Server 2022"
  [[ "${file,,}" == *"server_2025"* ]] && desc="Windows Server 2025"

  if [ -z "$desc" ]; then
    desc="Windows"
  else
    if [[ "$desc" == "Windows 1"* ]] && [[ "${file,,}" == *"_iot_"* ]]; then
      desc="$desc IoT"
    else
      if [[ "$desc" == "Windows 1"* ]] && [[ "${file,,}" == *"_ltsc_"* ]]; then
        desc="$desc LTSC"
      fi
    fi
  fi

  echo "$desc"
  return 0
}

getVersion() {

  local name="$1"
  local detected=""

  [[ "${name,,}" == *"windows 7"* ]] && detected="win7${PLATFORM,,}"
  [[ "${name,,}" == *"windows vista"* ]] && detected="winvista${PLATFORM,,}"

  [[ "${name,,}" == *"server 2008"* ]] && detected="win2008r2"
  [[ "${name,,}" == *"server 2025"* ]] && detected="win2025-eval"
  [[ "${name,,}" == *"server 2022"* ]] && detected="win2022-eval"
  [[ "${name,,}" == *"server 2019"* ]] && detected="win2019-eval"
  [[ "${name,,}" == *"server 2016"* ]] && detected="win2016-eval"
  [[ "${name,,}" == *"server 2012"* ]] && detected="win2012r2-eval"

  if [[ "${name,,}" == *"windows 8"* ]]; then
    if [[ "${name,,}" == *"enterprise evaluation"* ]]; then
      detected="win81${PLATFORM,,}-enterprise-eval"
    else
      detected="win81${PLATFORM,,}"
    fi
  fi

  if [[ "${name,,}" == *"windows 11"* ]]; then
    if [[ "${name,,}" == *"enterprise evaluation"* ]]; then
      detected="win11${PLATFORM,,}-enterprise-eval"
    else
      detected="win11${PLATFORM,,}"
    fi
  fi

  if [[ "${name,,}" == *"windows 10"* ]]; then
    if [[ "${name,,}" == *" iot "* ]]; then
      detected="win10${PLATFORM,,}-iot"
    else
      if [[ "${name,,}" == *"ltsc"* ]]; then
        detected="win10${PLATFORM,,}-ltsc"
      else
        if [[ "${name,,}" == *"enterprise evaluation"* ]]; then
          detected="win10${PLATFORM,,}-enterprise-eval"
        else
          detected="win10${PLATFORM,,}"
        fi
      fi
    fi
  fi

  echo "$detected"
  return 0
}

return 0
