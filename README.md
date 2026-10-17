# Hades II — Coop Local

Mod experimental de cooperação local para dois jogadores em Hades II, baseado no trabalho de [TheNormalnij e Hades2-coop-project](https://github.com/Hades2-coop-project/hades2-coop).

## Estado do projeto

Este repositório contém um **snapshot de desenvolvimento do código-fonte**, não uma versão estável nem um pacote pronto para instalar. Ainda não há release instalável publicada aqui. As duas personagens usam Melínoe adulta e as mecânicas de Hades II.

O desenvolvimento inclui controles por jogador, câmera compartilhada, HUD da dupla, preparação no hub e ofertas de bênçãos pessoais. Os sorteios de bênçãos são independentes; a coleta física deve ser contabilizada uma única vez. A Jornada de Zagreus foi testada parcialmente, mas não há garantia de compatibilidade completa.

## Problemas conhecidos

- Recolor do jogador 2 ainda não aparece corretamente; a ligação entre o módulo nativo e Lua está em investigação.
- “Encerrar corrida” aparece durante uma corrida, mas a interação ainda falha. Não confundir com “Desfazer noite”.
- Algumas combinações de Caos ainda ficam bloqueadas; efeitos e expiração precisam de mais validação.
- Segurar certas ações carregadas ainda altera a câmera da dupla.
- Há relato de foco automático do jogador 2 no parceiro.
- O modo Duelo/Arena foi removido e está fora do escopo atual.

## Organização

| Pasta | Conteúdo |
| --- | --- |
| `snapshot/mod` | Scripts Lua do coop instalado na máquina de desenvolvimento |
| `snapshot/reward-runtime` | Runtime e módulos das recompensas pessoais |
| `snapshot/reward-ui` | Layout e modelos de texto usados pela interface de bênçãos |
| `native/upstream-coop` | Fontes da base nativa original, preservadas para referência |
| `native/pause` | Ponte nativa experimental do botão de encerrar corrida |
| `native/recolor` | Ponte nativa experimental de inspeção da textura pessoal |
| `docs` | Dependências, limitações do snapshot e instruções para contribuir |

Os caminhos específicos da máquina de desenvolvimento foram substituídos por `<WORKSPACE>`, `<HADES_II>` ou `<HADES_I>`. Os scripts de diagnóstico e de automação do computador não fazem parte deste export. Por isso, copiar estas pastas diretamente para o jogo não constitui uma instalação completa.

## Instalação e desenvolvimento

Para a instalação da base original, consulte as instruções e releases do [projeto upstream](https://github.com/Hades2-coop-project/hades2-coop). Este fork ainda precisa concluir o empacotamento portátil das adaptações antes de oferecer seu próprio instalador.

Leia [as notas de desenvolvimento](docs/DEVELOPMENT.md) antes de compilar. Não substitua DLLs ou scripts com o jogo aberto. Preserve seus saves e teste mudanças de desenvolvimento em um perfil separado.

## Créditos e licença

Base original: Uladzislau Nikalayevich / TheNormalnij e colaboradores do Hades2-coop-project. Adaptações locais mantidas por Gabriel / somaimpressaodigital. A licença MIT original está preservada em [LICENSE](LICENSE); os avisos presentes nos arquivos também devem ser mantidos.

Hades II e seus recursos pertencem à Supergiant Games. Este projeto é independente e não é afiliado à desenvolvedora. Não contém executáveis, texturas, mapas, áudio ou saves dos jogos. O mod Jornada de Zagreus e suas dependências devem ser obtidos separadamente de seus autores e não estão redistribuídos aqui.
