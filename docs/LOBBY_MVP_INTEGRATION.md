# Lobby MVP: integração dos dois Places

O código da experiência agora possui dois projetos Rojo:

- `lobby.project.json`: somente dados, grupos, equipamentos cosméticos, roleta, portais e teleporte;
- `dungeon.project.json`: runtime procedural existente, escalonamento, arena final, boss e retorno.

O `default.project.json` continua representando a dungeon para preservar o fluxo atual de desenvolvimento.

## 1. Publicar os Places

1. Faça uma cópia do Place procedural atual dentro da mesma Experience e mantenha essa cópia como Dungeon Runtime.
2. Crie um Place vazio para o Lobby e defina-o como Start Place.
3. Sincronize `dungeon.project.json` no Place procedural.
4. Sincronize `lobby.project.json` no novo Place de lobby.
5. Preencha `LobbyPlaceId` e `DungeonPlaceId` em `src/shared/Shared/Configs/PlaceConfig.lua`.

IDs iguais a zero bloqueiam teleportes publicados de propósito. No Studio, a dungeon aceita `Phase01` sem `TeleportData`; defina o Attribute `StudioPhaseId = "Phase02"` no Workspace para testar a segunda fase.

## 2. Migrar os modelos do Place procedural

Os modelos `.rbxm/.rbxmx` não estão versionados neste repositório. No Place de dungeon, execute uma vez o conteúdo de `tools/MigrateGameContent.server.luau` no Command Bar, fora do modo Play. O script:

- cria um backup `MVPAssets_LobbyMigrationBackup`;
- cria `ServerStorage/GameContent`;
- copia inimigos, bosses e decorações para `Phase01`;
- copia espadas para `GameContent/Equipment`;
- copia conteúdo global para `SharedModels`;
- duplica temporariamente inimigos, decorações e bosses para `Phase02`.

O `MVPAssets` original é mantido como camada de compatibilidade para equipamentos e modelos globais. O runtime usa exclusivamente a pasta da fase selecionada para mobs, boss e decorações; uma fase nunca reutiliza silenciosamente o conteúdo de outra.

Estrutura final esperada:

```text
ServerStorage/GameContent
├── Phases
│   ├── Phase01
│   │   ├── Islands/Common
│   │   ├── Islands/Special
│   │   ├── Islands/BossArena
│   │   ├── Enemies
│   │   ├── Bosses
│   │   └── Decorations
│   └── Phase02
│       └── ...
├── Equipment
│   ├── Swords
│   ├── Wings
│   ├── Companions
│   └── Abilities
└── SharedModels
```

## 3. Registro automático de fases

Não edite `PhaseConfig.lua` para adicionar uma fase. Duplique `_PhaseTemplate` dentro de `ServerStorage/GameContent/Phases`, renomeie a pasta, preencha seus Attributes, coloque os modelos obrigatórios e altere `Enabled` para `true`.

Na inicialização da Dungeon, `PhaseRegistry` examina todas as pastas, desativa as inválidas e publica os dados públicos das fases para o Lobby. O Output informa atributos, pastas ou modelos ausentes. O catálogo do Lobby é atualizado quando um servidor publicado da Dungeon inicia com a nova pasta.

| Attribute da fase | Tipo | Função |
|---|---|---|
| `PhaseId` | String | Identificador único usado no teleporte |
| `DisplayName` | String | Nome exibido no Lobby |
| `Enabled` | Boolean | Registra ou ignora a fase |
| `RequiredLevel` | Number | Nível mínimo |
| `MaxPlayers` | Number | Limite de 1 a 4 jogadores |
| `MaximumIslandCount` | Number | Quantidade de ilhas antes do boss |
| `VictoryCoins` | Number | Moedas por vitória |
| `BossId` | String | Nome ou Attribute `BossId` do modelo em `Bosses` |
| `ImageId` | String | Imagem pública da fase |
| `SortOrder` | Number | Ordem no Lobby |
| `MaximumActiveMonsters` | Number | Limite simultâneo de mobs |
| `EliteReservedMonsterSlots` | Number | Vagas preservadas para elites |
| `DefaultMonsterSpawnChance` | Number | Chance padrão de mobs, entre 0 e 1 |
| `DecorationSpawnChance` | Number | Chance de decoração, entre 0 e 1 |
| `AllowPrototypeContent` | Boolean | Compatibilidade das fases antigas com arena/boss provisórios |

Para fases novas, mantenha `AllowPrototypeContent = false`. Nesse modo, boss e arena personalizados são obrigatórios.

### Aparência procedural dos blocos

| Attribute | Tipo | Exemplo |
|---|---|---|
| `IslandBlockColor` | Color3 | `Color3.fromRGB(90, 45, 35)` |
| `IslandBlockMaterial` | String | `Basalt`, `Slate`, `Ground` |
| `IslandBlockTextureId` | String | `rbxassetid://123456789` ou vazio |
| `TextureStudsPerTileU` | Number | `4` |
| `TextureStudsPerTileV` | Number | `4` |

A cor e o material são aplicados nos pisos e conexões procedurais. Quando `IslandBlockTextureId` não está vazio, a textura é repetida nas seis faces. Para celular, prefira material e cor; use textura somente quando ela realmente acrescentar identidade visual.

### Regras de spawn por mob

Cada Model diretamente em `Enemies` continua usando seus Attributes individuais. Além dos atributos já existentes, agora pode usar:

| Attribute | Função |
|---|---|
| `MinimumRound` | Primeiro round em que o mob pode aparecer |
| `MaximumRound` | Último round em que o mob pode aparecer; omita para não limitar |
| `SpawnWeight` | Peso relativo entre mobs elegíveis |
| `SpawnChance` | Chance final depois da seleção |

Cada fase seleciona somente os mobs de sua própria pasta.

## 4. Montar o mapa do lobby

O código não usa coordenadas fixas. Marque os objetos do mapa com `CollectionService`:

| Tag | Attribute | Valor |
|---|---|---|
| `PhasePortal` | `PhaseId` | qualquer `PhaseId` registrado |
| `RouletteStation` | `WheelId` | `BasicWheel` |
| `EquipmentStation` | — | — |
| `LobbySpawn` | — | — |

Cada objeto marcado deve ser uma `BasePart` ou um `Model` com `PrimaryPart`. Os `ProximityPrompt` são criados pelo servidor.

## 5. Modelos do boss

Um modelo chamado `GiantBoss` pode ser colocado em `Phases/<PhaseId>/Bosses`. Ele deve possuir `Humanoid` e `HumanoidRootPart` ou `PrimaryPart`. Adicione `BossId = "GiantBoss"` se o nome do Model for diferente.

Bosses novos não exigem edição de `BossConfig.lua`. O modelo pode definir `DisplayName`, `BaseHealth`, `BaseDamage`, `WalkSpeed`, `AttackRange`, `AttackCooldown` e `DetectionRange` como Attributes. Valores ausentes usam os padrões do boss inicial.

Uma arena deve ficar em `Phases/<PhaseId>/Islands/BossArena`. Use uma `BasePart` chamada `ArenaFloor` e, opcionalmente, outra chamada `BossTrigger`. Somente fases antigas com `AllowPrototypeContent = true` podem usar a arena, ponte e boss provisórios.

## 6. Testes obrigatórios

- Lobby: dados carregados, equipamentos cosméticos e sem Tools funcionais.
- Roleta: custo removido, prêmio concedido no servidor e persistência após reconectar.
- Grupo: convite, recusa, saída, remoção, troca de líder e limite de quatro.
- Fases: solo em `Phase01` e `Phase02`, depois grupos de 2, 3 e 4.
- Teleporte: todos no mesmo servidor reservado e membro ausente não altera o escalonamento inicial.
- Dungeon: 135/170/205% de vida nos inimigos para 2/3/4 jogadores.
- Boss: 150/200/250% de vida, ativação pelo gatilho, vitória única e salvamento.
- Derrota: todos mortos, nenhuma recompensa de conclusão e retorno ao lobby.

Teleportes para servidor reservado não funcionam no teste local comum do Studio. Publique os dois Places e use uma versão privada da Experience para o teste completo.
