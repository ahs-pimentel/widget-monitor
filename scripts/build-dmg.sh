#!/bin/zsh
# Gera dist/oDois-Monitor-<versão>.dmg com o app universal e atalho para /Applications.
#
# Com certificado "Developer ID Application" no keychain, assina o app e o DMG e
# notariza na Apple, para abrir em outros Macs sem aviso do Gatekeeper.
# Configuração única das credenciais de notarização (fica no keychain):
#   xcrun notarytool store-credentials odois-notary \
#     --apple-id <seu-apple-id> --team-id <TEAMID> --password <senha-de-app>
# Variáveis opcionais: SIGN_IDENTITY (força um certificado), NOTARY_PROFILE
# (padrão: odois-notary), NOTARIZE=0 (assina sem notarizar).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
NOTARY_PROFILE="${NOTARY_PROFILE:-odois-notary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
export SIGN_IDENTITY

UNIVERSAL=1 ./scripts/build-app.sh

APP="build/oDois Monitor.app"
mkdir -p dist
DMG="dist/oDois-Monitor-$VERSION.dmg"
TMP="$(mktemp -d)"
STAGE="$TMP/oDois Monitor"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "oDois Monitor $VERSION" -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -ov "$DMG" >/dev/null 2>&1
rm -rf "$TMP"

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "OK: $DMG ($(du -h "$DMG" | cut -f1)) — app com assinatura ad-hoc."
  echo "Aviso: sem Developer ID, outros Macs vão bloquear a primeira abertura (Gatekeeper)."
  exit 0
fi

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [[ "${NOTARIZE:-1}" == "0" ]]; then
  echo "OK: $DMG assinado, sem notarização (NOTARIZE=0)."
  exit 0
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "ERRO: perfil de notarização '$NOTARY_PROFILE' não encontrado no keychain." >&2
  echo "Crie com: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id <TEAMID> --password <senha-de-app>" >&2
  exit 1
fi

echo "Enviando para notarização (pode levar alguns minutos)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "OK: $DMG assinado, notarizado e grampeado ($(du -h "$DMG" | cut -f1))."
