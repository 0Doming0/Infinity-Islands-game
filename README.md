# SkyDungeon

Projeto Roblox sincronizado por Rojo. O loop do MVP e subir antes da agua,
lutar, acumular moedas, comprar equipamento nas vilas e arriscar rotas laterais.

## Sistemas atuais

- `RunScore`, `BestScore` e `Coins` completamente separados;
- ranking global persistente por `BestScore`;
- perda de toda a tentativa e 20% das moedas ao morrer;
- inventario persistente com consumiveis e GUI compacta;
- comerciantes variados, compras por moedas e aldeoes solitarios raros;
- agua acelerada, adaptativa e afetada por eventos;
- dificuldade fixa por altura, sem usar o jogador mais forte do servidor;
- ilhas laterais Elite opcionais;
- baus comuns, Baú Mimico e Ilha do Tesouro;
- eventos Mare Furiosa, Chuva de Moedas e Cacada dos Monstros;
- PvP desativado e grupos de colisao seguros para jogadores e inimigos;
- cura passiva desativada;
- atmosfera, nuvens, iluminacao e suporte a musica licenciada;
- modelos de prototipo para espadas, monstros e baus ausentes.

## Estrutura de assets no Roblox Studio

Os modelos reais continuam fora do Rojo e devem ficar em `ServerStorage`:

```text
ServerStorage
└── MVPAssets
    ├── Chests
    │   ├── NormalChest [Model]
    │   └── MimicChest [Model]
    ├── Monsters
    │   └── GreenSlime [Model, exemplo]
    ├── Swords
    │   ├── ClassicSword [Tool]
    │   ├── BronzeSword [Tool]
    │   ├── CrystalSword [Tool]
    │   ├── VoidSword [Tool]
    │   ├── RoyalSword [Tool]
    │   └── DragonSword [Tool]
    ├── Village
    │   ├── Buildings
    │   └── Villagers
    ├── Decorations
    ├── Grass
    ├── Items
    └── Atmosphere
        ├── Sky [Sky, opcional]
        ├── AmbientMusic [Folder]
        │   ├── Track01 [Sound]
        │   ├── Track02 [Sound]
        │   └── outras faixas [Sound, opcionais]
        ├── ForestAmbience [Folder]
        │   ├── ForestLoop [Sound]
        │   └── BirdCalls [Folder]
        │       ├── Bird01 [Sound]
        │       ├── Bird02 [Sound]
        │       └── outros passaros [Sound, opcionais]
        └── DangerMusic [Sound, opcional]
```

As faixas dentro de `AmbientMusic` sao embaralhadas e tocadas uma por vez,
sem repeticao imediata. Depois que uma faixa termina, o jogo mantem de 12 a 25
segundos de silencio antes da proxima, criando momentos de paz. Cada `Sound`
pode ter seu proprio `Volume`; deixe `Looped` desativado, pois a playlist
controla a troca. O formato antigo com um unico `Sound` chamado `AmbientMusic`
continua funcionando. Os tempos ficam em `MVPConfig.Atmosphere`.

`ForestLoop` toca continuamente em volume baixo, inclusive durante os momentos
de silencio entre as musicas. Os sons dentro de `BirdCalls` sao chamados em
intervalos aleatorios de 8 a 20 segundos, sem repetir o mesmo passaro de forma
imediata. O volume individual vem de cada `Sound`; volume geral, intervalos,
fade e reducao durante eventos perigosos ficam em `MVPConfig.Atmosphere`.

O jogo cria prototipos em tempo de execucao quando um asset essencial nao
existe. Um modelo real com o nome esperado sempre tem prioridade.

## Contrato do bau normal

```text
NormalChest [Model]
├── Root [BasePart, PrimaryPart]
└── partes visuais livres
```

- `Root` e o unico nome obrigatorio;
- todas as partes devem estar soldadas ao `Root`;
- nao coloque `ProximityPrompt` ou Script: o servidor cria a interacao;
- o sistema ancora e posiciona o modelo automaticamente.

## Contrato do Baú Mimico

```text
MimicChest [Model]
├── HumanoidRootPart [BasePart, PrimaryPart]
├── Humanoid
└── Animations [Folder]
    └── Main [Animation]
```

`Main` e a unica animacao usada e pode conter andar, pular e morder. Para que o
dano aconteca exatamente quando a boca fecha, adicione um marcador de animacao
chamado `Bite`. Sem o marcador, a IA utiliza distancia e cooldown.

A IA especifica fica em `BlockParkour/MimicAI`; Scripts internos do modelo sao
desabilitados no clone para impedir duas IAs concorrentes.

## Contrato dos monstros

Modelos ficam em `ServerStorage/MVPAssets/Monsters` e precisam de `Humanoid`,
`HumanoidRootPart` (ou `PrimaryPart`) e atributos:

| Atributo | Exemplo | Funcao |
|---|---:|---|
| `MonsterId` | `GreenSlime` | ID unico |
| `DisplayName` | `Slime Verde` | Nome visivel |
| `MaxHealth` | `50` | Vida base |
| `AttackDamage` | `8` | Dano base |
| `ScoreValue` | `3` | Pontos por morte |
| `CoinValue` | `5` | Moedas por morte |
| `SpawnChance` | `0.72` | Chance de aparecer |
| `SpawnWeight` | `10` | Peso entre modelos |
| `MinimumIslandSize` | `Small` | Tamanho minimo |
| `SpawnMode` | `Solo`, `Group` ou `Boss` | Formato do grupo |
| `GroupMin` / `GroupMax` | `2` / `4` | Quantidade no grupo |
| `GroupSpacing` | `5` | Distancia entre membros |
| `Peaceful` | `false` | Se ataca jogadores |
| `UseCentralAI` | `true` | Usa a IA generica do projeto |
| `UseCustomAI` | `true` | Preserva IA propria em variantes Elite |
| `RewardScaleVersion` | `2` | Usa `ScoreValue` na nova escala |

Ilhas Elite recebem nivel fixo pelo round, mais vida/dano e recompensa. O nivel
nao muda conforme os jogadores presentes no servidor.

## Economia e salvamento

O DataStore canonico continua `SkyDungeonPlayerData_V10`, agora com schema 3:

```text
Coins
BestScore
OwnedSwords
EquippedSword
Inventory
```

Registros antigos sao migrados. `TotalScore` antigo nao vira moeda, e recordes
da escala anterior sao compactados pelo divisor em `MVPConfig.Progression`. O
saldo e os itens do DataStore legado `BlockParkour_PlayerData_v1` sao importados
uma unica vez para o registro canonico.

O ranking global usa `SkyDungeonGlobalBestScore_V1`.

## Configuracao principal

Probabilidades, recompensas, agua, dificuldade, eventos, vilas e penalidade de
morte ficam centralizados em:

```text
ReplicatedStorage/MVPConfig
```

Catalogos:

```text
ReplicatedStorage/SwordCatalog
ReplicatedStorage/ItemCatalog
ReplicatedStorage/VillageShopCatalog
```

## Teste

1. Abra o projeto com Rojo.
2. Em um ambiente de teste, habilite **Game Settings > Security > Enable Studio Access to API Services**.
3. Teste com dois jogadores para validar PvP desativado e colisao.
4. Use varias mortes para validar perda de moedas e preservacao do recorde.
5. Teste compra, uso de consumiveis, respawn e nova entrada.
6. Force temporariamente as chances em `MVPConfig` para testar Elite, Tesouro e Mimico.

Para construir o place quando o Rojo estiver instalado:

```bash
rojo build -o SkyDungeon.rbxlx
```
