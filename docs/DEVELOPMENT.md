# Desenvolvimento

## Dependências

- Hades II instalado pelo usuário e um ambiente de mods compatível.
- [Hades II coop upstream](https://github.com/Hades2-coop-project/hades2-coop).
- [Hades II engine interface](https://github.com/Hades2-coop-project/hades2-engine-interface) e as dependências indicadas pelo upstream, incluindo Lua 5.2 e EASTL.
- Compilador MSVC x64 e Windows SDK para as pontes nativas. As pontes de pausa e recolor são específicas da versão do executável cujas assinaturas aparecem nas fontes.

## Limites deste snapshot

Os módulos Lua atuais e as fontes das duas pontes experimentais estão incluídos. As fontes `native/upstream-coop` representam a base original; não afirmamos que reproduzem todas as DLLs adicionais usadas no ambiente local. Ainda é necessário publicar a organização completa de build dessas adaptações e eliminar os caminhos de workspace restantes.

Não há binários, assets proprietários, SDKs vendorizados, arquivos de autenticação, configurações de controles pessoais ou saves. As referências `<WORKSPACE>` são marcadores documentais, não variáveis de ambiente automaticamente resolvidas. As dependências externas e a configuração dos carregadores não são instaladas por este repositório.

O par DLL/Lua do recolor deve usar o mesmo contrato. A variante de recolor aqui exportada é a instalada no snapshot; a tentativa posterior de transferência via registro Lua ainda é candidata local e não integra esta publicação. O mesmo cuidado se aplica ao par DLL/Lua da pausa. Compilar ou observar o botão não prova o funcionamento da interação, da morte conjunta ou da progressão.

## Contribuições

Abra uma issue com versão do jogo, versão do carregador, armas dos dois jogadores, dispositivo de entrada, passos e resultado observado. Remova nomes de usuário, caminhos pessoais e dados de save de qualquer log ou captura. Não anexe arquivos dos jogos.

Faça alterações pequenas e preserve o modo solo, o progresso real e o isolamento dos jogadores. Não modifique sorteios para esconder uma opção incompatível. Ao relatar testes, diferencie teste offline, compilação e observação real dentro do jogo.

A tabela gerada `snapshot/reward-ui/NativeTextTemplates.lua` contém somente o contrato vazio. As descrições/textos originais do jogo foram excluídos da publicação; o desenvolvedor precisa gerar esses dados localmente a partir de sua própria instalação. O bloqueio de perfil de teste também conserva um marcador `<USERPROFILE>` que precisa de configuração local.
