#!/bin/sh

# Copyright (C) 2024 Elliot Killick <contact@elliotkillick.com>
# Licensed under the MIT License. See LICENSE file for details.

# Prefer Dash shell for greater security if available
if [ "$BASH" ] && command -v dash > /dev/null; then
    exec dash "$0" "$@"
fi

# Test for 4-bit color (16 colors)
# Operand "colors" is undefined by POSIX
# If the operand doesn't exist, the terminal probably doesn't support color and the program will continue normally without it
if [ "0$(tput colors 2> /dev/null)" -ge 16 ]; then
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    GREEN='\033[0;32m'
    NC='\033[0m'
fi

# Avoid printing messages as potential terminal escape sequences
echo_ok() { printf "%b%s%b" "${GREEN}[+]${NC} " "$1" "\n" >&2; }
echo_info() { printf "%b%s%b" "${BLUE}[i]${NC} " "$1" "\n" >&2; }
echo_err() { printf "%b%s%b" "${RED}[!]${NC} " "$1" "\n" >&2; }

# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/fold.html
format() { fold -s; }

word_count() { echo $#; }

usage() {
    echo "Mido - The Secure Microsoft Windows Downloader"
    echo ""
    echo "Usage: $0 <windows_media>..."
    echo ""
    echo "Download specified list of Windows media."
    echo ""
    echo "Specify \"all\", or one or more of the following Windows media:"
    echo "  win7x64-ultimate"
    echo "  win81x64"
    echo "  win10x64"
    echo "  win11x64"
    echo "  win81x64-enterprise-eval"
    echo "  win10x64-enterprise-eval"
    echo "  win11x64-enterprise-eval"
    echo "  win10x64-enterprise-ltsc-eval (most secure)"
    echo "  win2008r2"
    echo "  win2012r2-eval"
    echo "  win2016-eval"
    echo "  win2019-eval"
    echo "  win2022-eval"
    echo ""
    echo "Each ISO download takes between 3 - 7 GiBs (average: 5 GiBs)."
    echo ""
    echo "Updates"
    echo "-------"
    echo "All the downloads provided here are the most up-to-date releases that Microsoft provides. This is ensured by programmatically checking Microsoft's official download pages to get the latest download link. In other cases, the Windows version in question is no longer supported by Microsoft meaning a direct download link (stored in Mido) will always point to the most up-to-date release." | format
    echo ""
    echo "Remember to update Windows to the latest patch level after installation."
    echo ""
    echo "Overuse"
    echo "-------"
    echo "Newer consumer versions of Windows including win81x64, win10x64, and win11x64 are downloaded through Microsoft's gated download web interface. Do not overuse this interface. Microsoft may be quick to do ~24 hour IP address bans after only a few download requests (especially if they are done in quick succession). Being temporarily banned from one of these downloads (e.g. win11x64) doesn't cause you to be banned from any of the other downloads provided through this interface." | format
    echo ""
    echo "Privacy Preserving Technologies"
    echo "-------------------------------"
    echo "The aforementioned Microsoft gated download web interface is currently blocking Tor (and similar technologies). They say this is to prevent people in restricted regions from downloading certain Windows media they shouldn't have access to. This is fine by most standards because Tor is too slow for large downloads anyway and we have checksum verification for security." | format
    echo ""
    echo "Language"
    echo "--------"
    echo "All the downloads provided here are for English (United States). This helps to great simplify maintenance and minimize the user's fingerprint. If another language is desired then that can easily be configured in Windows once it's installed." | format
    echo ""
    echo "Architecture"
    echo "------------"
    echo "All the downloads provided here are for x86-64 (x64). This is the only architecture Microsoft ships Windows Server in.$([ -d /run/qubes ] && echo ' Also, the only architecture Qubes OS supports.')" | format
}

# Media naming scheme info:
# Windows Server has no architecture because Microsoft only supports amd64 for this version of Windows (the last version to support x86 was Windows Server 2008 without the R2)
# "eval" is short for "evaluation", it's simply the license type included with the Windows installation (only exists on enterprise/server) and must be specified in the associated answer file
# "win7x64" has the "ultimate" edition appended to it because it isn't "multi-edition" like the other Windows ISOs (for multi-edition ISOs the edition is specified in the associated answer file)

readonly win7x64_ultimate="win7x64-ultimate.iso"
readonly win81x64="win81x64.iso"
readonly win10x64="win10x64.iso"
readonly win11x64="win11x64.iso"
readonly win81x64_enterprise_eval="win81x64-enterprise-eval.iso"
readonly win10x64_enterprise_eval="win10x64-enterprise-eval.iso"
readonly win11x64_enterprise_eval="win11x64-enterprise-eval.iso"
readonly win10x64_enterprise_ltsc_eval="win10x64-enterprise-ltsc-eval.iso"
readonly win2008r2="win2008r2.iso"
readonly win2012r2_eval="win2012r2-eval.iso"
readonly win2016_eval="win2016-eval.iso"
readonly win2019_eval="win2019-eval.iso"
readonly win2022_eval="win2022-eval.iso"

parse_args() {
    for arg in "$@"; do
        if [ "$arg" = "-h" ] ||  [ "$arg" = "--help" ]; then
            usage
            exit
        fi
    done

    if [ $# -lt 1 ]; then
        usage >&2
        exit 1
    fi

    # Append to media_list so media is downloaded in the order they're passed in
    for arg in "$@"; do
        case "$arg" in
            win7x64-ultimate)
                media_list="$media_list $win7x64_ultimate"
                ;;
            win81x64)
                media_list="$media_list $win81x64"
                ;;
            win10x64)
                media_list="$media_list $win10x64"
                ;;
            win11x64)
                media_list="$media_list $win11x64"
                ;;
            win81x64-enterprise-eval)
                media_list="$media_list $win81x64_enterprise_eval"
                ;;
            win10x64-enterprise-eval)
                media_list="$media_list $win10x64_enterprise_eval"
                ;;
            win11x64-enterprise-eval)
                media_list="$media_list $win11x64_enterprise_eval"
                ;;
            win10x64-enterprise-ltsc-eval)
                media_list="$media_list $win10x64_enterprise_ltsc_eval"
                ;;
            win2008r2)
                media_list="$media_list $win2008r2"
                ;;
            win2012r2-eval)
                media_list="$media_list $win2012r2_eval"
                ;;
            win2016-eval)
                media_list="$media_list $win2016_eval"
                ;;
            win2019-eval)
                media_list="$media_list $win2019_eval"
                ;;
            win2022-eval)
                media_list="$media_list $win2022_eval"
                ;;
            all)
                media_list="$win7x64_ultimate $win81x64 $win10x64 $win11x64 $win81x64_enterprise_eval $win10x64_enterprise_eval $win11x64_enterprise_eval $win10x64_enterprise_ltsc_eval $win2008r2 $win2012r2_eval $win2016_eval $win2019_eval $win2022_eval"
                break
                ;;
            *)
                echo_err "Invalid Windows media specified: $arg"
                exit 1
                ;;
        esac
    done
}

handle_curl_error() {
    error_code="$1"

    fatal_error_action=2

    case "$error_code" in
        6)
            echo_err "Failed to resolve Microsoft servers! Is there an Internet connection? Exiting..."
            return "$fatal_error_action"
            ;;
        7)
            echo_err "Failed to contact Microsoft servers! Is there an Internet connection or is the server down?"
            ;;
        8)
            echo_err "Microsoft servers returned a malformed HTTP response!"
            ;;
        22)
            echo_err "Microsoft servers returned a failing HTTP status code!"
            ;;
        23)
            echo_err "Failed at writing Windows media to disk! Out of disk space or permission error? Exiting..."
            return "$fatal_error_action"
            ;;
        26)
            echo_err "Ran out of memory during download! Exiting..."
            return "$fatal_error_action"
            ;;
        36)
            echo_err "Failed to continue earlier download!"
            ;;
        63)
            echo_err "Microsoft servers returned an unexpectedly large response!"
            ;;
        # POSIX defines exit statuses 1-125 as usable by us
        # https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_08_02
        $((error_code <= 125)))
            # Must be some other server or network error (possibly with this specific request/file)
            # This is when accounting for all possible errors in the curl manual assuming a correctly formed curl command and an HTTP(S) request, using only the curl features we're using, and a sane build
            echo_err "Miscellaneous server or network error!"
            ;;
        126 | 127)
            echo_err "Curl command not found! Please install curl and try again. Exiting..."
            return "$fatal_error_action"
            ;;
        # Exit statuses are undefined by POSIX beyond this point
        *)
            case "$(kill -l "$error_code")" in
                # Signals defined to exist by POSIX:
                # https://pubs.opengroup.org/onlinepubs/009695399/basedefs/signal.h.html
                INT)
                    echo_err "Curl was interrupted!"
                    ;;
                # There could be other signals but these are most common
                SEGV | ABRT)
                    echo_err "Curl crashed! Failed exploitation attempt? Please report any core dumps to curl developers. Exiting..."
                    return "$fatal_error_action"
                    ;;
                *)
                    echo_err "Curl terminated due to a fatal signal!"
                    ;;
            esac
    esac

    return 1
}

part_ext=".PART"
unverified_ext=".UNVERIFIED"

scurl_file() {
    out_file="$1"
    tls_version="$2"
    url="$3"

    part_file="${out_file}${part_ext}"

    # --location: Microsoft likes to change which endpoint these downloads are stored on but is usually kind enough to add redirects
    # --fail: Return an error on server errors where the HTTP response code is 400 or greater
    curl --progress-bar --location --output "$part_file" --continue-at - --max-filesize 10G --fail --proto =https "--tlsv$tls_version" --http1.1 -- "$url" || {
        error_code=$?
        handle_curl_error "$error_code"
        error_action=$?

        # Clean up and make sure a future resume doesn't happen from a bad download resume file
        if [ -f "$out_file" ]; then
            # If file is empty, bad HTTP code, or bad download resume file
            if [ ! -s "$out_file" ] || [ "$error_code" = 22 ] || [ "$error_code" = 36 ]; then
                echo_info "Deleting failed download..."
                rm -f "$out_file"
            fi
        fi

        return "$error_action"
    }

    # Full downloaded succeeded, ready for verification check
    mv "$part_file" "${out_file}"
}

manual_verification() {
    media_verification_failed_list="$1"
    checksum_verification_failed_list="$2"

    echo_info "Manual verification instructions"
    echo "    1. Get checksum (may already be done for you):" >&2
    echo "    sha256sum <ISO_FILENAME>" >&2
    echo "" >&2
    echo "    2. Verify media:" >&2
    echo "    Web search: https://duckduckgo.com/?q=%22CHECKSUM_HERE%22" >&2
    echo "    Onion search: https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/?q=%22CHECKSUM_HERE%22" >&2
    echo "    \"No results found\" or unexpected results indicates the media has been modified and should not be used." >&2
    echo "" >&2
    echo "    3. Remove the $unverified_ext extension from the file after performing or deciding to skip verification (not recommended):" >&2
    echo "    mv <ISO_FILENAME>$unverified_ext <ISO_FILENAME>" >&2
    echo "" >&2

    for media in $media_verification_failed_list; do
        # Read current checksum in list and then read remaining checksums back into the list (effectively running "shift" on the variable)
        # POSIX sh doesn't support indexing so do this instead to iterate both lists at once
        # POSIX sh doesn't support here-strings (<<<). We could also use the "cut" program but that's not a builtin
        IFS=' ' read -r checksum checksum_verification_failed_list << EOF
$checksum_verification_failed_list
EOF

        echo "    ${media}${unverified_ext} = $checksum" >&2
        echo "        Web search: https://duckduckgo.com/?q=%22$checksum%22" >&2
        echo "        Onion search: https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/?q=%22$checksum%22" >&2
        echo "        mv ${media}${unverified_ext} $media" >&2
        echo "" >&2
    done

    echo "    Theses searches can be performed in a web/Tor browser or more securely using" >&2
    echo "    ddgr (Debian/Fedora packages available) terminal search tool if preferred." >&2
    echo "    Once validated, consider updating the checksums in Mido by submitting a pull request on GitHub." >&2

    # If you're looking for a single secondary source to cross-reference checksums then try here: https://files.rg-adguard.net/search
    # This site is recommended by the creator of Rufus in the Fido README and has worked well for me
}

consumer_download() {
    # Copyright (C) 2024 Elliot Killick <contact@elliotkillick.com>
    # Licensed under the MIT License. See LICENSE file for details.
    #
    # This function is from the Mido project:
    # https://github.com/ElliotKillick/Mido

    # Download newer consumer Windows versions from behind gated Microsoft API

    out_file="$1"
    # Either 8, 10, or 11
    windows_version="$2"

    url="https://www.microsoft.com/en-us/software-download/windows$windows_version"
    case "$windows_version" in
        8 | 10) url="${url}ISO" ;;
    esac

    user_agent="Mozilla/5.0 (X11; Linux x86_64; rv:100.0) Gecko/20100101 Firefox/100.0"
    # uuidgen: For MacOS (installed by default) and other systems (e.g. with no /proc) that don't have a kernel interface for generating random UUIDs
    session_id="$(cat /proc/sys/kernel/random/uuid 2> /dev/null || uuidgen --random)"

    # Get product edition ID for latest release of given Windows version
    # Product edition ID: This specifies both the Windows release (e.g. 22H2) and edition ("multi-edition" is default, either Home/Pro/Edu/etc., we select "Pro" in the answer files) in one number
    # This is a request we make that Fido doesn't. Fido manually maintains a list of all the Windows release/edition product edition IDs in its script (see: $WindowsVersions array). This is helpful for downloading older releases (e.g. Windows 10 1909, 21H1, etc.) but we always want to get the newest release which is why we get this value dynamically
    # Also, keeping a "$WindowsVersions" array like Fido does would be way too much of a maintenance burden
    # Remove "Accept" header that curl sends by default (match Fido requests)
    iso_download_page_html="$(curl -sS --user-agent "$user_agent" --header "Accept:" --max-filesize 1M --fail --proto =https --tlsv1.2 --http1.1 -- "$url")" || {
        handle_curl_error $?
        return $?
    }

    # tr: Filter for only numerics to prevent HTTP parameter injection
    # head -c was recently added to POSIX: https://austingroupbugs.net/view.php?id=407
    product_edition_id="$(echo "$iso_download_page_html" | grep -Eo '<option value="[0-9]+">Windows' | cut -d '"' -f 2 | head -n 1 | tr -cd '0-9' | head -c 16)"
    [ "$VERBOSE" ] && echo "Product edition ID: $product_edition_id" >&2

    # Permit Session ID
    # "org_id" is always the same value
    curl -sS --output /dev/null --user-agent "$user_agent" --header "Accept:" --max-filesize 100K --fail --proto =https --tlsv1.2 --http1.1 -- "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$session_id" || {
        # This should only happen if there's been some change to how this API works
        handle_curl_error $?
        return $?
    }

    # Extract everything after the last slash
    url_segment_parameter="${url##*/}"

    # Get language -> skuID association table
    # SKU ID: This specifies the language of the ISO. We always use "English (United States)", however, the SKU for this changes with each Windows release
    # We must make this request so our next one will be allowed
    # --data "" is required otherwise no "Content-Length" header will be sent causing HTTP response "411 Length Required"
    language_skuid_table_html="$(curl -sS --request POST --user-agent "$user_agent" --data "" --header "Accept:" --max-filesize 10K --fail --proto =https --tlsv1.2 --http1.1 -- "https://www.microsoft.com/en-US/api/controls/contentinclude/html?pageId=a8f8f489-4c7f-463a-9ca6-5cff94d8d041&host=www.microsoft.com&segments=software-download,$url_segment_parameter&query=&action=getskuinformationbyproductedition&sessionId=$session_id&productEditionId=$product_edition_id&sdVersion=2")" || {
        handle_curl_error $?
        return $?
    }

    # tr: Filter for only alphanumerics or "-" to prevent HTTP parameter injection
    sku_id="$(echo "$language_skuid_table_html" | grep "English (United States)" | sed 's/&quot;//g' | cut -d ',' -f 1  | cut -d ':' -f 2 | tr -cd '[:alnum:]-' | head -c 16)"
    [ "$VERBOSE" ] && echo "SKU ID: $sku_id" >&2

    # Get ISO download link
    # If any request is going to be blocked by Microsoft it's always this last one (the previous requests always seem to succeed)
    # --referer: Required by Microsoft servers to allow request
    iso_download_link_html="$(curl -sS --request POST --user-agent "$user_agent" --data "" --referer "$url" --header "Accept:" --max-filesize 100K --fail --proto =https --tlsv1.2 --http1.1 -- "https://www.microsoft.com/en-US/api/controls/contentinclude/html?pageId=6e2a1789-ef16-4f27-a296-74ef7ef5d96b&host=www.microsoft.com&segments=software-download,$url_segment_parameter&query=&action=GetProductDownloadLinksBySku&sessionId=$session_id&skuId=$sku_id&language=English&sdVersion=2")" || {
        # This should only happen if there's been some change to how this API works
        handle_curl_error $?
        return $?
    }

    if ! [ "$iso_download_link_html" ]; then
        # This should only happen if there's been some change to how this API works
        echo_err "Microsoft servers gave us an empty response to our request for an automated download."
        manual_verification="true"
        return 1
    fi

    if echo "$iso_download_link_html" | grep -q "We are unable to complete your request at this time."; then
        echo_err "Microsoft blocked the automated download request based on your IP address."
        manual_verification="true"
        return 1
    fi

    # Filter for 64-bit ISO download URL
    # sed: HTML decode "&" character
    # tr: Filter for only alphanumerics or punctuation
    iso_download_link="$(echo "$iso_download_link_html" | grep -o "https://software.download.prss.microsoft.com.*IsoX64" | cut -d '"' -f 1 | sed 's/&amp;/\&/g' | tr -cd '[:alnum:][:punct:]')"

    if ! [ "$iso_download_link" ]; then
        # This should only happen if there's been some change to the download endpoint web address
        echo_err "Microsoft servers gave us no download link to our request for an automated download."
        manual_verification="true"
        return 1
    fi

    #echo_ok "Got latest ISO download link (valid for 24 hours): $iso_download_link"

    # Download ISO
    scurl_file "$out_file" "1.3" "$iso_download_link"
}

enterprise_eval_download() {
    # Copyright (C) 2024 Elliot Killick <contact@elliotkillick.com>
    # Licensed under the MIT License. See LICENSE file for details.
    #
    # This function is from the Mido project:
    # https://github.com/ElliotKillick/Mido

    # Download enterprise evaluation Windows versions

    out_file="$1"
    windows_version="$2"
    enterprise_type="$3"

    url="https://www.microsoft.com/en-us/evalcenter/download-$windows_version"

    iso_download_page_html="$(curl -sS --location --max-filesize 1M --fail --proto =https --tlsv1.2 --http1.1 -- "$url")" || {
        handle_curl_error $?
        return $?
    }

    if ! [ "$iso_download_page_html" ]; then
        # This should only happen if there's been some change to where this download page is located
        echo_err "Windows enterprise evaluation download page gave us an empty response"
        return 1
    fi

    iso_download_links="$(echo "$iso_download_page_html" | grep -o "https://go.microsoft.com/fwlink/p/?LinkID=[0-9]\+&clcid=0x[0-9a-z]\+&culture=en-us&country=US")" || {
        # This should only happen if there's been some change to the download endpoint web address
        echo_err "Windows enterprise evaluation download page gave us no download link"
        return 1
    }

    # Limit untrusted size for input validation
    iso_download_links="$(echo "$iso_download_links" | head -c 1024)"

    case "$enterprise_type" in
        # Select x64 download link
        "enterprise") iso_download_link=$(echo "$iso_download_links" | head -n 2 | tail -n 1) ;;
        # Select x64 LTSC download link
        "ltsc") iso_download_link=$(echo "$iso_download_links" | head -n 4 | tail -n 1) ;;
        *) iso_download_link="$iso_download_links" ;;
    esac

    # Follow redirect so proceeding log message is useful
    # This is a request we make this Fido doesn't
    # We don't need to set "--max-filesize" here because this is a HEAD request and the output is to /dev/null anyway
    iso_download_link="$(curl -sS --location --output /dev/null --silent --write-out "%{url_effective}" --head --fail --proto =https --tlsv1.2 --http1.1 -- "$iso_download_link")" || {
        # This should only happen if the Microsoft servers are down
        handle_curl_error $?
        return $?
    }

    # Limit untrusted size for input validation
    iso_download_link="$(echo "$iso_download_link" | head -c 1024)"

    #echo_ok "Got latest ISO download link: $iso_download_link"

    # Use highest TLS version for endpoints that support it
    case "$iso_download_link" in
        "https://download.microsoft.com"*) tls_version="1.2" ;;
        *) tls_version="1.3" ;;
    esac

    # Download ISO
    scurl_file "$out_file" "$tls_version" "$iso_download_link"
}

download_media() {
    echo_info "Downloading Windows media from official Microsoft servers..."

    media_download_failed_list=""

    for media in $media_list; do
        case "$media" in
            "$win7x64_ultimate")
                echo_info "Downloading Windows 7..."
                # Source, Google search this (it can be found many places): "dec04cbd352b453e437b2fe9614b67f28f7c0b550d8351827bc1e9ef3f601389" "download.microsoft.com"
                # This Windows 7 ISO bundles MSU update packages
                # It's the most up-to-date Windows 7 ISO that Microsoft offers (August 2018 update): https://files.rg-adguard.net/files/cea4210a-3474-a17a-88d4-4b3e10bd9f66
                # Of particular interest to us is the update that adds support for SHA-256 driver signatures so Qubes Windows Tools installs correctly
                #
                # Microsoft purged Windows 7 from all their servers...
                # More info about this event: https://github.com/pbatard/Fido/issues/64
                # Luckily, the ISO is still available on the Wayback Machine so get the last copy of it from there
                # This is still secure because we validate with the checksum from before the purge
                # The only con then is that web.archive.org is a much slower download source than the Microsoft servers
                echo_info "Microsoft has unfortunately purged all downloads of Windows 7 from their servers so this identical download is sourced from: web.archive.org"
                scurl_file "$media" "1.3" "https://web.archive.org/web/20221228154140/https://download.microsoft.com/download/5/1/9/5195A765-3A41-4A72-87D8-200D897CBE21/7601.24214.180801-1700.win7sp1_ldr_escrow_CLIENT_ULTIMATE_x64FRE_en-us.iso"
                ;;
            "$win81x64")
                echo_info "Downloading Windows 8.1..."
                consumer_download "$media" 8
                ;;
            "$win10x64")
                echo_info "Downloading Windows 10..."
                consumer_download "$media" 10
                ;;
            "$win11x64")
                echo_info "Downloading Windows 11..."
                consumer_download "$media" 11
                ;;

            "$win81x64_enterprise_eval")
                echo_info "Downloading Windows 8.1 Enterprise Evaluation..."
                # This download link is "Update 1": https://files.rg-adguard.net/file/166cbcab-1647-53d5-1785-6ef9e22a6500
                # A more up-to-date "Update 3" enterprise ISO exists but it was only ever distributed by Microsoft through MSDN which means it's impossible to get a Microsoft download link now: https://files.rg-adguard.net/file/549a58f2-7813-3e77-df6c-50609bc6dd7c
                # win81x64 is "Update 3" but that's isn't an enterprise version (although technically it's possible to modify a few files in the ISO to get any edition)
                # If you want "Update 3" enterprise though (not from Microsoft servers), then you should still be able to get it from here: https://archive.org/details/en_windows_8.1_enterprise_with_update_x64_dvd_6054382_202110
                # "Update 1" enterprise also seems to be the ISO used by other projects
                # Old source, used to be here but Microsoft deleted it: http://technet.microsoft.com/en-us/evalcenter/hh699156.aspx
                # Source: https://gist.github.com/eyecatchup/11527136b23039a0066f
                scurl_file "$media" "1.2" "https://download.microsoft.com/download/B/9/9/B999286E-0A47-406D-8B3D-5B5AD7373A4A/9600.17050.WINBLUE_REFRESH.140317-1640_X64FRE_ENTERPRISE_EVAL_EN-US-IR3_CENA_X64FREE_EN-US_DV9.ISO"
                ;;
            "$win10x64_enterprise_eval")
                echo_info "Downloading Windows 10 Enterprise Evaluation..."
                enterprise_eval_download "$media" windows-10-enterprise enterprise
                ;;
            "$win11x64_enterprise_eval")
                echo_info "Downloading Windows 11 Enterprise Evaluation..."
                enterprise_eval_download "$media" windows-11-enterprise enterprise
                ;;
            "$win10x64_enterprise_ltsc_eval")
                echo_info "Downloading Windows 10 Enterprise LTSC Evaluation..."
                enterprise_eval_download "$media" windows-10-enterprise ltsc
                ;;

            "$win2008r2")
                echo_info "Downloading Windows Server 2008 R2..."
                # Old source, used to be here but Microsoft deleted it: https://www.microsoft.com/en-us/download/details.aspx?id=11093
                # Microsoft took down the original download link provided by that source too but this new one has the same checksum
                # Source: https://github.com/rapid7/metasploitable3/pull/563
                scurl_file "$media" "1.2" "https://download.microsoft.com/download/4/1/D/41DEA7E0-B30D-4012-A1E3-F24DC03BA1BB/7601.17514.101119-1850_x64fre_server_eval_en-us-GRMSXEVAL_EN_DVD.iso"
                ;;
            "$win2012r2_eval")
                echo_info "Downloading Windows Server 2012 R2 Evaluation..."
                enterprise_eval_download "$media" windows-server-2012-r2 server
                ;;
            "$win2016_eval")
                echo_info "Downloading Windows Server 2016 Evaluation..."
                enterprise_eval_download "$media" windows-server-2016 server
                ;;
            "$win2019_eval")
                echo_info "Downloading Windows Server 2019 Evaluation..."
                enterprise_eval_download "$media" windows-server-2019 server
                ;;
            "$win2022_eval")
                echo_info "Downloading Windows Server 2022 Evaluation..."
                enterprise_eval_download "$media" windows-server-2022 server
                ;;
        esac || {
            error_action=$?
            media_download_failed_list="$media_download_failed_list $media"
            # Return immediately on a fatal error action
            if [ "$error_action" = 2 ]; then
                return
            fi
        }
    done
}

verify_media() {
    # SHA256SUMS file
    # Some of these Windows ISOs are EOL (e.g. win81x64) so their checksums will always match
    # For all other Windows ISOs, a new release will make their checksums no longer match
    #
    # IMPORTANT: These checksums are not necessarily subject to being updated
    # Unfortunately, the maintenance burden would be too large and even if I did there would still be some time gap between Microsoft releasing a new ISO and me updating the checksum (also, users would have to update this script)
    # For these reasons, I've opted for a slightly more manual verification where you have to look up the checksum to see if it's a well-known Windows ISO checksum
    # Ultimately, you have to trust Microsoft because they could still include a backdoor in the verified ISO (keeping Windows air gapped could help with this)
    # Community contributions for these checksums are welcome
    #
    # Leading backslash is to avoid prepending a newline while maintaining alignment
    readonly sha256sums="\
dec04cbd352b453e437b2fe9614b67f28f7c0b550d8351827bc1e9ef3f601389  win7x64-ultimate.iso
d8333cf427eb3318ff6ab755eb1dd9d433f0e2ae43745312c1cd23e83ca1ce51  win81x64.iso
# Windows 10 22H2
a6f470ca6d331eb353b815c043e327a347f594f37ff525f17764738fe812852e  win10x64.iso
# Windows 11 23H2 v2
36de5ecb7a0daa58dce68c03b9465a543ed0f5498aa8ae60ab45fb7c8c4ae402  win11x64.iso
2dedd44c45646c74efc5a028f65336027e14a56f76686a4631cf94ffe37c72f2  win81x64-enterprise-eval.iso
ef7312733a9f5d7d51cfa04ac497671995674ca5e1058d5164d6028f0938d668  win10x64-enterprise-eval.iso
ebbc79106715f44f5020f77bd90721b17c5a877cbc15a3535b99155493a1bb3f  win11x64-enterprise-eval.iso
e4ab2e3535be5748252a8d5d57539a6e59be8d6726345ee10e7afd2cb89fefb5  win10x64-enterprise-ltsc-eval.iso
30832ad76ccfa4ce48ccb936edefe02079d42fb1da32201bf9e3a880c8ed6312  win2008r2.iso
6612b5b1f53e845aacdf96e974bb119a3d9b4dcb5b82e65804ab7e534dc7b4d5  win2012r2-eval.iso
1ce702a578a3cb1ac3d14873980838590f06d5b7101c5daaccbac9d73f1fb50f  win2016-eval.iso
6dae072e7f78f4ccab74a45341de0d6e2d45c39be25f1f5920a2ab4f51d7bcbb  win2019-eval.iso
3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325  win2022-eval.iso"

    # Read sha256sums line-by-line to build known checksum and media lists
    # Only use shell builtins for better security and stability
    # Don't use a for loop because IFS cannot temporarily be set using that
    while IFS="$(printf '\n')" read -r line; do
        # Ignore comments and empty lines
        case "$line" in
            "#"* | "") continue ;;
        esac

        # Read first and second words of line
        IFS=' ' read -r known_checksum known_media _ << EOF
$line
EOF

        known_checksum_list="$known_checksum_list $known_checksum"
        known_media_list="$known_media_list $known_media"
    done << EOF
$sha256sums
EOF

    media_verification_failed_list=""
    checksum_verification_failed_list=""

    for media in $media_list; do
        # Scan for unverified media files
        if ! [ -f "${media}${unverified_ext}" ]; then
            continue
        fi

        if [ "$verify_media_message_shown" != "true" ]; then
            echo_info "Verifying integrity..."
            verify_media_message_shown="true"
        fi

        checksum_line="$(sha256sum "${media}${unverified_ext}")"
        # Get first word of checksum line
        IFS=' ' read -r checksum _ << EOF
$checksum_line
EOF

        # Sanity check: Assert correct size of SHA-256 checksum
        if [ ${#checksum} != 64 ]; then
            echo_err "Failed SHA-256 sanity check! Exiting..."
            exit 2
        fi

        known_checksum_list_iterator="$known_checksum_list"

        # Search known media and checksum lists for the current media
        for known_media in $known_media_list; do
            IFS=' ' read -r known_checksum known_checksum_list_iterator << EOF
$known_checksum_list_iterator
EOF

            if [ "$media" = "$known_media" ]; then
                break
            fi
        done

        # Verify current media integrity
        if [ "$checksum" = "$known_checksum" ]; then
            echo "$media: OK"
            mv "${media}${unverified_ext}" "$media"
        else
            echo "$media: UNVERIFIED"
            media_verification_failed_list="$media_verification_failed_list $media"
            checksum_verification_failed_list="$checksum_verification_failed_list $checksum"
        fi

        # Reset known checksum list iterator so we can iterate on it again for the next media
        known_checksum_list_iterator="$known_checksum_list"
    done
}

ending_summary() {
    echo "" >&2

    if [ "$media_download_failed_list" ]; then
        for media in $media_download_failed_list; do
            media_download_failed_argument_list="$media_download_failed_argument_list ${media%%.iso}"
        done
    fi

    # Exit codes
    # 0: Success
    # 1: Argument parsing error
    # 2: Runtime error (see error message for more info)
    # 3: One or more downloads failed
    # 4: One or more verifications failed
    # 5: At least one download and one verification failed (when more than one media is specified)

    exit_code=0

    # Determine exit code
    if [ "$media_download_failed_list" ] && [ "$media_verification_failed_list" ]; then
        exit_code=5
    else
        if [ "$media_download_failed_list" ]; then
            exit_code=3
        elif [ "$media_verification_failed_list" ]; then
            exit_code=4
        fi
    fi

    trap -- - EXIT

    if [ "$exit_code" = 0 ]; then
        echo_ok "Successfully downloaded Windows image!"
    else
        echo_ok "Finished! Please see the above errors with information"
        exit "$exit_code"
    fi
}

# https://unix.stackexchange.com/questions/752570/why-does-trap-passthough-zero-instead-of-the-signal-the-process-was-killed-wit
handle_exit() {
    exit_code=$?
    signal="$1"

    if [ "$exit_code" != 0 ] || [ "$signal" ]; then
        echo "" >&2
        echo_err "Mido was exited abruptly!"
    fi

    if [ "$exit_code" != 0 ]; then
        trap -- - EXIT
        exit "$exit_code"
    elif [ "$signal" ]; then
        trap -- - "$signal"
        kill -s "$signal" -- $$
    fi
}

# Enable exiting on error
#
# Disable shell globbing
# This isn't necessary given that all unquoted variables (e.g. for determining word count) are set directly by us but it's just a precaution
set -ef

# IFS defaults to many different kinds of whitespace but we only care about space
# Note: This means that ISO filenames cannot contain spaces but that's a bad idea anyway
IFS=' '

parse_args "$@"

# POSIX sh doesn't include signals in its EXIT trap so do it ourselves
signo=1
while true; do
    # "kill" is a shell builtin
    # shellcheck disable=SC2064
    case "$(kill -l "$signo" 2> /dev/null)" in
        # Trap on all catchable terminating signals as defined by POSIX
        # Stop (i.e. suspend) signals (like Ctrl + Z or TSTP) are fine because they can be resumed
        # Most signals result in termination so this way is easiest (Linux signal(7) only adds more terminating signals)
        #
        # https://pubs.opengroup.org/onlinepubs/009695399/basedefs/signal.h.html
        # https://unix.stackexchange.com/a/490816
        # Signal WINCH was recently added to POSIX: https://austingroupbugs.net/view.php?id=249
        CHLD | CONT | URG | WINCH | KILL | STOP | TSTP | TTIN | TTOU) ;;
        *) trap "handle_exit $signo" "$signo" 2> /dev/null || break ;;
    esac

    signo=$((signo + 1))
done
trap handle_exit EXIT

download_media
verify_media
ending_summary
