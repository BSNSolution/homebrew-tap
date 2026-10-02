# Formula do Bsn Palm para o tap bsnsolution/tap (repositorio GitHub
# BSNSolution/homebrew-tap, arquivo Formula/bsn-palm.rb).
#
#   brew install bsnsolution/tap/bsn-palm
#   bsn-palm setup
#
# A formula instala so o INSTALADOR (o mesmo install.sh publico do getpalm) e o
# comando `bsn-palm`. O Bsn Palm em si vem pelo mesmo fluxo dos outros comandos:
# na primeira vez o `bsn-palm setup` pede a licenca, troca por um link temporario,
# baixa o pacote (sha256 conferido) em ~/bsn-palm e roda o setup. Assim nenhum
# pacote do Palm fica publico e os dados ficam fora da Cellar (um `brew upgrade`
# nunca apaga nada).
#
# O instalador fica no proprio tap (installers/), que e publico: e o mesmo install.sh
# publico do getpalm -- nenhum codigo do Palm vai para o repositorio do tap.
#
# @VERSION@, @SHA256@, @DIST_BASE@ e @INSTALLER_URL@ sao preenchidos por
# ops/distribution/make-release.sh (saida em dist-release/homebrew/bsn-palm.rb).
# E formula (nao cask) porque o Bsn Palm e um programa de linha de comando.
class BsnPalm < Formula
  desc "Agente pessoal de IA no WhatsApp e num painel web"
  homepage "https://getpalm.bsnsolution.com.br"
  url "https://raw.githubusercontent.com/BSNSolution/homebrew-tap/main/installers/bsn-palm-installer-0.4.3-866c770.sh"
  version "0.4.3-866c770"
  sha256 "20723715400c6fdde643dc712417ed58455f0766d2035e6d972d96cf6b313a3a"
  license :cannot_represent

  depends_on "ffmpeg"
  depends_on "git"
  depends_on "node@22"
  depends_on "poppler"

  def install
    libexec.install "bsn-palm-installer-#{version}.sh" => "install.sh"
    (bin/"bsn-palm").write <<~EOS
      #!/bin/bash
      export PATH="#{formula_opt_bin("node@22")}:$PATH"
      export BSN_PALM_DIST_BASE="${BSN_PALM_DIST_BASE:-https://getpalm.bsnsolution.com.br}"
      DIR="${BSN_PALM_DIR:-$HOME/bsn-palm}"
      if [ -f "$DIR/dist/setup/cli.js" ] && [ "${1:-}" != "update" ]; then
        exec node "$DIR/dist/setup/cli.js" "$@"
      fi
      # Primeira vez (ou update): o instalador pede a licenca, baixa o pacote e roda o setup.
      [ "${1:-}" = "update" ] && shift
      BSN_PALM_NO_WRAPPER=1 BSN_PALM_DIR="$DIR" exec bash "#{libexec}/install.sh" "$@"
    EOS
  end

  def caveats
    <<~EOS
      Para instalar e configurar (licenca, Claude, WhatsApp, painel e servico):
        bsn-palm setup

      Atualizar o Bsn Palm: bsn-palm update
    EOS
  end

  test do
    assert_path_exists libexec/"install.sh"
    system "bash", "-n", libexec/"install.sh"
  end
end
