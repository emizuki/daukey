#!/bin/bash
set -euo pipefail

install=false
case $# in
    0) ;;
    1)
        if [[ $1 == --install ]]; then
            install=true
        else
            printf 'Usage: %s [--install]\n' "$0" >&2
            exit 2
        fi
        ;;
    *)
        printf 'Usage: %s [--install]\n' "$0" >&2
        exit 2
        ;;
esac

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repository_root"
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
identity=${DAUKEY_SIGN_IDENTITY:-DauKey Local}

if ! xcrun --find actool > /dev/null 2>&1; then
    printf 'Xcode is required to build the DauKey bundle: actool was not found. Install Xcode and select it with xcode-select.\n' >&2
    exit 1
fi

# A dash explicitly requests ad-hoc signing; never choose it automatically.
if [[ $identity != - ]]; then
    if ! identities=$(security find-identity -v -p codesigning); then
        printf 'Could not query code-signing identities with security find-identity. Unlock the keychain and retry, or explicitly set DAUKEY_SIGN_IDENTITY=- for ad-hoc signing.\n' >&2
        exit 1
    fi
    identity_found=false
    identity_pattern='^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"(.*)"$'
    while IFS= read -r line; do
        if [[ $line =~ $identity_pattern ]]; then
            if [[ $identity == "${BASH_REMATCH[1]}" || $identity == "${BASH_REMATCH[2]}" ]]; then
                identity_found=true
                break
            fi
        fi
    done <<< "$identities"
    if [[ $identity_found == false ]]; then
        printf 'Signing identity "%s" was not found. Run scripts/make-signing-cert.sh, or set DAUKEY_SIGN_IDENTITY=- for ad-hoc signing.\n' "$identity" >&2
        exit 1
    fi
fi

swift build -c release --product daukey
binary_directory=$(swift build -c release --show-bin-path)
bundle="$repository_root/.build/DauKey.app"
rm -rf -- "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_directory/daukey" "$bundle/Contents/MacOS/daukey"
cp "$repository_root/Sources/DauKey/Info.plist" "$bundle/Contents/Info.plist"
partial_info_plist=$(mktemp "${TMPDIR:-/tmp}/daukey-icon-info.XXXXXX")
trap 'rm -f -- "$partial_info_plist"' EXIT
xcrun actool Sources/DauKey/AppIcon.icon \
    --compile "$bundle/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$partial_info_plist"
codesign --force --options runtime --sign "$identity" --requirements '=designated => identifier "com.emizuki.daukey"' "$bundle"
codesign --verify --strict "$bundle"
codesign -d -r- "$bundle"

if [[ $install == true ]]; then
    if pgrep -x daukey > /dev/null; then
        pkill -TERM -x daukey || true
        for ((attempt = 0; attempt < 5; attempt++)); do
            if ! pgrep -x daukey > /dev/null; then
                break
            fi
            sleep 1
        done
        if pgrep -x daukey > /dev/null; then
            printf 'DauKey did not exit within 5 seconds. Close it before installing again.\n' >&2
            exit 1
        fi
    fi
    rm -rf -- /Applications/DauKey.app
    ditto "$bundle" /Applications/DauKey.app
    open /Applications/DauKey.app
fi
