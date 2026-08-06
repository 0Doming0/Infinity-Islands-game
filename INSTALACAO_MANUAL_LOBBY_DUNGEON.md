# Infinity Islands — instalação manual do Lobby e da Dungeon

Este guia explica, em ordem, o que precisa ser feito manualmente para instalar a integração atual do Lobby e da Dungeon.

## Antes de começar: o que este pacote realmente entrega

O pacote instala a implementação já existente no branch `agent/lobby-mvp-integration`:

- dois projetos Rojo separados;
- Lobby como área de preparação;
- grupos de até quatro jogadores;
- seleção de duas fases;
- teleporte para servidor reservado;
- equipamentos apenas cosméticos no Lobby;
- roleta persistente;
- escala de dificuldade por tamanho inicial do grupo;
- runtime da Dungeon, arena, boss, vitória, derrota e retorno;
- registro das fases a partir das pastas do `ServerStorage`.

O pacote não contém os modelos `.rbxm/.rbxmx`, o mapa visual do Lobby, IDs publicados, imagens, músicas ou animações. Esses itens existem dentro do Roblox Studio e precisam ser preparados manualmente.

Importante: o plano técnico final de retenção é maior que esta integração. O schema 12 completo, grants idempotentes, o novo HUD Arcano Noturno, o tutorial de 13 etapas e a bateria de 145 testes ainda não estão totalmente implementados neste código. Não publique anúncios tratando este pacote como a versão final do plano.

---

## Parte A — instalar os arquivos no projeto

### 1. Faça um backup

1. Feche o Rojo e o Roblox Studio.
2. Faça uma cópia da pasta inteira do projeto.
3. No Git, trabalhe no branch `agent/lobby-mvp-integration`.
4. Confirme que você consegue voltar ao estado anterior antes de substituir qualquer arquivo.

### 2. Copie os arquivos do ZIP

1. Abra a pasta `ARQUIVOS_PARA_COPIAR` do ZIP.
2. Copie tudo que está dentro dela.
3. Cole na raiz do seu repositório, onde ficam `default.project.json`, `src` e `tools`.
4. Escolha **substituir os arquivos com o mesmo nome**.
5. Não copie a própria pasta `ARQUIVOS_PARA_COPIAR` para dentro do repositório; copie o conteúdo dela.

Depois da cópia, estes três arquivos devem estar lado a lado:

```text
default.project.json
dungeon.project.json
lobby.project.json
```

### 3. Ainda não altere os IDs

Deixe temporariamente assim:

```lua
LobbyPlaceId = 0,
DungeonPlaceId = 0,
```

O valor zero bloqueia teleportes publicados e evita mandar jogadores para o Place errado durante a preparação.

---

## Parte B — criar os dois Places na mesma experiência

O resultado deve ser:

```text
Infinity Islands — uma única Experience
├── Lobby            ← Start Place
└── Dungeon Runtime  ← Place secundário
```

Não crie duas Experiences separadas.

### 4. Preserve o mapa procedural como Dungeon

1. Abra o Place procedural atual no Roblox Studio.
2. Salve uma cópia local `.rbxl` como segurança.
3. Publique uma cópia dele como um novo Place chamado `Dungeon Runtime`, dentro da mesma Experience.
4. Abra o novo `Dungeon Runtime` e confirme que o mapa, `ServerStorage`, iluminação e assets continuam presentes.
5. Anote o `PlaceId` da Dungeon.

Não transforme a única cópia do mapa procedural em Lobby antes de confirmar que o novo Place foi publicado corretamente.

### 5. Prepare o Start Place como Lobby

1. Volte ao Start Place original da mesma Experience.
2. Salve outra cópia local antes de limpar o mapa.
3. Remova do `Workspace` somente o mapa procedural, ilhas geradas e objetos de gameplay que não pertencem ao Lobby.
4. Monte ou importe o mapa visual do Lobby nesse Start Place.
5. Anote o `PlaceId` do Lobby.

O Lobby deve permanecer leve. Não deixe nele boss, inimigos ativos, água procedural ou todas as ilhas da Dungeon.

### 6. Configure a privacidade da Dungeon

No painel da experiência, deixe o Place `Dungeon Runtime` acessível apenas de dentro da própria Experience. O jogador deve entrar nele pelo teleporte do Lobby, nunca por acesso direto.

---

## Parte C — preencher os IDs e sincronizar corretamente

### 7. Preencha os PlaceIds

Abra:

```text
src/shared/Shared/Configs/PlaceConfig.lua
```

Troque apenas os zeros:

```lua
return table.freeze({
    LobbyPlaceId = 1234567890,
    DungeonPlaceId = 9876543210,
})
```

Use números, sem aspas. `LobbyPlaceId` recebe o ID do Start Place; `DungeonPlaceId` recebe o ID do Place secundário.

### 8. Sincronize a Dungeon

1. Abra o Place `Dungeon Runtime` no Studio.
2. No VS Code, abra a pasta raiz do projeto.
3. Inicie o Rojo usando `dungeon.project.json`.
4. A porta prevista é `34872`.
5. No plugin Rojo do Studio, conecte à porta `34872`.
6. Confirme que o projeto mostrado é **Infinity Islands Dungeon Runtime**.
7. Sincronize e salve o Place.

Nunca conecte `lobby.project.json` nesse Place.

### 9. Sincronize o Lobby

1. Abra o Start Place `Lobby` no Studio.
2. Inicie o Rojo usando `lobby.project.json`.
3. A porta prevista é `34873`.
4. No plugin Rojo do Studio, conecte à porta `34873`.
5. Confirme que o projeto mostrado é **Infinity Islands Lobby**.
6. Sincronize e salve o Place.

Nunca conecte `dungeon.project.json` no Lobby.

---

## Parte D — organizar os modelos da Dungeon

### 10. Execute a migração uma única vez

Faça isto no Place `Dungeon Runtime`, fora do modo Play:

1. Confirme que existe `ServerStorage/MVPAssets`.
2. Abra `tools/MigrateGameContent.server.luau` no VS Code.
3. Copie todo o conteúdo do arquivo.
4. No Studio, abra `View > Command Bar`.
5. Cole o código e execute uma única vez.
6. Confira no Output a mensagem de conclusão.
7. Salve o Place.

O script cria um backup chamado:

```text
ServerStorage/MVPAssets_LobbyMigrationBackup
```

Não apague esse backup até terminar todos os testes.

### 11. Confira a árvore criada

No `ServerStorage` da Dungeon deve existir:

```text
GameContent
├── Phases
│   ├── Phase01
│   │   ├── Islands
│   │   │   ├── Common
│   │   │   ├── Special
│   │   │   └── BossArena
│   │   ├── Enemies
│   │   ├── Bosses
│   │   └── Decorations
│   ├── Phase02
│   │   └── mesmas pastas
│   └── _PhaseTemplate
├── Equipment
│   ├── Swords
│   ├── Wings
│   ├── Companions
│   └── Abilities
└── SharedModels
```

Se essa árvore não aparecer, pare. Não prossiga para publicação.

### 12. Prepare os inimigos

Cada inimigo diretamente em `Phase01/Enemies` ou `Phase02/Enemies` precisa ser um `Model` com:

- `Humanoid`;
- `HumanoidRootPart` ou `PrimaryPart`;
- Attribute `MonsterId` do tipo `String`;
- Attribute `Enabled = true`;
- `MinimumRound`, `MaximumRound`, `SpawnWeight` e `SpawnChance` quando você quiser controlar o spawn.

Os inimigos da Fase 2 foram inicialmente copiados da Fase 1 apenas como ponto de partida. Para a fase ficar realmente diferente, substitua os modelos, atributos, cores, efeitos e balanceamento da Fase 2.

### 13. Prepare os bosses

Em cada pasta `Bosses`, coloque o boss daquela fase. O mínimo é:

```text
GiantBoss [Model]
├── Humanoid
└── HumanoidRootPart
```

Defina o `PrimaryPart` do Model. Opcionalmente use Attributes:

- `BossId`;
- `DisplayName`;
- `BaseHealth`;
- `BaseDamage`;
- `WalkSpeed`;
- `AttackRange`;
- `AttackCooldown`;
- `DetectionRange`.

Para o build final, use bosses diferentes e coerentes com cada fase, por exemplo `ColossalSlimeKing` e `TempestSlimeKing`.

### 14. Prepare as arenas

Em cada `Phases/<PhaseId>/Islands/BossArena`, coloque um Model de arena com pelo menos:

```text
BossArenaModel
├── ArenaFloor [BasePart]
├── BossTrigger [BasePart, opcional]
├── BossSpawn [BasePart recomendado]
├── PlayerSpawns [Folder recomendado]
└── ArenaBounds [BasePart recomendado]
```

Durante o protótipo, `AllowPrototypeContent = true` permite fallback. Antes do build candidato final, crie arenas próprias e mude esse Attribute para `false` nas duas fases.

### 15. Prepare as ilhas e marcadores

Modelos de ilha próprios devem ficar em `Islands/Common` ou `Islands/Special`. Cada Model deve ter `PrimaryPart` e, para a estrutura final, estes marcadores:

```text
IslandModel
├── Geometry
├── Decorations
├── EntryMarker
├── ExitMarker
├── SafeSpawn
├── EnemySpawns
├── ObjectiveMarkers
└── RuntimeAttachments
```

Marcadores são `Parts` invisíveis, ancoradas, sem colisão e sem scripts internos.

---

## Parte E — montar o mapa do Lobby

### 16. Crie quatro pontos obrigatórios

No mapa do Lobby, crie ao menos:

1. um ponto de spawn;
2. um portal da Fase 1;
3. um portal da Fase 2;
4. uma estação de equipamentos;
5. uma estação de roleta.

Você pode posicioná-los onde quiser. O código não depende de coordenadas fixas.

### 17. Adicione as Tags pelo Tag Editor

Abra o Tag Editor do Studio e marque os objetos:

| Objeto | Tag | Attribute |
|---|---|---|
| Spawn do Lobby | `LobbySpawn` | nenhum |
| Portal da Fase 1 | `PhasePortal` | `PhaseId = "Phase01"` |
| Portal da Fase 2 | `PhasePortal` | `PhaseId = "Phase02"` |
| Roleta | `RouletteStation` | `WheelId = "BasicWheel"` |
| Equipamentos | `EquipmentStation` | nenhum |

Cada objeto marcado deve ser uma `BasePart` ou um `Model` com `PrimaryPart`. O servidor cria os `ProximityPrompt`; não precisa adicioná-los manualmente.

### 18. Deixe os equipamentos apenas visuais

No Lobby, os equipamentos podem aparecer no personagem e ser trocados, mas não podem causar dano, ativar habilidades ou permitir voo. Se uma `Tool` funcional aparecer no Backpack do Lobby, considere isso um erro de instalação.

---

## Parte F — configurar e testar

### 19. Publique primeiro a Dungeon

1. Publique e salve o Place `Dungeon Runtime`.
2. Inicie uma vez um servidor publicado da Dungeon para que o catálogo das fases seja validado e gravado.
3. Confira no Output se `Phase01` e `Phase02` foram registradas.
4. Só depois publique o Lobby.

Enquanto o catálogo ainda não existir, o Lobby usa temporariamente as duas fases padrão.

### 20. Teste cada Place isoladamente no Studio

Dungeon:

- `Workspace` sem Attribute `StudioPhaseId` testa a fase padrão;
- `Workspace` com `StudioPhaseId = "Phase02"` testa a Fase 2;
- confirme geração, inimigos, boss, vitória e derrota.

Lobby:

- confirme carregamento dos dados;
- confirme os dois portais;
- confirme roleta;
- confirme equipamento cosmético;
- confirme que ataque e voo estão bloqueados.

### 21. Teste o fluxo completo em versão publicada

Teleporte reservado não é validado corretamente pelo teste local comum do Studio. Use uma versão publicada e privada:

1. entre pelo Lobby;
2. crie grupo solo e inicie a Fase 1;
3. confirme que chegou à Dungeon reservada;
4. conclua ou force derrota;
5. confirme retorno ao Lobby;
6. repita com Fase 2;
7. repita com grupos de 2, 3 e 4 jogadores.

### 22. Teste persistência sem usar sua base de produção

Use uma experiência de teste ou contas de teste. Verifique:

- moedas depois de reconectar;
- equipamentos selecionados;
- prêmio da roleta;
- conclusão da fase;
- ausência de recompensa duplicada;
- nenhum jogador preso em estado de teleporte.

---

## Checklist mínimo para dizer “a integração funciona”

- [ ] O ZIP foi copiado na raiz correta do repositório.
- [ ] Lobby e Dungeon pertencem à mesma Experience.
- [ ] Lobby é o Start Place.
- [ ] Dungeon não aceita entrada direta.
- [ ] Os dois PlaceIds estão corretos em `PlaceConfig.lua`.
- [ ] `dungeon.project.json` foi sincronizado somente na Dungeon.
- [ ] `lobby.project.json` foi sincronizado somente no Lobby.
- [ ] A migração criou `ServerStorage/GameContent` e o backup.
- [ ] As duas fases possuem ao menos um inimigo válido.
- [ ] Boss e arena funcionam nas duas fases.
- [ ] Os portais possuem Tags e `PhaseId` corretos.
- [ ] A roleta possui `WheelId = "BasicWheel"`.
- [ ] Equipamentos não funcionam como armas no Lobby.
- [ ] Solo e grupos de 2, 3 e 4 entram no mesmo servidor reservado.
- [ ] Vitória, derrota, salvamento e retorno foram testados em versão publicada.

## Checklist para considerar o plano técnico final concluído

Além do checklist anterior, ainda será necessário implementar e validar os blocos pendentes do documento `INFINITY_ISLANDS_PLANO_TECNICO_RETENCAO_MVP.md`, incluindo:

- schema 12 e uma única implementação canônica de dados;
- trava de sessão/perfil e grants idempotentes;
- rounds finais de 3, 4 e 5 ilhas com seis baús pessoais;
- economia e drops finais das duas fases;
- tutorial contextual de 13 passos;
- HUD Arcano Noturno e remoção das interfaces concorrentes;
- contrato completo de sinais, snapshots, validação e rate limit;
- assets P0 sem protótipos;
- execução e aprovação dos 145 cenários funcionais;
- testes cegos, canário e gates antes de reativar anúncios.

Até esses itens passarem, considere o projeto uma **integração jogável em desenvolvimento**, não o release candidate final.

## Referências técnicas

- Teleporte entre Places: https://create.roblox.com/docs/projects/teleport
- Publicação de experiências e Places: https://create.roblox.com/docs/production/publishing/publish-experiences-and-places
- Sincronização do Rojo: https://rojo.space/docs/v7/sync-details/
