# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versões seguem [SemVer](https://semver.org/lang/pt-BR/). A versão atual fica em `VERSION`.

## [0.5.0] — 2026-10-31

### Adicionado
- **Antigravity CLI (`agy`)**, quando instalada: consumo lido dos bancos SQLite de `~/.gemini/antigravity-cli/conversations` (um por conversa; o uso de cada geração vem no protobuf do passo), com modelo e pasta do projeto. Processos `agy` entram na lista de processos.
- **Tarefas: abrir no Dashboard** — clicar no título da tarefa (na lista ou no cronômetro) abre a página dela no navegador padrão (`/timesheet/projects/<slug>/tasks/<número>`, com o endereço da credencial da `sea`). No modo barra, cada tarefa do submenu tem *Iniciar* e *Abrir no navegador*.
- **Tarefas recolhíveis por projeto**; a escolha fica salva.

### Alterado
- No notch, o card acompanha a largura do formato aberto: com muitas abas a margem lateral continua igual às demais.

## [0.4.0] — 2026-10-31

### Adicionado
- **Tarefas do Sea Dashboard com cronômetro** (item *Tarefas Sea*, aparece quando a CLI `sea` está logada):
  - Lista as tarefas atribuídas a você em **não iniciado** e **em andamento**, por projeto, nos projetos em que você está alocado (30 dias para trás e para frente). Atualiza a cada 5 min ou no botão.
  - **Iniciar / pausar / retomar** com cronômetro local (funciona sem rede e sobrevive a fechar o app); só um roda por vez. Iniciar uma tarefa *não iniciado* a passa para *em andamento* no Dashboard.
  - **Finalizar** abre uma confirmação com horas (editáveis), data, tipo de atividade (lembra o último por projeto) e comentário; ao confirmar, grava na **sua** folha de horas da semana (cria a folha se faltar, conferindo o dono).
  - Cronômetro visível no notch fechado e na visão geral; no modo barra, controle pelo submenu *Tarefas Sea* do clique direito.
- A credencial é a da própria CLI `sea`; o app nunca lê nem mostra o token.

## [0.3.0] — 2026-10-31

### Adicionado
- **Processos das CLIs um a um** (card Sistema): PID, projeto, há quanto tempo roda, CPU e memória; os sem terminal aparecem como **2º plano** (abertos por app, agente ou daemon).
- **Parar processo**: dois cliques (o primeiro arma, o segundo envia SIGTERM); se não sair em 3 s, vira **Forçar** (SIGKILL). Antes do sinal o app confere pelo horário de início que o PID ainda é o mesmo processo. No modo barra, pelo submenu *Processos das CLIs* do clique direito.
- **Sessões ativas no notch fechado**: contador verde das sessões com resposta nos últimos 10 min; o tooltip mostra por CLI.
- Visão geral mostra quantos processos de CLI estão rodando e quantos em 2º plano.

### Alterado
- **Card mais compacto e com margens consistentes**: medidas centralizadas em `CardMetrics` (mesma margem nos quatro lados, no card da barra e no notch); tipografia e gráficos menores.
- No notch, o formato aberto tem a largura do card em vez de herdar a largura da faixa fechada (que deixava margens laterais bem maiores que a inferior).
- **Sessões recentes recolhíveis** (recolhidas por padrão); também alternam pelo menu, para o modo barra.

### Corrigido
- O painel do notch passa a comportar o maior dos dois formatos (fechado ou aberto), sem cortar as asas.

## [0.2.0] — 2026-10-31

Redesenho com foco no que o usuário precisa ver primeiro.

### Adicionado
- **Visão geral**: card com todas as CLIs e o sistema; é a primeira aba do notch (abre por padrão) e o primeiro item da barra. CLIs com limite crítico aparecem no topo.
- **Anel de status nos ícones** (barra e notch): limite mais alto de cada CLI e, no item Sistema, a RAM colorida pela pressão de memória.
- **Aviso no notch fechado**: quando um limite passa de 80%, o percentual (com a cor da faixa) toma o lugar do total de tokens.
- Ícone do app, gerado com o GPT.
- Versão no menu e no `Info.plist`, lida de `VERSION`; número de build = número de commits.

### Alterado
- Card da CLI reorganizado: limites primeiro, depois o uso de hoje, a semana e as sessões.
- Os quatro quadros de entrada/saída/cache viraram uma barra de composição com legenda (mostra quanto do total é cache).
- Sem uso no dia, o card diz "Nenhum uso hoje" em vez de uma grade de zeros.
- Cabeçalho mostra o estado de uso ("Em uso agora", "Último uso há 3 h") no lugar de "Atualizado agora".
- Bloco de 5 h do Claude mostra o tempo decorrido do bloco.
- Semana com média diária e o dia de hoje em destaque.
- Nomes de pasta gerados a partir do pedido (ex.: tarefas do Codex) aparecem como frase.
- No notch aberto o ícone da CLI não se repete no cabeçalho.

## [0.1.0] — 2026-10-31

Primeira versão: barra flutuante e modo notch com o consumo de Claude Code, Codex, Gemini CLI e DK lido dos logs locais, card do sistema (CPU, RAM, GPU, pressão de memória), alertas por notificação e modos `--snapshot`, `--alerts`, `--bench` e `--test-alert`.
