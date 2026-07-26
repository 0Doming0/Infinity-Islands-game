# Sistema modular de monstros e companheiros

Os Models ficam em `ServerStorage/MVPAssets/Monsters`. Um mob comum usa a IA
genérica automaticamente. Defina `UseCustomAI = true` apenas quando o Model
possuir um controlador próprio. O atributo legado `UseCentralAI` continua sendo
preenchido em runtime, mas não é mais necessário no asset.

## Estrutura mínima

```text
Golem [Model, PrimaryPart = HumanoidRootPart]
├── HumanoidRootPart [BasePart]
├── Humanoid
├── Animations [Folder, opcional]
│   ├── Idle [Animation]
│   ├── Walk [Animation]
│   ├── Attack [Animation]
│   ├── Death [Animation]
│   └── GroundSlam [Animation]
├── Abilities [Folder, opcional]
│   └── GroundSlam [BoolValue = true]
└── LootTable [Folder, opcional]
    ├── Stone [StringValue = "Stone"]
    └── RareCore [StringValue = "GolemCore"]
```

O sistema aceita animações na pasta `Animations` ou Attributes como
`AttackAnimationId = "rbxassetid://123"`.

## Exemplo recomendado: Golem

| Attribute | Valor |
|---|---:|
| `Enabled` | `true` |
| `MonsterId` | `"StoneGolem"` |
| `MonsterType` | `"Golem"` |
| `DisplayName` | `"Golem de Pedra"` |
| `MaxHealth` | `180` |
| `WalkSpeed` | `8` |
| `DetectionRange` | `55` |
| `LoseTargetRange` | `75` |
| `LeashRange` | `50` |
| `RoamRadius` | `12` |
| `CanMove` / `CanRoam` / `CanChase` | `true` |
| `ReturnToSpawn` | `true` |
| `UsePathfinding` | `true` |
| `PathRecomputeInterval` | `1` |
| `StopDistance` | `4` |
| `AttackType` | `"Melee"` |
| `AttackDamage` | `22` |
| `AttackRange` | `7` |
| `AttackCooldown` | `1.8` |
| `AttackWindup` | `0.65` |
| `AttackRecovery` | `0.55` |
| `AttackHitboxSize` | `Vector3.new(9, 7, 10)` |
| `AttackOffset` | `Vector3.new(0, 0, -4)` |
| `Defense` | `5` |
| `DamageMultiplier` | `0.9` |
| `KnockbackResistance` | `0.85` |
| `StunResistance` | `0.6` |
| `CanBeStunned` / `CanBeKnockedBack` | `true` |
| `SpawnMode` | `"Solo"` |
| `MinimumIslandSize` | `"Medium"` |
| `SpawnChance` | `0.45` |
| `SpawnWeight` | `6` |
| `ScoreValue` | `10` |
| `CoinValue` | `14` |
| `HasGroundSlam` | `true` |
| `GroundSlamRadius` | `13` |
| `GroundSlamDamage` | `28` |
| `GroundSlamWindup` | `1.1` |
| `GroundSlamCooldown` | `9` |
| `CanBecomeCompanion` | `true` |
| `CompanionUnlockChance` | `0.08` |
| `CompanionImageId` | `""` |
| `CompanionScale` | `0.72` |

O `GroundSlam` mostra a área no chão durante o windup, pode ser interrompido por
stun e possui cooldown independente.

## Ataques e estados

`AttackType` aceita `Melee`, `Contact`, `Ranged` e `None`. O dano só acontece
depois do `AttackWindup`. Ataques melee validam a caixa espacial no instante do
impacto; ataques ranged validam distância e linha de visão.

A máquina de estados publica `MonsterState` no Model (`Idle`, `Roam`, `Chase`,
`Return`, `Attack`, `Ability` ou `Stunned`). `DetectionRange` inicia a perseguição
e `LoseTargetRange` mantém o alvo sem oscilar na borda.

## Loot avançado

Cada filho de `LootTable` usa:

- o valor de um `StringValue` ou o Attribute `ItemId`;
- `Weight` (padrão `1`);
- `Chance` entre `0` e `1` (padrão `1`);
- `MinAmount` e `MaxAmount` (padrão `1`).

`LootRolls` no Model define quantas seleções ponderadas ocorrem. O formato legado
`DropItemId` + `DropChance` continua funcionando. Também é aceito um Attribute
`LootTable` com JSON equivalente.

## Companheiros

Ao derrotar uma espécie ainda não possuída, o jogador tem 12% de chance padrão
de capturá-la. Configure por mob:

- `CanBecomeCompanion = false` para impedir captura;
- `CompanionUnlockChance` entre `0` e `1`;
- `CompanionXPValue` para o XP concedido por derrota;
- `CompanionDamage` para substituir opcionalmente o `AttackDamage` natural;
- `CompanionScale` entre `0.3` e `1.5` (padrão `0.72`);
- `CompanionImageId = "rbxassetid://..."` para a imagem da coleção.

Elites garantem no mínimo 25% de chance. O primeiro companheiro é equipado
automaticamente. É possível equipar até quatro espécies diferentes; todos os
companheiros equipados recebem o XP das vitórias creditadas ao dono.

O dano começa no `AttackDamage` natural da espécie e recebe `+4%` por nível.
Cada nível depois do primeiro também concede um ponto para uma destas estatísticas:

| Estatística | Efeito por ponto | Limite |
|---|---:|---:|
| Poder | `+5%` de dano | 10 |
| Velocidade de ataque | `-3%` de recarga | 10 |
| Agilidade | `+4%` de movimento | 10 |
| Alcance | `+0.6` stud | 10 |

O botão `COMPANHEIROS` abre a coleção, seleciona o mob, distribui pontos e permite
equipar ou desequipar. O servidor valida limite, propriedade, pontos e upgrades.
Os dados usam o schema 8 e migram automaticamente o antigo slot único.

### Alvos e movimento

O companheiro usa `Humanoid:MoveTo()` e conserva a velocidade, alcance, cooldown,
tipo de ataque e habilidades configuradas no Model. As variantes atuais mantêm:

- Slime Verde: melee;
- Slime Azul: projétil à distância;
- Slime Vermelho: morteiro em área;
- Slime Dourado: teleporte e melee;
- mobs genéricos: `Melee`, `Contact`, `Ranged`, `None` e `GroundSlam`.

Ele só ataca um `CombatTarget` que esteja perseguindo o dono (`AggroUserId` /
`TargetUserId`) ou que tenha sido atingido pelo dono (`LastDamagedByUserId`).
Nunca seleciona personagens ou companheiros. O alvo precisa permanecer a até
60 studs do dono; acima de 70 studs, ou depois de cair do mapa, o companheiro é
teletransportado de volta à sua posição na formação.

As imagens conhecidas também possuem campos vazios em
`ReplicatedStorage/CompanionCatalog`. O Attribute do Model tem prioridade e
permite cadastrar imagens de mobs futuros sem alterar a interface.

### Checklist obrigatório no Studio

1. Abrir dois jogadores e fazer cada um entrar em combate com um mob diferente.
2. Confirmar que cada equipe ignora o alvo exclusivo do outro jogador.
3. Testar Verde, Azul, Vermelho, Dourado e Golem para validar animações e rig.
4. Equipar quatro espécies, desequipar a posição intermediária e conferir a nova formação.
5. Afastar-se mais de 70 studs e derrubar um companheiro da ilha para validar o retorno.
6. Subir de nível, gastar pontos nas quatro estatísticas e reconectar para validar o save.
7. Carregar uma conta do schema 7 e confirmar a migração do companheiro antigo para o slot 1.
8. Preencher um `CompanionImageId` e verificar o retrato no computador, celular e controle.
