#!/usr/bin/env bash
set -Eeuo pipefail

: "${VERIFY:=""}"
: "${MANUAL:=""}"
: "${REMOVE:=""}"
: "${VERSION:=""}"
: "${DETECTED:=""}"

MIRRORS=5
PLATFORM="x64"

parseVersion() {

  VERSION="${VERSION/\//}"

  if [[ "${VERSION}" == \"*\" || "${VERSION}" == \'*\' ]]; then
    VERSION="${VERSION:1:-1}"
  fi

  [ -z "$VERSION" ] && VERSION="win11"

  case "${VERSION,,}" in
    "11" | "11p" | "win11" | "win11p" | "windows11" | "windows 11" )
      VERSION="win11${PLATFORM,,}"
      ;;
    "11e" | "win11e" | "windows11e" | "windows 11e" )
      VERSION="win11${PLATFORM,,}-enterprise-eval"
      ;;
    "10" | "10p" | "win10" | "win10p" | "windows10" | "windows 10" )
      VERSION="win10${PLATFORM,,}"
      ;;
    "10e" | "win10e" | "windows10e" | "windows 10e" )
      VERSION="win10${PLATFORM,,}-enterprise-eval"
      ;;
    "8" | "8p" | "81" | "81p" | "8.1" | "win8" | "win8p" | "win81" | "win81p" | "windows 8" )
      VERSION="win81${PLATFORM,,}"
      ;;
    "8e" | "81e" | "8.1e" | "win8e" | "win81e" | "windows 8e" )
      VERSION="win81${PLATFORM,,}-enterprise-eval"
      ;;
    "7" | "7e" | "win7" | "win7e" | "windows7" | "windows 7" )
      VERSION="win7${PLATFORM,,}"
      [ -z "$DETECTED" ] && DETECTED="win7${PLATFORM,,}-enterprise"
      ;;
    "7u" | "win7u" | "windows7u" | "windows 7u" )
      VERSION="win7${PLATFORM,,}-ultimate"
      ;;
    "vista" | "winvista" | "windowsvista" | "windows vista" )
      VERSION="winvista${PLATFORM,,}"
      [ -z "$DETECTED" ] && DETECTED="winvista${PLATFORM,,}-enterprise"
      ;;
    "vistu" | "winvistu" | "windowsvistu" | "windows vistu" )
      VERSION="winvista${PLATFORM,,}-ultimate"
      ;;
    "xp" | "xp32" | "xpx86" | "winxp" | "winxp86" | "windowsxp" | "windows xp" )
      VERSION="winxpx86"
      ;;
    "xp64" | "xpx64" | "winxp64" | "winxpx64" | "windowsxp64" | "windowsxpx64" )
      VERSION="winxp${PLATFORM,,}"
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
    "core11" | "core 11" )
      VERSION="core11"
      [ -z "$DETECTED" ] && DETECTED="win11${PLATFORM,,}"
      ;;
    "tiny11" | "tiny 11" )
      VERSION="tiny11"
      [ -z "$DETECTED" ] && DETECTED="win11${PLATFORM,,}"
      ;;
   "tiny10" | "tiny 10" )
      VERSION="tiny10"
      [ -z "$DETECTED" ] && DETECTED="win10${PLATFORM,,}-ltsc"
      ;;
    "iot11" | "11iot" | "win11-iot" | "win11${PLATFORM,,}-iot" | "win11${PLATFORM,,}-enterprise-iot-eval" )
      VERSION="win11${PLATFORM,,}-enterprise-iot-eval"
      [ -z "$DETECTED" ] && DETECTED="win11${PLATFORM,,}-iot"
      ;;
    "iot10" | "10iot" | "win10-iot" | "win10${PLATFORM,,}-iot" | "win10${PLATFORM,,}-enterprise-iot-eval" )
      VERSION="win10${PLATFORM,,}-enterprise-iot-eval"
      [ -z "$DETECTED" ] && DETECTED="win10${PLATFORM,,}-iot"
      ;;
    "ltsc10" | "10ltsc" | "win10-ltsc" | "win10${PLATFORM,,}-ltsc" | "win10${PLATFORM,,}-enterprise-ltsc-eval" )
      VERSION="win10${PLATFORM,,}-enterprise-ltsc-eval"
      [ -z "$DETECTED" ] && DETECTED="win10${PLATFORM,,}-ltsc"
      ;;
  esac

  return 0
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
    "winvista"* ) desc="Windows Vista" ;;
    "win2025"* ) desc="Windows Server 2025" ;;
    "win2022"* ) desc="Windows Server 2022" ;;
    "win2019"* ) desc="Windows Server 2019" ;;
    "win2016"* ) desc="Windows Server 2016" ;;
    "win2012"* ) desc="Windows Server 2012" ;;
    "win2008"* ) desc="Windows Server 2008" ;;
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
    *"-iot" )
      edition="IoT"
      ;;
    *"-ltsc" )
      edition="LTSC"
      ;;
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
    "win2025"* | "win2022"* | "win2019"* | "win2016"* | "win2012"* | "win2008"* )
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

  case "${file/ /_}" in
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

  case "${file/ /_}" in
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
    "win10"* )
        case "${name,,}" in
          *" iot"* ) id="$id-iot" ;;
          *" ltsc"* ) id="$id-ltsc" ;;
          *" home"* ) id="$id-home" ;;
          *" education"* ) id="$id-education" ;;
          *" enterprise evaluation"* ) id="$id-enterprise-eval" ;;
          *" enterprise"* ) id="$id-enterprise" ;;
        esac
      ;;
    "win11"* )
       case "${name,,}" in
          *" iot"* ) id="$id-iot" ;;
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
    "win2022-eval" ) DETECTED="win2022" ;;
    "win2019-eval" ) DETECTED="win2019" ;;
    "win2016-eval" ) DETECTED="win2016" ;;
    "win2012r2-eval" ) DETECTED="win2012r2" ;;
    "win2008r2-eval" ) DETECTED="win2008r2" ;;
  esac

  return 0
}

getCatalog() {

  local id="$1"
  local ret="$2"
  local url=""
  local name=""
  local edition=""

  case "${id,,}" in
    "win11${PLATFORM,,}" )
      edition="Professional"
      name="Windows 11 Pro"
      url="https://go.microsoft.com/fwlink?linkid=2156292"
      ;;
    "win10${PLATFORM,,}" )
      edition="Professional"
      name="Windows 10 Pro"
      url="https://go.microsoft.com/fwlink/?LinkId=841361"
      ;;
    "win11${PLATFORM,,}-enterprise" | "win11${PLATFORM,,}-enterprise-eval")
      edition="Enterprise"
      name="Windows 11 Enterprise"
      url="https://go.microsoft.com/fwlink?linkid=2156292"
      ;;
    "win10${PLATFORM,,}-enterprise" | "win10${PLATFORM,,}-enterprise-eval" )
      edition="Enterprise"
      name="Windows 10 Enterprise"
      url="https://go.microsoft.com/fwlink/?LinkId=841361"
      ;;
  esac

  case "${ret,,}" in
    "url" ) echo "$url" ;;
    "name" ) echo "$name" ;;
    "edition" ) echo "$edition" ;;
    *) echo "";;
  esac

  return 0
}

getMido() {

  local id="$1"
  local ret="$2"
  local sum=""
  local size=""

  case "${id,,}" in
    "win11${PLATFORM,,}" )
      size=6812706816
      sum="36de5ecb7a0daa58dce68c03b9465a543ed0f5498aa8ae60ab45fb7c8c4ae402"
      ;;
    "win11${PLATFORM,,}-enterprise-eval" )
      size=6209064960
      sum="c8dbc96b61d04c8b01faf6ce0794fdf33965c7b350eaa3eb1e6697019902945c"
      ;;
    "win10${PLATFORM,,}" )
      size=6140975104
      sum="a6f470ca6d331eb353b815c043e327a347f594f37ff525f17764738fe812852e"
      ;;
    "win10${PLATFORM,,}-enterprise-eval" )
      size=5550497792
      sum="ef7312733a9f5d7d51cfa04ac497671995674ca5e1058d5164d6028f0938d668"
      ;;
    "win10${PLATFORM,,}-enterprise-ltsc-eval" )
      size=4898582528
      sum="e4ab2e3535be5748252a8d5d57539a6e59be8d6726345ee10e7afd2cb89fefb5"
      ;;
    "win81${PLATFORM,,}" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      ;;
    "win81${PLATFORM,,}-enterprise-eval" )
      size=3961473024
      sum="2dedd44c45646c74efc5a028f65336027e14a56f76686a4631cf94ffe37c72f2"
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

  return 1
}

getLink1() {

  # Fallbacks for users who cannot connect to the Microsoft servers

  local id="$1"
  local ret="$2"
  local url=""
  local sum=""
  local size=""
  local host="https://dl.bobpony.com/windows"

  case "${id,,}" in
    "win11${PLATFORM,,}" )
      size=5946128384
      sum="5bb1459034f50766ee480d895d751af73a4af30814240ae32ebc5633546a5af7"
      url="$host/11/en-us_windows_11_23h2_${PLATFORM,,}.iso"
      ;;
    "win10${PLATFORM,,}" )
      size=4957009920
      sum="6673e2ab6c6939a74eceff2c2bb4d36feb94ff8a6f71700adef0f0b998fdcaca"
      url="$host/10/en-us_windows_10_22h2_${PLATFORM,,}.iso"
      ;;
    "win10${PLATFORM,,}-iot" | "win10${PLATFORM,,}-enterprise-iot-eval" )
      size=4851668992
      sum="a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
      url="$host/10/en-us_windows_10_iot_enterprise_ltsc_2021_${PLATFORM,,}_dvd_257ad90f.iso"
      ;;
    "win10${PLATFORM,,}-ltsc" | "win10${PLATFORM,,}-enterprise-ltsc-eval" )
      size=4899461120
      sum="c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d"
      url="$host/10/en-us_windows_10_enterprise_ltsc_2021_${PLATFORM,,}_dvd_d289cf96.iso"
      ;;
    "win81${PLATFORM,,}" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      url="$host/8.x/8.1/en_windows_8.1_with_update_${PLATFORM,,}_dvd_6051480.iso"
      ;;
    "win2022" | "win2022-eval" )
      size=5365624832
      sum="c3c57bb2cf723973a7dcfb1a21e97dfa035753a7f111e348ad918bb64b3114db"
      url="$host/server/2022/en-us_windows_server_2022_updated_jan_2024_${PLATFORM,,}_dvd_2b7a0c9f.iso"
      ;;
    "win2019" | "win2019-eval" )
      size=5575774208
      sum="0067afe7fdc4e61f677bd8c35a209082aa917df9c117527fc4b2b52a447e89bb"
      url="$host/server/2019/en-us_windows_server_2019_updated_aug_2021_${PLATFORM,,}_dvd_a6431a28.iso"
      ;;
    "win2016" | "win2016-eval" )
      size=6006587392
      sum="af06e5483c786c023123e325cea4775050324d9e1366f46850b515ae43f764be"
      url="$host/server/2016/en_windows_server_2016_updated_feb_2018_${PLATFORM,,}_dvd_11636692.iso"
      ;;
    "win2012r2" | "win2012r2-eval" )
      size=5397889024
      sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
      url="$host/server/2012r2/en_windows_server_2012_r2_with_update_${PLATFORM,,}_dvd_6052708-004.iso"
      ;;
    "win2008r2" | "win2008r2-eval" )
      size=3166584832
      sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
      url="$host/server/2008r2/en_windows_server_2008_r2_with_sp1_${PLATFORM,,}_dvd_617601-018.iso"
      ;;
    "win7${PLATFORM,,}" | "win7${PLATFORM,,}-enterprise" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="$host/7/en_windows_7_enterprise_with_sp1_${PLATFORM,,}_dvd_u_677651.iso"
      ;;
    "win7${PLATFORM,,}-ultimate" )
      size=3320836096
      sum="0b738b55a5ea388ad016535a5c8234daf2e5715a0638488ddd8a228a836055a1"
      url="$host/7/en_windows_7_with_sp1_${PLATFORM,,}.iso"
      ;;
    "win7x86" | "win7x86-enterprise" )
      size=2434502656
      sum="8bdd46ff8cb8b8de9c4aba02706629c8983c45e87da110e64e13be17c8434dad"
      url="$host/7/en_windows_7_enterprise_with_sp1_x86_dvd_u_677710.iso"
      ;;
    "win7x86-ultimate" )
      size=2564411392
      sum="99f3369c90160816be07093dbb0ac053e0a84e52d6ed1395c92ae208ccdf67e5"
      url="$host/7/en_windows_7_with_sp1_x86.iso"
      ;;
    "winvista${PLATFORM,,}-ultimate" )
      size=3861460992
      sum="edf9f947c5791469fd7d2d40a5dcce663efa754f91847aa1d28ed7f585675b78"
      url="$host/vista/en_windows_vista_sp2_${PLATFORM,,}_dvd_342267.iso"
      ;;
    "winvistax86-ultimate" )
      size=3243413504
      sum="9c36fed4255bd05a8506b2da88f9aad73643395e155e609398aacd2b5276289c"
      url="$host/vista/en_windows_vista_with_sp2_x86_dvd_342266.iso"
      ;;
    "winxpx86" )
      size=617756672
      sum="62b6c91563bad6cd12a352aa018627c314cfc5162d8e9f8af0756a642e602a46"
      url="$host/xp/professional/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
    "winxpx64" )
      size=614166528
      sum="8fac68e1e56c64ad9a2aa0ad464560282e67fa4f4dd51d09a66f4e548eb0f2d6"
      url="$host/xp/professional/en_win_xp_pro_${PLATFORM,,}_vl.iso" 
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) echo "$url";;
  esac

  return 0
}

getLink2() {

  local id="$1"
  local ret="$2"
  local url=""
  local sum=""
  local size=""
  local host="https://files.dog/MSDN"

  case "${id,,}" in
    "win81${PLATFORM,,}" )
      size=4320526336
      sum="d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51"
      url="$host/Windows%208.1%20with%20Update/en_windows_8.1_with_update_${PLATFORM,,}_dvd_6051480.iso"
      ;;
    "win81${PLATFORM,,}-enterprise" | "win81${PLATFORM,,}-enterprise-eval" )
      size=4139163648
      sum="c3c604c03677504e8905090a8ce5bb1dde76b6fd58e10f32e3a25bef21b2abe1"
      url="$host/Windows%208.1%20with%20Update/en_windows_8.1_enterprise_with_update_${PLATFORM,,}_dvd_6054382.iso"
      ;;
    "win2012r2" | "win2012r2-eval" )
      size=5397889024
      sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
      url="$host/Windows%20Server%202012%20R2%20with%20Update/en_windows_server_2012_r2_with_update_${PLATFORM,,}_dvd_6052708.iso"
      ;;
    "win2008r2" | "win2008r2-eval" )
      size=3166584832
      sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
      url="$host/Windows%20Server%202008%20R2/en_windows_server_2008_r2_with_sp1_${PLATFORM,,}_dvd_617601.iso"
      ;;
    "win7${PLATFORM,,}" | "win7${PLATFORM,,}-enterprise" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="$host/Windows%207/en_windows_7_enterprise_with_sp1_${PLATFORM,,}_dvd_u_677651.iso"
      ;;
    "win7${PLATFORM,,}-ultimate" )
      size=3320903680
      sum="36f4fa2416d0982697ab106e3a72d2e120dbcdb6cc54fd3906d06120d0653808"
      url="$host/Windows%207/en_windows_7_ultimate_with_sp1_${PLATFORM,,}_dvd_u_677332.iso"
      ;;
    "win7x86" | "win7x86enterprise" )
      size=2434502656
      sum="8bdd46ff8cb8b8de9c4aba02706629c8983c45e87da110e64e13be17c8434dad"
      url="$host/Windows%207/en_windows_7_enterprise_with_sp1_x86_dvd_u_677710.iso"
      ;;
    "win7x86-ultimate" )
      size=2564476928
      sum="e2c009a66d63a742941f5087acae1aa438dcbe87010bddd53884b1af6b22c940"
      url="$host/Windows%207/en_windows_7_ultimate_with_sp1_x86_dvd_u_677460.iso"
      ;;
    "winvista${PLATFORM,,}" | "winvista${PLATFORM,,}-enterprise" )
      size=3205953536
      sum="0a0cd511b3eac95c6f081419c9c65b12317b9d6a8d9707f89d646c910e788016"
      url="$host/Windows%20Vista/en_windows_vista_enterprise_sp2_${PLATFORM,,}_dvd_342332.iso"
      ;;
    "winvista${PLATFORM,,}-ultimate" )
      size=3861460992
      sum="edf9f947c5791469fd7d2d40a5dcce663efa754f91847aa1d28ed7f585675b78"
      url="$host/Windows%20Vista/en_windows_vista_sp2_${PLATFORM,,}_dvd_342267.iso"
      ;;
    "winvistax86" | "winvistax86-enterprise" )
      size=2420981760
      sum="54e2720004041e7db988a391543ea5228b0affc28efcf9303d2d0ff9402067f5"
      url="$host/Windows%20Vista/en_windows_vista_enterprise_sp2_x86_dvd_342329.iso"
      ;;
    "winvistax86-ultimate" )
      size=3243413504
      sum="9c36fed4255bd05a8506b2da88f9aad73643395e155e609398aacd2b5276289c"
      url="$host/Windows%20Vista/en_windows_vista_with_sp2_x86_dvd_342266.iso"
      ;;
    "winxpx86" )
      size=617756672
      sum="62b6c91563bad6cd12a352aa018627c314cfc5162d8e9f8af0756a642e602a46"
      url="$host/Windows%20XP/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
    "winxpx64" )
      size=614166528
      sum="8fac68e1e56c64ad9a2aa0ad464560282e67fa4f4dd51d09a66f4e548eb0f2d6"
      url="$host/Windows%20XP/en_win_xp_pro_${PLATFORM,,}_vl.iso"
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) echo "$url";;
  esac

  return 0
}

getLink3() {

  local id="$1"
  local ret="$2"
  local url=""
  local sum=""
  local size=""
  local host="https://file.cnxiaobai.com/Windows"

  case "${id,,}" in
    "core11" )
      size=2159738880
      sum="78f0f44444ff95b97125b43e560a72e0d6ce0a665cf9f5573bf268191e5510c1"
      url="$host/%E7%B3%BB%E7%BB%9F%E5%AE%89%E8%A3%85%E5%8C%85/Tiny%2010_11/tiny11%20core%20${PLATFORM,,}%20beta%201.iso"
      ;;
    "tiny11" )
      size=3788177408
      sum="a028800a91addc35d8ae22dce7459b67330f7d69d2f11c70f53c0fdffa5b4280"
      url="$host/%E7%B3%BB%E7%BB%9F%E5%AE%89%E8%A3%85%E5%8C%85/Tiny%2010_11/tiny11%202311%20${PLATFORM,,}.iso"
      ;;
    "tiny10" )
      size=3839819776
      sum="a11116c0645d892d6a5a7c585ecc1fa13aa66f8c7cc6b03bf1f27bd16860cc35"
      url="$host/%E7%B3%BB%E7%BB%9F%E5%AE%89%E8%A3%85%E5%8C%85/Tiny%2010_11/tiny10%2023H2%20${PLATFORM,,}.iso"
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) echo "$url";;
  esac

  return 0
}

getLink4() {

  # Fallbacks for users who cannot connect to the Microsoft servers

  local id="$1"
  local ret="$2"
  local url=""
  local sum=""
  local size=""
  local host="https://drive.massgrave.dev"

  case "${id,,}" in
    "win11${PLATFORM,,}" )
      size=7004780544
      sum="a6c21313210182e0315054789a2b658b77394d5544b69b5341075492f89f51e5"
      url="$host/en-us_windows_11_consumer_editions_version_23h2_updated_april_2024_${PLATFORM,,}_dvd_d986680b.iso"
      ;;
    "win11${PLATFORM,,}-enterprise" | "win11${PLATFORM,,}-enterprise-eval" )
      size=6879023104
      sum="3d4d388d6ffa371956304fa7401347b4535fd10e3137978a8f7750b790a43521"
      url="$host/en-us_windows_11_business_editions_version_23h2_updated_april_2024_${PLATFORM,,}_dvd_349cd577.iso"
      ;;
    "win11${PLATFORM,,}-iot" | "win11${PLATFORM,,}-enterprise-iot-eval" )
      size=6248140800
      sum="5d9b86ad467bc89f488d1651a6c5ad3656a7ea923f9f914510657a24c501bb86"
      url="$host/en-us_windows_11_iot_enterprise_version_23h2_${PLATFORM,,}_dvd_fb37549c.iso"
      ;;
    "win10${PLATFORM,,}" )
      size=6605459456
      sum="b072627c9b8d9f62af280faf2a8b634376f91dc73ea1881c81943c151983aa4a"
      url="$host/en-us_windows_10_consumer_editions_version_22h2_updated_april_2024_${PLATFORM,,}_dvd_9a92dc89.iso"
      ;;
    "win10${PLATFORM,,}-enterprise" | "win10${PLATFORM,,}-enterprise-eval" )
      size=6428377088
      sum="05fe9de04c2626bd00fbe69ad19129b2dbb75a93a2fe030ebfb2256d937ceab8"
      url="$host/en-us_windows_10_business_editions_version_22h2_updated_april_2024_${PLATFORM,,}_dvd_c00090a7.iso"
      ;;
    "win10${PLATFORM,,}-iot" | "win10${PLATFORM,,}-enterprise-iot-eval" )
      size=4851668992
      sum="a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
      url="$host/en-us_windows_10_iot_enterprise_ltsc_2021_${PLATFORM,,}_dvd_257ad90f.iso"
      ;;
    "win10${PLATFORM,,}-ltsc" | "win10${PLATFORM,,}-enterprise-ltsc-eval" )
      size=4899461120
      sum="c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d"
      url="$host/en-us_windows_10_enterprise_ltsc_2021_${PLATFORM,,}_dvd_d289cf96.iso"
      ;;
    "win81${PLATFORM,,}-enterprise" | "win81${PLATFORM,,}-enterprise-eval" )
      size=4139163648
      sum="c3c604c03677504e8905090a8ce5bb1dde76b6fd58e10f32e3a25bef21b2abe1"
      url="$host/en_windows_8.1_enterprise_with_update_${PLATFORM,,}_dvd_6054382.iso"
      ;;
    "win2022" | "win2022-eval" )
      size=5515755520
      sum="7f41d603224e8a0bf34ba957d3abf0a02437ab75000dd758b5ce3f050963e91f"
      url="$host/en-us_windows_server_2022_updated_april_2024_${PLATFORM,,}_dvd_164349f3.iso"
      ;;
    "win2019" | "win2019-eval" )
      size=4843268096
      sum="4c5dd63efee50117986a2e38d4b3a3fbaf3c1c15e2e7ea1d23ef9d8af148dd2d"
      url="$host/en_windows_server_2019_${PLATFORM,,}_dvd_4cb967d8.iso"
      ;;
    "win2016" | "win2016-eval" )
      size=5653628928
      sum="4caeb24b661fcede81cd90661aec31aa69753bf49a5ac247253dd021bc1b5cbb"
      url="$host/en_windows_server_2016_${PLATFORM,,}_dvd_9327751.iso"
      ;;
    "win2012r2" | "win2012r2-eval" )
      size=5397889024
      sum="f351e89eb88a96af4626ceb3450248b8573e3ed5924a4e19ea891e6003b62e4e"
      url="$host/en_windows_server_2012_r2_with_update_${PLATFORM,,}_dvd_6052708.iso"
      ;;
    "win2008r2" | "win2008r2-eval" )
      size=3166584832
      sum="dfd9890881b7e832a927c38310fb415b7ea62ac5a896671f2ce2a111998f0df8"
      url="$host/en_windows_server_2008_r2_with_sp1_${PLATFORM,,}_dvd_617601.iso"
      ;;
    "win7${PLATFORM,,}" | "win7${PLATFORM,,}-enterprise" )
      size=3182604288
      sum="ee69f3e9b86ff973f632db8e01700c5724ef78420b175d25bae6ead90f6805a7"
      url="$host/en_windows_7_enterprise_with_sp1_${PLATFORM,,}_dvd_u_677651.iso"
      ;;
    "win7${PLATFORM,,}-ultimate" )
      size=3320903680
      sum="36f4fa2416d0982697ab106e3a72d2e120dbcdb6cc54fd3906d06120d0653808"
      url="$host/en_windows_7_ultimate_with_sp1_${PLATFORM,,}_dvd_u_677332.iso"
      ;;
    "win7x86" | "win7x86enterprise" )
      size=2434502656
      sum="8bdd46ff8cb8b8de9c4aba02706629c8983c45e87da110e64e13be17c8434dad"
      url="$host/en_windows_7_enterprise_with_sp1_x86_dvd_u_677710.iso"
      ;;
    "win7x86-ultimate" )
      size=2564476928
      sum="e2c009a66d63a742941f5087acae1aa438dcbe87010bddd53884b1af6b22c940"
      url="$host/en_windows_7_ultimate_with_sp1_x86_dvd_u_677460.iso"
      ;;
    "winvista${PLATFORM,,}" | "winvista${PLATFORM,,}-enterprise" )
      size=3205953536
      sum="0a0cd511b3eac95c6f081419c9c65b12317b9d6a8d9707f89d646c910e788016"
      url="$host/en_windows_vista_enterprise_sp2_${PLATFORM,,}_dvd_342332.iso"
      ;;
    "winvista${PLATFORM,,}-ultimate" )
      size=3861460992
      sum="edf9f947c5791469fd7d2d40a5dcce663efa754f91847aa1d28ed7f585675b78"
      url="$host/en_windows_vista_sp2_${PLATFORM,,}_dvd_342267.iso"
      ;;
    "winvistax86" | "winvistax86-enterprise" )
      size=2420981760
      sum="54e2720004041e7db988a391543ea5228b0affc28efcf9303d2d0ff9402067f5"
      url="$host/en_windows_vista_enterprise_sp2_x86_dvd_342329.iso"
      ;;
    "winvistax86-ultimate" )
      size=3243413504
      sum="9c36fed4255bd05a8506b2da88f9aad73643395e155e609398aacd2b5276289c"
      url="$host/en_windows_vista_with_sp2_x86_dvd_342266.iso"
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) echo "$url";;
  esac

  return 0
}

getLink5() {

  local id="$1"
  local ret="$2"
  local url=""
  local sum=""
  local size=""
  local host="https://archive.org/download"

  case "${id,,}" in
    "core11" )
      size=2159738880
      sum="78f0f44444ff95b97125b43e560a72e0d6ce0a665cf9f5573bf268191e5510c1"
      url="$host/tiny-11-core-x-64-beta-1/tiny11%20core%20${PLATFORM,,}%20beta%201.iso"
      ;;
    "tiny11" )
      size=3788177408
      sum="a028800a91addc35d8ae22dce7459b67330f7d69d2f11c70f53c0fdffa5b4280"
      url="$host/tiny11-2311/tiny11%202311%20${PLATFORM,,}.iso"
      ;;
    "tiny10" )
      size=3839819776
      sum="a11116c0645d892d6a5a7c585ecc1fa13aa66f8c7cc6b03bf1f27bd16860cc35"
      url="$host/tiny-10-23-h2/tiny10%20${PLATFORM,,}%2023h2.iso"
      ;;
    "winxpx86" )
      size=617756672
      sum="62b6c91563bad6cd12a352aa018627c314cfc5162d8e9f8af0756a642e602a46"
      url="$host/XPPRO_SP3_ENU/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
      ;;
  esac

  case "${ret,,}" in
    "sum" ) echo "$sum" ;;
    "size" ) echo "$size" ;;
    *) echo "$url";;
  esac

  return 0
}

getValue() {

  local val=""
  local id="$3"
  local type="$2"
  local func="getLink$1"

  if [ "$1" -gt 0 ] && [ "$1" -le "$MIRRORS" ]; then
    val=$($func "$id" "$type")
  fi

  echo "$val"
  return 0
}

getLink() {

  local url=""
  url=$(getValue "$1" "" "$2")

  echo "$url"
  return 0
}

getHash() {

  local sum=""
  sum=$(getValue "$1" "sum" "$2")

  echo "$sum"
  return 0
}

getSize() {

  local size=""
  size=$(getValue "$1" "size" "$2")

  echo "$size"
  return 0
}

isMido() {

  local id="$1"
  local sum

  sum=$(getMido "$id" "sum")
  [ -n "$sum" ] && return 0

  return 1
}

isESD() {

  local id="$1"
  local url

  url=$(getCatalog "$id" "url")
  [ -n "$url" ] && return 0

  return 1
}

validVersion() {

  local id="$1"
  local url

  isESD "$id" && return 0
  isMido "$id" && return 0

  for ((i=1;i<=MIRRORS;i++)); do

    url=$(getLink "$i" "$id")
    [ -n "$url" ] && return 0

  done

  return 1
}

migrateFiles() {

  local base="$1"
  local version="$2"
  local file=""

  [ -f "$base" ] && return 0

  [[ "${version,,}" == "tiny10" ]] && file="tiny10_${PLATFORM,,}_23h2.iso"
  [[ "${version,,}" == "tiny11" ]] && file="tiny11_2311_${PLATFORM,,}.iso"
  [[ "${version,,}" == "core11" ]] && file="tiny11_core_${PLATFORM,,}_beta_1.iso"
  [[ "${version,,}" == "winxpx86" ]] && file="en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
  [[ "${version,,}" == "winvista${PLATFORM,,}" ]] && file="en_windows_vista_sp2_${PLATFORM,,}_dvd_342267.iso"
  [[ "${version,,}" == "win7${PLATFORM,,}" ]] && file="en_windows_7_enterprise_with_sp1_${PLATFORM,,}_dvd_u_677651.iso"

  [ ! -f "$STORAGE/$file" ] && return 0
  ! mv -f "$STORAGE/$file" "$base" && return 1

  return 0
}

configXP() {

  local dir="$1"
  local arch="x86"
  local target="$dir/I386"
  local drivers="$TMP/drivers"

  if [ -d "$dir/AMD64" ]; then
    arch="amd64"
    target="$dir/AMD64"
  fi

  rm -rf "$drivers"

  if ! 7z x /run/drivers.iso -o"$drivers" > /dev/null; then
    error "Failed to extract driver ISO file!" && return 1
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

  local key pid setup
  setup=$(find "$target" -maxdepth 1 -type f -iname setupp.ini | head -n 1)
  pid=$(<"$setup")
  pid="${pid:(-4)}"
  pid="${pid:0:3}"

  if [[ "$pid" == "270" ]]; then
    info "Warning: this XP version requires a volume license, it will reject the generic key during installation."
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

  find "$target" -maxdepth 1 -type f -iname winnt.sif -exec rm {} \;

  {       echo "[Data]"
          echo "AutoPartition=1"
          echo "MsDosInitiated=\"0\""
          echo "UnattendedInstall=\"Yes\""
          echo "AutomaticUpdates=\"Yes\""
          echo ""
          echo "[Unattended]"
          echo "UnattendSwitch=Yes"
          echo "UnattendMode=FullUnattended"
          echo "FileSystem=NTFS"
          echo "OemSkipEula=Yes"
          echo "OemPreinstall=Yes"
          echo "Repartition=Yes"
          echo "WaitForReboot=\"No\""
          echo "DriverSigningPolicy=\"Ignore\""
          echo "NonDriverSigningPolicy=\"Ignore\""
          echo "OemPnPDriversPath=\"Drivers\viostor;Drivers\NetKVM;Drivers\sata\""
          echo "NoWaitAfterTextMode=1"
          echo "NoWaitAfterGUIMode=1"
          echo "FileSystem-ConvertNTFS"
          echo "ExtendOemPartition=0"
          echo "Hibernation=\"No\""
          echo ""
          echo "[GuiUnattended]"
          echo "OEMSkipRegional=1"
          echo "OemSkipWelcome=1"
          echo "AdminPassword=*"
          echo "TimeZone=0"
          echo "AutoLogon=Yes"
          echo "AutoLogonCount=65432"
          echo ""
          echo "[UserData]"
          echo "FullName=\"Docker\""
          echo "ComputerName=\"*\""
          echo "OrgName=\"Windows for Docker\""
          echo "ProductKey=$key"
          echo ""
          echo "[Identification]"
          echo "JoinWorkgroup = WORKGROUP"
          echo ""
          echo "[Networking]"
          echo "InstallDefaultComponents=Yes"
          echo ""
          echo "[Branding]"
          echo "BrandIEUsingUnattended=Yes"
          echo ""
          echo "[URL]"
          echo "Home_Page = http://www.google.com"
          echo "Search_Page = http://www.google.com"
          echo ""
          echo "[RegionalSettings]"
          echo "Language=00000409"
          echo ""
          echo "[TerminalServices]"
          echo "AllowConnections=1"
  } | unix2dos > "$target/WINNT.SIF"

  {       echo "Windows Registry Editor Version 5.00"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Security]"
          echo "\"FirstRunDisabled\"=dword:00000001"
          echo "\"AntiVirusOverride\"=dword:00000001"
          echo "\"FirewallOverride\"=dword:00000001"
          echo "\"FirewallDisableNotify\"=dword:00000001"
          echo "\"UpdatesDisableNotify\"=dword:00000001"
          echo "\"AntiVirusDisableNotify\"=dword:00000001"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\wscsvc]"
          echo "\"Start\"=dword:00000004"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\WindowsFirewall\StandardProfile]"
          echo "\"EnableFirewall\"=dword:00000000"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess]"
          echo "\"Start\"=dword:00000004"
          echo
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
          echo "\"DefaultUserName\"=\"Docker\""
          echo "\"DefaultDomainName\"=\"Dockur\""
          echo "\"AltDefaultUserName\"=\"Docker\""
          echo "\"AltDefaultDomainName\"=\"Dockur\""
          echo "\"AutoAdminLogon\"=\"1\""
  } | unix2dos > "$dir/\$OEM\$/install.reg"

  {       echo "Set WshShell = WScript.CreateObject(\"WScript.Shell\")"
          echo "Set WshNetwork = WScript.CreateObject(\"WScript.Network\")"
          echo "Set oMachine = GetObject(\"WinNT://\" & WshNetwork.ComputerName)"
          echo "Set oInfoUser = GetObject(\"WinNT://\" & WshNetwork.ComputerName & \"/Administrator,user\")"
          echo "Set oUser = oMachine.MoveHere(oInfoUser.ADsPath,\"Docker\")"
  } | unix2dos > "$dir/\$OEM\$/admin.vbs"

  {       echo "[COMMANDS]"
          echo "\"REGEDIT /s install.reg\""
          echo "\"Wscript admin.vbs\""
  } | unix2dos > "$dir/\$OEM\$/cmdlines.txt"

  rm -rf "$drivers"
  return 0
}

prepareXP() {

  local iso="$1"
  local dir="$2"

  MACHINE="pc-q35-2.10"
  ETFS="[BOOT]/Boot-NoEmul.img"

  [[ "$MANUAL" == [Yy1]* ]] && return 0
  configXP "$dir" && return 0

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

return 0
