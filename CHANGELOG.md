# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versões seguem [SemVer](https://semver.org/lang/pt-BR/). A versão atual fica em `VERSION`.

## [1.2.1] — 2026-11-09

### Adicionado
- Mac: instalador em DMG (`scripts/build-dmg.sh`), com app universal (Apple Silicon e Intel) e atalho para Aplicativos. Com o certificado Developer ID no keychain, assina, notariza na Apple e grampeia o DMG; outros Macs abrem sem aviso do Gatekeeper. `build-app.sh` ganha `UNIVERSAL=1`.
- `docs/ux-decisoes.md` com as decisões de interface.

### Corrigido
- Mac: diálogos de ação (parar processo, descartar e finalizar timer, erro do Dashboard) ficavam atrás do notch aberto, e o notch congelava na tela enquanto o diálogo estava aberto. Agora o diálogo abre por cima e o notch continua respondendo.
- Mac: com muitas tarefas do Dashboard, o card passava da altura do notch e cortava o cabeçalho e o avatar. A lista agora rola por dentro e o resto do card fica fixo.
- Mac: lista de processos das CLIs com mais de 6 itens passa a rolar.

## [1.2.0] — 2026-10-31

### Adicionado
- **App de iPhone** em `ios/` (SwiftUI, iOS 17+, projeto gerado pelo XcodeGen a partir de `project.yml`), com os recursos do Mac e do Android pela mesma API v1:
  - **Telas:** Geral, CLIs (lista e detalhe), Mac com os processos (parar e forçar, com confirmação) e Tarefas (cronômetro em destaque, finalizar com registro de horas, notificações, projetos recolhíveis, ranking e avatar).
  - **Live Activity:** o cronômetro da tarefa aparece na Dynamic Island e na tela bloqueada e conta sozinho.
  - **Widgets** de tela inicial (pequeno e médio) e de tela bloqueada, com dados do App Group.
  - **Atalhos da Siri** (App Intents): "Pausar cronômetro" e "Retomar tarefa".
  - **Alertas em segundo plano** (BGAppRefresh) com as mesmas regras do Mac e do Android.
  - **Pareamento:** leitor de QR nativo (VisionKit), link `odoismonitor://pair?c=…` ou código colado. O token fica no Keychain, só neste aparelho.
  - Links `odoismonitor://tab/<aba>`; o widget abre a aba certa.
- Mac: `--pair-device` e `--revoke-device` para criar e revogar aparelhos pelo terminal (o token vai para um arquivo com permissão 0600 e nunca é impresso). O servidor relê a lista de aparelhos quando o arquivo muda.

### Corrigido
- **Mac travava** com memória apertada: estouro aritmético em `Sampler.readMemory`, porque as páginas purgáveis podiam passar as internas e a subtração dava a volta. Isso derrubava também o acesso remoto. A subtração agora para no zero, e o uso fica limitado à RAM física.

## [1.1.2] — 2026-10-31

### Corrigido
- Android: no release, o leitor de QR code não abria. O R8 removia os construtores dos registradores do ML Kit, que são criados por reflexão (`NoSuchMethodException: CommonComponentRegistrar.<init>`). Foram adicionadas regras de keep em `proguard-rules.pro`.
- A mensagem de falha do leitor agora mostra o motivo.

## [1.1.1] — 2026-10-31

### Adicionado
- Logo do oDois Monitor em `assets/logo/`: horizontal para fundo escuro e claro, e só o símbolo. Em SVG com o texto convertido em curvas (SF Pro), sem depender de fonte, e PNG em 1x e 2x.

### Corrigido
- Android: título e botões da tela de pareamento saíam em preto sobre o fundo escuro. O app inteiro agora usa a cor de texto do tema.

## [1.1.0] — 2026-10-31

### Adicionado
- Previsão de esgotamento dos limites: "no ritmo atual esgota às 16h40", calculada pela subida do percentual nas últimas 3 horas, só quando acontece antes do limite reiniciar. Aparece no Mac, no celular e na visão geral.
- Alerta quando faltar menos de 1 h para esgotar, no Mac e no celular.
- Histórico de 30 dias por CLI, no Mac e no celular. Os logs só cobrem 7 dias, então o histórico cresce dia a dia.
- Atalhos no ícone do app Android (tocar e segurar): pausar o cronômetro e iniciar as tarefas em andamento.
- Distribuição pelo teste interno do Google Play: release assinado com a chave de upload (fora do repositório) e `scripts/publish-android.py` para publicar o AAB pela API do Play Developer, com as notas da versão tiradas deste arquivo.

## [1.0.0] — 2026-10-31

### Adicionado
- **App Android** (`android/`, Kotlin + Jetpack Compose, Material 3, tema escuro do monitor), com os mesmos recursos do Mac via túnel da Cloudflare:
  - **Geral**: tokens do dia, sessões ativas, aviso de limite ≥ 80%, cronômetro em andamento, CLIs ordenadas por limite e resumo do Mac.
  - **CLIs**: lista com anel do limite e detalhe (limites, bloco de 5 h, hoje com composição, 7 dias, sessões, conta logada).
  - **Mac**: CPU/RAM/GPU, pressão de memória com histórico, processos das CLIs com PID e *Parar*/*Forçar* (confirmação).
  - **Tarefas**: avatar, ranking (quando a API trouxer), cronômetro em destaque (pausar, finalizar com horas/dia/atividade/comentário, descartar), pausados, notificações (abrir/lida), projetos recolhíveis com ▶.
  - Estado ao vivo por SSE com reconexão; atualizar puxando a tela.
  - **Widget** da tela inicial (tokens de hoje, limite mais alto, cronômetro) e **notificações** em segundo plano (limite ≥ 90%/esgotado, memória crítica, notificações do Dashboard) a cada 15 min.
  - **Pareamento** lendo o QR code do Mac (leitor do Google Play Services, sem permissão de câmera) ou colando o código; token cifrado com AES-256-GCM por chave do Android Keystore; só HTTPS.
  - Versão do app = `VERSION` da raiz.
- `--remote-state-json <arquivo>` no Mac: grava o JSON de `/v1/state` (teste de contrato do Android).
- Testes do Android (`./gradlew testDebugUnitTest`): contrato v1 com fixture anonimizada (e com o estado real via `ODOIS_STATE_JSON`), validação do pareamento e formatação.

## [0.9.0] — 2026-10-31

### Adicionado
- **Acesso remoto (celular)** pelo menu *Acesso remoto*:
  - Servidor HTTP próprio (Network.framework) só em `127.0.0.1:47862`; quem chega de fora é o túnel nomeado da Cloudflare `odois-monitor` (`https://monitor.o2d.me`), com config própria em `~/.config/odois-monitor/cloudflared.yml`. O app sobe e mantém o `cloudflared` (reinicia em 10 s se cair).
  - API v1: `GET /v1/state` (CLIs, sistema, processos, tarefas, cronômetros, notificações, ranking), `GET /v1/stream` (SSE a cada 2 s), ícones e avatar em PNG, e ações: iniciar/pausar/finalizar (registra horas)/descartar cronômetro, tipos de atividade, marcar notificação lida, parar processo, atualizar.
  - **Pareamento por QR code** (*Parear celular…*): um token por aparelho, só o hash SHA-256 em disco (`devices.json`, 0600), comparação em tempo constante, limite de 10 tentativas inválidas por origem a cada 5 min, revogação imediata. Descartar cronômetro e parar processo exigem `confirm: true`.
- `--remote-selftest`: sobe servidor e túnel, pareia um aparelho temporário, chama a API pelo endereço público e revoga (nunca imprime o token).

## [0.8.1] — 2026-10-31

### Corrigido
- **Ranking**: a pontuação mostrada (200, 22º) era só a parte manual — a API pública (`/api/v1/ops/ranking_summary`) não inclui critérios automáticos nem medalhas, e a página "Melhores do Ano" (3.320,01, 15º de 76) é montada no servidor e só abre com a sessão do navegador. A faixa de ranking fica oculta até a API expor o total.
- O app já consulta a API com `user_id` usando a credencial da `sea` (token só em memória); quando ela passar a devolver `total_score` completo, a faixa volta sozinha, com a composição medalhas / automático / manual.
- `--ranking`: diagnóstico da consulta (nunca imprime o token).

## [0.8.0] — 2026-10-31

### Adicionado
- **Avatar no card de Tarefas Sea**: a foto da conta do macOS (local, sem rede; o Dashboard não expõe avatar pela API), com anel em gradiente; sem foto, as iniciais.
- **Ranking**: posição no ranking anual (`sea ops ranking-summary`), pontuação geral do ano (`total_score`, soma de todos os critérios — a mesma da página de ranking), empates, quantos pontos faltam para o próximo patamar e barra comparando com o líder.

## [0.7.0] — 2026-10-31

### Alterado
- **Card de Tarefas Sea redesenhado**:
  - Cronômetro em destaque num cartão com gradiente (azul-petróleo → índigo): indicador "GRAVANDO" pulsando, relógio grande, anel com o progresso da hora corrente e as horas completas, botões *Pausar* / *Finalizar* e descartar.
  - Cronômetros pausados em linhas próprias com retomar e finalizar.
  - Sem cronômetro: convite "Escolha uma tarefa para começar"; sem tarefas: "Tudo em dia".
  - Cabeçalho com selos "em andamento" / "a iniciar" e conta da `sea` (nome; e-mail no tooltip).
  - Cada projeto ganha uma cor estável (barra lateral, contador e número da tarefa); tarefas em linhas com número em fonte monoespaçada, status e botão ▶ em gradiente.
  - Notificações com sino, contador e destaque lateral.
- `--snapshot` espera as tarefas do Dashboard carregarem antes de desenhar.

## [0.6.0] — 2026-10-31

### Adicionado
- **Notificações do Dashboard no notch**: a cada 60 s busca as não lidas (`sea notify inbox --unread`); quando chega uma nova, o notch abre sozinho mostrando-a por 8 s (fica aberto com o mouse em cima), com *Abrir* (abre a página e marca como lida), *Lida* e fechar; várias de uma vez mostram "+N". As que já existiam ao abrir o app não disparam o aviso.
- Seção **Notificações** no card de Tarefas com as não lidas (abrir ou marcar como lida).
- **Conta logada em cada CLI**, no cabeçalho do card: Claude Code (`~/.claude.json`), Codex (e-mail das claims públicas do `id_token`), Gemini CLI (`google_accounts.json`), DK (perfil ativo e provedor) e Tarefas Sea (`sea auth whoami`). Nenhum token é exibido ou guardado. O Antigravity não grava a conta em arquivo legível e fica sem a linha.

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
