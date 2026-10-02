#!/usr/bin/env bash
# Bsn Palm - instalador (Linux, macOS e Windows pelo WSL2).
#
#   curl -fsSL https://getpalm.bsnsolution.com.br/install.sh | bash
#   curl -fsSL https://getpalm.bsnsolution.com.br/install.sh | bash -s -- --license=SEU-CODIGO
#
# Garante Node 22, git e compiladores, troca a sua LICENCA por um link de
# download temporario, baixa o pacote (conferindo o sha256), instala o comando
# `bsn-palm` e chama o setup interativo (`bsn-palm setup`), que sobe o resto:
# WhatsApp (WAHA), Firecrawl, Whisper, HTTPS, servico... O motor de IA e o da
# pessoa (Claude Code/Codex opcionais, ou a chave de API de qualquer provedor,
# cadastrada no painel). Nada aponta para servidores da BSN alem deste getpalm
# (licenca e download); servicos da BSN (ex.: BSN Voz) sao opcionais, no painel.
# Pode rodar de novo quantas vezes quiser: so mexe no que falta.
# Tambem funciona sem terminal (CI, ssh sem -t): o setup usa as respostas padrao.
set -euo pipefail

# ============================================================================
# DISTRIBUICAO
#   BSN_PALM_DIST_BASE  servidor de distribuicao (instaladores publicos + troca
#                       licenca -> link temporario). Nunca o palm.bsnsolution
#                       (essa e a instancia pessoal).
#   BSN_PALM_LICENSE    licenca (ou --license=...; sem ela, o instalador pergunta)
# De onde vem o codigo (resolve_download):
#   release (padrao)    licenca -> link temporario no DIST_BASE -> pacote + sha256
#   BSN_PALM_TARBALL    (dev) pacote local ou URL, com .sha256 ao lado ou BSN_PALM_SHA256
#   BSN_PALM_REPO       (dev) git clone de uma pasta local ou do repositorio privado
# ============================================================================
DIST_BASE="${BSN_PALM_DIST_BASE:-${BSN_PALM_DIST_URL:-https://getpalm.bsnsolution.com.br}}"
LICENSE="${BSN_PALM_LICENSE:-}"
REPO="${BSN_PALM_REPO:-}"
BRANCH="${BSN_PALM_BRANCH:-}"          # vazio = branch padrao do repositorio
VERSION="${BSN_PALM_VERSION:-latest}"  # release: versao fixa ou latest
NODE_MAJOR=22

# --license=X / --license X: fica aqui e segue para o setup (que guarda) pela variavel
# BSN_PALM_LICENSE, nunca na linha de comando (o ps mostra os argumentos a qualquer usuario).
SETUP_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --license=*) LICENSE="${1#--license=}" ;;
    --license) shift; LICENSE="${1:-}" ;;
    *) SETUP_ARGS+=("$1") ;;
  esac
  shift
done

if [ "$(id -u)" = "0" ]; then DIR="${BSN_PALM_DIR:-/opt/bsn-palm}"; SUDO=""; else DIR="${BSN_PALM_DIR:-$HOME/bsn-palm}"; SUDO="sudo"; fi
STATE="${BSN_PALM_HOME:-$DIR}"

say() { printf '\033[1;32m●\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

node_ok() { command -v node >/dev/null 2>&1 && node -e "process.exit(+process.versions.node.split('.')[0] >= $NODE_MAJOR ? 0 : 1)"; }
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

if [ -n "$SUDO" ] && ! command -v sudo >/dev/null 2>&1; then
  die "Este usuario nao e root e a maquina nao tem sudo. Rode como root (su -) ou instale o sudo."
fi

# ---------------------------------------------------------------- sistema ---
OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    say "Instalando o Homebrew (necessario no macOS)..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  command -v git >/dev/null 2>&1 || brew install git
  if ! node_ok; then
    say "Instalando o Node.js $NODE_MAJOR..."
    brew install "node@$NODE_MAJOR"
    brew link --overwrite --force "node@$NODE_MAJOR" 2>/dev/null || true
    NODE_PREFIX="$(brew --prefix "node@$NODE_MAJOR")"
    export PATH="$NODE_PREFIX/bin:$PATH"
  fi
elif [ "$OS" = "Linux" ]; then
  # bubblewrap (bwrap): os motores CLI (Codex, OpenCode, Cursor...) so rodam isolados do sistema neste
  # pacote -- disco so leitura, segredos ocultos. Sem ele, ficam desligados (o Claude e o Palm Lite seguem).
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates python3 make g++ tar gzip
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y bubblewrap || warn "Nao consegui instalar o bubblewrap: os motores CLI ficam desligados."
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y git curl python3 make gcc-c++ tar gzip
    $SUDO dnf install -y bubblewrap || warn "Nao consegui instalar o bubblewrap: os motores CLI ficam desligados."
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y git curl python3 make gcc-c++ tar gzip
    $SUDO yum install -y bubblewrap || warn "Nao consegui instalar o bubblewrap: os motores CLI ficam desligados."
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add git curl bash python3 make g++ tar gzip
    $SUDO apk add bubblewrap || warn "Nao consegui instalar o bubblewrap: os motores CLI ficam desligados."
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -S --noconfirm --needed git curl python make gcc tar gzip
    $SUDO pacman -S --noconfirm --needed bubblewrap || warn "Nao consegui instalar o bubblewrap: os motores CLI ficam desligados."
  fi
  if ! node_ok; then
    say "Instalando o Node.js $NODE_MAJOR..."
    if command -v apt-get >/dev/null 2>&1; then
      curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | $SUDO bash -
      $SUDO apt-get install -y nodejs
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
      curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | $SUDO bash -
      $SUDO "$(command -v dnf || command -v yum)" install -y nodejs
    else
      die "Instale o Node.js $NODE_MAJOR+ manualmente e rode este instalador de novo."
    fi
  fi
else
  die "Sistema $OS nao suportado. No Windows, use o instalador do Windows (install.ps1): ele prepara o WSL2 e roda este aqui dentro."
fi
node_ok || die "O Node.js $NODE_MAJOR nao ficou disponivel. Abra um terminal novo e rode o instalador de novo."

# ------------------------------------------------------------ o Bsn Palm ---
prepare_dir() {
  [ -d "$DIR" ] && return
  # Sem sudo quando da (pasta do usuario); com sudo so para /opt e afins.
  mkdir -p "$DIR" 2>/dev/null && return
  $SUDO mkdir -p "$DIR"
  if [ -n "$SUDO" ]; then $SUDO chown "$(id -u):$(id -g)" "$DIR"; fi
}

install_from_git() {
  local auth=()
  if [ -n "${BSN_PALM_GIT_TOKEN:-}" ]; then
    auth=(-c "http.extraHeader=Authorization: Basic $(printf 'x-access-token:%s' "$BSN_PALM_GIT_TOKEN" | base64 | tr -d '\n')")
  fi
  if [ -d "$DIR/.git" ]; then
    say "Atualizando $DIR..."
    git ${auth[@]+"${auth[@]}"} -C "$DIR" pull --ff-only
  else
    say "Baixando o Bsn Palm em $DIR (modo desenvolvimento: $REPO)..."
    if [ -d "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
      die "$DIR ja existe e nao e um clone do git. Use outra pasta (BSN_PALM_DIR=...)."
    fi
    prepare_dir
    if ! git ${auth[@]+"${auth[@]}"} clone ${BRANCH:+--branch "$BRANCH"} "$REPO" "$DIR"; then
      die "Nao consegui baixar $REPO."
    fi
  fi
  cd "$DIR"
  say "Instalando dependencias e compilando..."
  npm ci --no-audit --no-fund
  npm run build
  git rev-parse HEAD > dist/.build-rev
}

# Licenca: argumento/variavel, a ja guardada nesta maquina (update), ou pergunta.
resolve_license() {
  if [ -z "$LICENSE" ] && [ -f "$STATE/ops/bsn-palm.env" ]; then
    LICENSE="$(sed -n 's/^PALM_LICENSE=//p' "$STATE/ops/bsn-palm.env" | tail -1 | tr -d '"'"'"' ')"
  fi
  if [ -z "$LICENSE" ] && { true </dev/tty; } 2>/dev/null; then
    printf '  ? Codigo da sua licenca do Bsn Palm (quem liberou o acesso te enviou): ' >/dev/tty
    IFS= read -r LICENSE </dev/tty || true
    LICENSE="$(printf '%s' "$LICENSE" | tr -d '[:space:]')"
  fi
  [ -n "$LICENSE" ] || die "Falta a licenca. Rode de novo passando o codigo: curl -fsSL $DIST_BASE/install.sh | bash -s -- --license=SEU-CODIGO  (Homebrew/Windows: bsn-palm setup --license=SEU-CODIGO)"
}

# Decide DE ONDE vem o pacote. Preenche PKG_SRC (arquivo local ou URL), PKG_SHA (sha256 esperado)
# e PKG_VER (versao, ou vazio = ler de dentro do pacote).
resolve_download() {
  PKG_SRC=""; PKG_SHA="${BSN_PALM_SHA256:-}"; PKG_VER=""
  if [ -n "${BSN_PALM_TARBALL:-}" ]; then
    # Modo desenvolvimento: pacote gerado pelo ops/distribution/make-release.sh.
    PKG_SRC="$BSN_PALM_TARBALL"
    if [ -z "$PKG_SHA" ]; then
      if [ -f "$PKG_SRC.sha256" ]; then PKG_SHA="$(awk '{print $1}' "$PKG_SRC.sha256")"
      else PKG_SHA="$(curl -fsSL --retry 3 "$PKG_SRC.sha256" 2>/dev/null | awk '{print $1}')" || true; fi
    fi
    [ -n "$PKG_SHA" ] || die "Sem sha256 para $PKG_SRC (ponha $PKG_SRC.sha256 ao lado ou defina BSN_PALM_SHA256)."
    return
  fi
  resolve_license
  # getpalm -- POST $DIST_BASE/api/v1/download
  #   pede:     {"license","version","os","arch","installId"}
  #   devolve:  200 {"url": "<link temporario, vence em minutos>", "sha256", "version", "signature"}
  #             401/403 {"error": "licenca invalida | desativada | expirada"}
  local os arch install_id resp
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  install_id="$( [ -f "$STATE/ops/bsn-palm.env" ] && sed -n 's/^PALM_INSTALL_ID=//p' "$STATE/ops/bsn-palm.env" | tail -1 || true)"
  # O corpo (com a licenca) vai pelo stdin do curl e o node le a licenca do ambiente: nada dela
  # nos argumentos do node nem do curl.
  resp="$(BSN_PALM_LICENSE="$LICENSE" node -e 'console.log(JSON.stringify({license:process.env.BSN_PALM_LICENSE,version:process.argv[1],os:process.argv[2],arch:process.argv[3],installId:process.argv[4]||undefined}))' "$VERSION" "$os" "$arch" "$install_id" \
    | curl -sS --retry 2 -w '\n%{http_code}' -X POST "$DIST_BASE/api/v1/download" \
      -H 'Content-Type: application/json' --data-binary @- 2>/dev/null)" \
    || die "Nao consegui falar com $DIST_BASE. Confira a internet e tente de novo."
  local code="${resp##*$'\n'}" body="${resp%$'\n'*}"
  case "$code" in
    200) ;;
    401|403) die "Licenca recusada: $(printf '%s' "$body" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).error||s)}catch{console.log(s)}})'). Fale com quem te enviou a licenca." ;;
    404|405|501) die "A distribuicao por licenca ainda nao esta no ar em $DIST_BASE. Para testar: BSN_PALM_TARBALL=<pacote> ou BSN_PALM_REPO=<pasta do codigo>." ;;
    *) die "O servidor de distribuicao respondeu $code. Tente de novo em alguns minutos." ;;
  esac
  local sig
  read -r PKG_SRC PKG_SHA PKG_VER sig < <(printf '%s' "$body" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log([j.url,j.sha256,j.version||"-",j.signature||"-"].join(" "))})') \
    || die "Resposta invalida do servidor de distribuicao."
  [ "$PKG_VER" = "-" ] && PKG_VER=""
  [ -n "$PKG_SRC" ] && [ -n "$PKG_SHA" ] || die "Resposta invalida do servidor de distribuicao (sem url/sha256)."
  verify_release_signature "$PKG_VER" "$PKG_SHA" "$sig"
}

# Chave publica do servidor de distribuicao (a mesma que assina as licencas; src/license/license.ts
# HUB_PUBLIC_KEY). O hub assina "palm-release:v1:<versao>:<sha256>": uma resposta falsa de
# download (DNS ou proxy trocado) nao consegue apontar para outro pacote. Sem assinatura
# valida, nada e instalado (revisao 24/09).
HUB_RELEASE_PUBKEY="${BSN_PALM_RELEASE_PUBKEY:-MCowBQYDK2VwAyEACGHqs+e4Vz6S7zXR568Tgjavw9fo1bfCVyJUZHyzGb0=}"
verify_release_signature() {
  local ver="$1" sha="$2" sig="$3"
  [ -n "$ver" ] && [ -n "$sig" ] && [ "$sig" != "-" ] \
    || die "O servidor de distribuicao nao assinou este pacote. Por seguranca nada foi instalado; fale com a BSN."
  node -e '
    const c = require("crypto");
    const [pk, ver, sha, sig] = process.argv.slice(1);
    try {
      const key = c.createPublicKey({ key: Buffer.from(pk, "base64"), format: "der", type: "spki" });
      process.exit(c.verify(null, Buffer.from(`palm-release:v1:${ver}:${sha.toLowerCase()}`), key, Buffer.from(sig, "base64")) ? 0 : 1);
    } catch { process.exit(1); }
  ' "$HUB_RELEASE_PUBKEY" "$ver" "$sha" "$sig" \
    || die "A assinatura do pacote nao confere (resposta de download adulterada?). Nada foi instalado."
}

# Baixa (ou copia) o pacote, confere o sha256 e troca so o codigo; dados e segredos ficam.
install_package() {
  local tmp ver
  if [ -n "$PKG_VER" ] && [ -f "$DIR/.bsn-palm-release" ] && [ "$(cat "$DIR/.bsn-palm-release")" = "$PKG_VER" ] && [ -d "$DIR/node_modules" ]; then
    say "Bsn Palm $PKG_VER ja instalado em $DIR."
    cd "$DIR"
    return
  fi
  tmp="$(mktemp -d)"
  say "Baixando o Bsn Palm${PKG_VER:+ $PKG_VER}..."
  case "$PKG_SRC" in
    http://*|https://*) curl -fsSL --retry 3 -o "$tmp/pkg.tar.gz" "$PKG_SRC" || die "Falha no download (o link temporario pode ter vencido; rode de novo)." ;;
    *) cp "$PKG_SRC" "$tmp/pkg.tar.gz" || die "Nao achei o pacote $PKG_SRC." ;;
  esac
  if [ "$PKG_SHA" != "$(sha256 "$tmp/pkg.tar.gz")" ]; then
    rm -rf "$tmp"
    die "O arquivo baixado nao confere com o sha256 esperado (download corrompido ou adulterado). Nada foi instalado."
  fi
  mkdir -p "$tmp/x"
  tar -xzf "$tmp/pkg.tar.gz" -C "$tmp/x"
  [ -f "$tmp/x/bsn-palm/dist/setup/cli.js" ] || die "Pacote invalido (sem dist/setup/cli.js)."
  ver="$(cat "$tmp/x/bsn-palm/.bsn-palm-release" 2>/dev/null || echo '?')"
  if [ -f "$DIR/.bsn-palm-release" ] && [ "$(cat "$DIR/.bsn-palm-release")" = "$ver" ] && [ -d "$DIR/node_modules" ]; then
    say "Bsn Palm $ver ja instalado em $DIR."
    rm -rf "$tmp"
    cd "$DIR"
    return
  fi
  prepare_dir
  rm -rf "$DIR/dist" "$DIR/web/dist"
  cp -R "$tmp/x/bsn-palm/." "$DIR/"
  rm -rf "$tmp"
  cd "$DIR"
  say "Instalando dependencias do Bsn Palm $ver..."
  npm ci --omit=dev --no-audit --no-fund
}

if [ -n "$REPO" ]; then
  install_from_git
else
  resolve_download
  install_package
fi
# Licenca para o setup: pela variavel (fora do ps). O setup le BSN_PALM_LICENSE desde a 0.4.2;
# pacote mais velho (ex.: BSN_PALM_VERSION fixa numa versao antiga) recebe o --license= de antes.
setup_reads_license_env() {
  node -e 'const v=String(require(process.argv[1]).version||"0").split(/[.-]/).map(Number);process.exit((v[0]||0)*1e6+(v[1]||0)*1e3+(v[2]||0)>=4002?0:1)' "$DIR/package.json" 2>/dev/null
}
if [ -n "$LICENSE" ]; then
  export BSN_PALM_LICENSE="$LICENSE"
  setup_reads_license_env || SETUP_ARGS+=("--license=$LICENSE")
fi

# ------------------------------------------------- comando bsn-palm no PATH --
NODE_BIN="$(command -v node)"
if [ -n "${BSN_PALM_NO_WRAPPER:-}" ]; then BIN_DIR=""; fi
WRAPPER="#!/usr/bin/env bash
exec \"$NODE_BIN\" \"$DIR/dist/setup/cli.js\" \"\$@\"
"
if [ -n "${BSN_PALM_NO_WRAPPER:-}" ]; then
  :
elif [ -z "$SUDO" ] || [ -w /usr/local/bin ]; then
  BIN_DIR=/usr/local/bin
  mkdir -p "$BIN_DIR"
  printf '%s' "$WRAPPER" > "$BIN_DIR/bsn-palm"
  chmod 755 "$BIN_DIR/bsn-palm"
else
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
  printf '%s' "$WRAPPER" > "$BIN_DIR/bsn-palm"
  chmod 755 "$BIN_DIR/bsn-palm"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        [ -f "$rc" ] || continue
        # shellcheck disable=SC2016 # $HOME/$PATH are meant to expand when the rc file runs
        grep -q '.local/bin' "$rc" 2>/dev/null || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
      done
      ;;
  esac
fi
[ -n "$BIN_DIR" ] && say "Comando instalado: $BIN_DIR/bsn-palm (bsn-palm setup | doctor | update)"

# ---------------------------------------------------------------- setup ----
say "Chamando o setup..."
# stdin do terminal (nao do curl), para as perguntas funcionarem com "curl | bash".
# Testa abrindo de fato: sem terminal (CI, ssh sem -t) o /dev/tty existe mas nao abre.
if { true </dev/tty; } 2>/dev/null; then
  exec "$NODE_BIN" "$DIR/dist/setup/cli.js" setup ${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"} </dev/tty
else
  warn "Sem terminal interativo: o setup vai usar as respostas padrao. Depois rode 'bsn-palm setup' num terminal para completar."
  exec "$NODE_BIN" "$DIR/dist/setup/cli.js" setup ${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}
fi
