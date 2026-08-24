#!/bin/zsh
# subir.sh [numero_de_build]
#
# Compila, archiva y sube a TestFlight sin depender de la sesión de Xcode.
#
# Por qué existe: durante dos días los uploads se cayeron con "Failed to
# Use Accounts" porque xcodebuild dejaba de ver la sesión de Apple ID —y
# la firma era EN LA NUBE, o sea que sin sesión no había con qué firmar.
# Ahora la firma usa el certificado local (Apple Distribution, en el
# llavero) y la subida una API key con rol Admin. Ninguna de las dos
# caduca sola.
set -e
cd "$(dirname "$0")/../../../../../../Users/felipe/Documents/GitHub/maratonia" 2>/dev/null || cd /Users/felipe/Documents/GitHub/maratonia

KEY_ID=U7G33S45YG
ISSUER=16931601-1b6c-457d-aee0-3863ac4598e2
KEY=~/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8
TMP=$(mktemp -d)

if [ -n "$1" ]; then
  ACTUAL=$(grep -o 'CURRENT_PROJECT_VERSION = [0-9]*' Maraton.xcodeproj/project.pbxproj | head -1 | grep -o '[0-9]*')
  sed -i '' "s/CURRENT_PROJECT_VERSION = $ACTUAL/CURRENT_PROJECT_VERSION = $1/g" Maraton.xcodeproj/project.pbxproj
  echo "build $ACTUAL -> $1"
fi

echo "▸ archivando…"
xcodebuild archive -project Maraton.xcodeproj -scheme Maraton \
  -destination 'generic/platform=iOS' -archivePath "$TMP/M.xcarchive" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" -authenticationKeyID $KEY_ID \
  -authenticationKeyIssuerID $ISSUER 2>&1 | grep -E '(error):|ARCHIVE (SUCCEEDED|FAILED)'

cat > "$TMP/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>2M7NJ8V37F</string>
  <key>uploadSymbols</key><true/>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

echo "▸ firmando…"
xcodebuild -exportArchive -archivePath "$TMP/M.xcarchive" -exportPath "$TMP/ipa" \
  -exportOptionsPlist "$TMP/export.plist" -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" -authenticationKeyID $KEY_ID \
  -authenticationKeyIssuerID $ISSUER 2>&1 | grep -E '(error):|EXPORT (SUCCEEDED|FAILED)'

echo "▸ subiendo…"
xcrun altool --upload-app -f "$TMP/ipa/Maraton.ipa" -t ios \
  --apiKey $KEY_ID --apiIssuer $ISSUER 2>&1 | grep -E 'UPLOAD|error'
rm -rf "$TMP"
