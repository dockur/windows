#!/usr/bin/env bash
set -Eeuo pipefail

: "${MANUAL:=""}"
: "${VERSION:=""}"
: "${DETECTED:=""}"

getLink() {

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
    "win81x64")
      url="$host/windows/8.x/8.1/en_windows_8.1_with_update_x64_dvd_6051480.iso"
      ;;
    "win2022-eval")
      url="$host/windows/server/2022/en-us_windows_server_2022_updated_jan_2024_x64_dvd_2b7a0c9f.iso"
      ;;
    "win2019-eval")
      url="$host/windows/server/2019/en-us_windows_server_2019_updated_aug_2021_x64_dvd_a6431a28.iso"
      ;;
    "win2016-eval")
      url="$host/windows/server/2016/en_windows_server_2016_updated_feb_2018_x64_dvd_11636692.iso"
      ;;
    "win2012r2-eval")
      url="$host/windows/server/2012r2/en_windows_server_2012_r2_with_update_x64_dvd_6052708-004.iso"
      ;;
    "win2008r2")
      url="$host/windows/server/2008r2/en_windows_server_2008_r2_with_sp1_x64_dvd_617601-018.iso"
      ;;
    "win7x64")
      url="$host/windows/7/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
      ;;
    "winvistax64")
      url="$host/windows/vista/en_windows_vista_sp2_x64_dvd_342267.iso"
      ;;
    "winxpx86")
      url="$host/windows/xp/professional/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
    "core11")
      url="https://archive.org/download/tiny-11-core-x-64-beta-1/tiny11%20core%20x64%20beta%201.iso"
      ;;
    "tiny11")
      url="https://archive.org/download/tiny11-2311/tiny11%202311%20x64.iso"
      ;;
    "tiny10")
      url="https://archive.org/download/tiny-10-23-h2/tiny10%20x64%2023h2.iso"
      ;;
    *)
      return 0
      ;;
  esac

  echo "$url"
  return 0
}

parseVersion() {

  [ -z "$VERSION" ] && VERSION="win11"

  if [[ "${VERSION}" == \"*\" || "${VERSION}" == \'*\' ]]; then
    VERSION="${VERSION:1:-1}"
  fi

  case "${VERSION,,}" in
    "11" | "win11")
      VERSION="win11${PLATFORM}"
      ;;
    "10" | "win10")
      VERSION="win10${PLATFORM}"
      ;;
    "8" | "81" | "8.1" | "win8" | "win81")
      VERSION="win81x64"
      ;;
    "7" | "win7")
      VERSION="win7x64"
      ;;
    "vista" | "winvista")
      VERSION="winvistax64"
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
    "iot10" | "10iot" | "win10-iot" | "win10x64-iot")
      VERSION="win10x64-enterprise-iot-eval"
      ;;
    "ltsc10" | "10ltsc" | "win10-ltsc" | "win10x64-ltsc")
      VERSION="win10x64-enterprise-ltsc-eval"
      ;;
  esac

  if [[ "${VERSION,,}" == "win10x64-enterprise-iot-eval" ]]; then
    DETECTED="win10x64-iot"
  fi

  if [[ "${VERSION,,}" == "win10x64-enterprise-ltsc-eval" ]]; then
    DETECTED="win10x64-ltsc"
  fi

  if [[ "${VERSION,,}" == "win7x64" ]]; then
    DETECTED="$VERSION"
    VERSION=$(getLink "$VERSION")
  fi

  if [[ "${VERSION,,}" == "winvistax64" ]]; then
    DETECTED="$VERSION"
    VERSION=$(getLink "$VERSION")
  fi

  if [[ "${VERSION,,}" == "winxpx86" ]]; then
    DETECTED="$VERSION"
    VERSION=$(getLink "$VERSION")
  fi

  if [[ "${VERSION,,}" == "core11" ]]; then
    DETECTED="win11x64"
    VERSION=$(getLink "$VERSION")
  fi

  if [[ "${VERSION,,}" == "tiny11" ]]; then
    DETECTED="win11x64"
    VERSION=$(getLink "$VERSION")
  fi

  if [[ "${VERSION,,}" == "tiny10" ]]; then
    DETECTED="win10x64-ltsc"
    VERSION=$(getLink "$VERSION")
  fi

  return 0
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
  [[ "$id" == "win10x64-iot" ]] && desc="Windows 10 IoT"
  [[ "$id" == "win11x64-iot" ]] && desc="Windows 11 IoT"
  [[ "$id" == "win10x64-ltsc" ]] && desc="Windows 10 LTSC"
  [[ "$id" == "win11x64-ltsc" ]] && desc="Windows 11 LTSC"
  [[ "$id" == "win81x64-enterprise-eval" ]] && desc="Windows 8 Enterprise"
  [[ "$id" == "win10x64-enterprise-eval" ]] && desc="Windows 10 Enterprise"
  [[ "$id" == "win11x64-enterprise-eval" ]] && desc="Windows 11 Enterprise"

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

  [ -z "$desc" ] && desc="Windows"

  echo "$desc"
  return 0
}

getVersion() {

  local name="$1"
  local detected=""

  [[ "${name,,}" == *"windows 7"* ]] && detected="win7x64"
  [[ "${name,,}" == *"windows vista"* ]] && detected="winvistax64"

  [[ "${name,,}" == *"server 2008"* ]] && detected="win2008r2"
  [[ "${name,,}" == *"server 2025"* ]] && detected="win2025-eval"
  [[ "${name,,}" == *"server 2022"* ]] && detected="win2022-eval"
  [[ "${name,,}" == *"server 2019"* ]] && detected="win2019-eval"
  [[ "${name,,}" == *"server 2016"* ]] && detected="win2016-eval"
  [[ "${name,,}" == *"server 2012"* ]] && detected="win2012r2-eval"

  if [[ "${name,,}" == *"windows 8"* ]]; then
    if [[ "${name,,}" == *"enterprise evaluation"* ]]; then
      detected="win81x64-enterprise-eval"
    else
      detected="win81x64"
    fi
  fi

  if [[ "${name,,}" == *"windows 11"* ]]; then
    if [[ "${name,,}" == *"enterprise evaluation"* ]]; then
      detected="win11x64-enterprise-eval"
    else
      detected="win11x64"
    fi
  fi

  if [[ "${name,,}" == *"windows 10"* ]]; then
    if [[ "${name,,}" == *" iot "* ]]; then
      detected="win10x64-iot"
    else
      if [[ "${name,,}" == *"ltsc"* ]]; then
        detected="win10x64-ltsc"
      else
        if [[ "${name,,}" == *"enterprise evaluation"* ]]; then
          detected="win10x64-enterprise-eval"
        else
          detected="win10x64"
        fi
      fi
    fi
  fi

  echo "$detected"
  return 0
}

return 0
