# Decisões de UX — oDois Monitor

### 2026-11-09 — Notch: diálogos de ação (parar processo, timers do Dashboard)
- Decisão: diálogos abrem acima do notch e dos cards; o notch continua respondendo ao mouse
  enquanto o diálogo está aberto e recolhe quando o mouse sai.
- Lei que sustenta: Fitts (a ação pedida precisa estar clicável) e Doherty (o notch não pode
  congelar na tela).
- Alternativa descartada: esconder o notch ao abrir qualquer diálogo (some o contexto da ação).
- Herdado da base? não se aplica (app próprio em AppKit/SwiftUI).
- Como validar: (TESTAR) abrir o notch, parar um processo pelo menu e conferir que o diálogo
  fica por cima e o notch recolhe.

### 2026-11-09 — Card de Tarefas: lista longa
- Decisão: a lista de tarefas rola por dentro a partir de 300 pt de altura; cabeçalho, avatar,
  contadores e o cronômetro ficam sempre visíveis. A última linha aparece cortada na borda,
  sinalizando que há mais itens.
- Lei que sustenta: Miller (o resumo — quem sou, quantas em andamento, o que está rodando —
  continua à vista) e Jakob (lista que rola dentro do painel, como em menus e popovers do macOS).
- Alternativa descartada: limitar a N tarefas com "ver mais" (esconde opções e exige um clique
  a mais; Miller não pede corte de itens).
- Herdado da base? não se aplica.
- Como validar: (TESTAR) com 40+ tarefas, rolar com trackpad dentro do notch e conferir que o
  topo do card não é cortado. Mesmo padrão já usado na lista de processos (mais de 6 linhas).
