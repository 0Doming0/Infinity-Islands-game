# Monetizacao e marketing do MVP

## Principios

- Existe somente um tipo de NPC: **Mercador do Ceu**.
- O NPC concentra itens por moedas, recompensas gratuitas e acesso a loja
  premium.
- O jogo nunca abre uma compra automaticamente.
- O algoritmo prepara no maximo uma recomendacao e a destaca quando o jogador
  decide falar com o mercador.
- O renascimento e a unica excecao de local: ele aparece na tela de morte,
  porque o jogador nao consegue voltar fisicamente ao NPC naquele momento.
- A interface nunca exibe preco ficticio. O cliente consulta o preco atual do
  Roblox, incluindo preco regional ou teste de otimizacao.
- Nao existem descontos, estoque premium ou contadores falsos.

## Configuracao antes de publicar

Edite apenas `src/shared/MonetizationCatalog.lua` e substitua os IDs `0`.

| Produto | Tipo no Creator Hub | Preco inicial sugerido |
|---|---|---:|
| Renascimento seguro | Developer Product | 19 Robux |
| Asas Azure | Pass | 79 Robux |
| Asas Reais | Pass | 149 Robux |
| Asas Celestiais | Pass | 249 Robux |
| Expedicao do Tesouro | Developer Product | 49 Robux |
| Cacada de Elites | Developer Product | 49 Robux |
| Capa de Invisibilidade | Pass | 149 Robux |
| Pocao Permanente | Pass | 129 Robux |
| Slot de Companheiro | Developer Product | 79 Robux |
| Giro da Roleta | Developer Product | 19 Robux |

Os valores sao hipoteses de lancamento, nao descontos. Depois de haver volume
de compradores, use Managed Pricing e Price Optimization no Creator Hub.

## Produtos

### Renascimento seguro

Renasce sem perder as moedas retiradas pela derrota. A pontuacao da tentativa
continua encerrada. A opcao gratuita continua disponivel e perde 20% das
moedas.

### Asas

- Asas temporarias: 3 voos por 3.000 moedas.
- Azure: 5 segundos de voo.
- Reais: 7 segundos de voo.
- Celestiais: 9 segundos de voo.

As asas permanentes sao Passes e nao consumiveis. O voo e horizontal e possui
recarga, portanto nao substitui toda a progressao de parkour.

### Expedicao do Tesouro

Por 20 minutos, a chance base de Ilha do Tesouro sobe de 2% para 6% nas
janelas elegiveis. Como o mapa e compartilhado,
o beneficio e informado honestamente como beneficio da expedicao/servidor.
Compras adicionais estendem a duracao.

### Cacada de Elites

Por 20 minutos:

- aumenta a chance base de ilhas Elite de 12% para 21%;
- cada Elite derrotado pelo comprador possui 35% de chance de entregar uma
  recompensa extra equivalente a Bau Raro.

Compras adicionais estendem a duracao.

### Capa de Invisibilidade

Pass permanente. Ativacao voluntaria, 8 segundos de invisibilidade contra
inimigos e 90 segundos de recarga. Nao protege contra agua ou vazio.

### Pocao Permanente

Pass permanente e nao acumulavel. Concede +15 de vida maxima a cada tentativa.

### Slot de Companheiro

Developer Product que desbloqueia um slot por compra, ate quatro. A rota por
moedas continua disponivel com precos altos.

### Giro pago

As probabilidades sao exibidas antes da compra:

- 75% moedas;
- 15% reliquia;
- 10% espada;
- 0% companheiro.

Detalhamento dos resultados:

- Reliquias: Raio 3,846%; Fogo 3,846%; Gelo 3,462%; Pedra 3,846%.
- Espadas: Bronze 4,167%; Cristal 3,056%; Vazio 1,667%; Real 0,833%;
  Dragao 0,278%.
- Dentro dos 75% de moedas, o valor e uniforme entre o minimo e o maximo
  informados pela roleta para o nivel atual.
- Espada ou reliquia repetida vira a compensacao em moedas configurada no
  catalogo de recompensas.

Companheiros nao participam para impedir que um slime recebido por compra seja
transferido sem as verificacoes adicionais de item pago. O sistema consulta
`PolicyService`; contas ou regioes com restricao nao veem a compra como
disponivel. Se a consulta falhar em servidor publicado, o sistema bloqueia por
seguranca; somente o Studio possui uma excecao para testes locais.

### Giro por anuncio

O gancho existe no catalogo, mas fica desativado no MVP. Ative apenas depois de:

- a experiencia ser publica;
- alcancar a elegibilidade atual de Rewarded Video;
- configurar um Developer Product exclusivo para a recompensa;
- manter opt-in explicito e entregar a recompensa somente apos conclusao.

## Algoritmo contextual e segmentacao

A pontuacao final de cada produto e normalizada de 0 a 100 e combina:

- **60% comportamento e contexto do jogo**;
- **25% intencao observada dentro da sessao**;
- **15% Platform Spender Status**.

Comportamento e contexto consideram:

- mortes;
- baus abertos;
- Elites derrotados;
- curas usadas;
- companheiros capturados;
- giros gratuitos;
- nivel atual e slots de companheiro.

A intencao da sessao considera somente acoes reais no Mercador:

- abrir voluntariamente a loja;
- iniciar a compra de um produto;
- demonstrar interesse em produtos do mesmo contexto;
- compras feitas naquela categoria durante a sessao.

O servidor consulta `AnalyticsService:GetPlayerSegmentsAsync()` uma vez por
jogador e mantem o resultado somente em memoria. `Active` da um bonus moderado
de afinidade, principalmente para beneficios permanentes. `OtherPayer` e
neutro. O segmento nunca aumenta a quantidade de ofertas nem reduz cooldowns.

Se `HasData` for falso, ocorrer uma falha ou o status for `Unknown`, nenhum
perfil economico e presumido. Os pesos disponiveis sao renormalizados:

- comportamento e contexto: **70,6%**;
- intencao da sessao: **29,4%**.

Protecoes:

- nenhuma oferta antes de 3 minutos;
- tutorial precisa estar concluido;
- nenhuma recomendacao durante combate, estado caido, loja aberta ou perigo
  proximo da agua;
- intervalo minimo de 6 minutos;
- maximo de 2 recomendacoes por sessao;
- um produto ja mostrado nao se repete na sessao;
- **Agora nao** bloqueia o mesmo produto por 15 minutos;
- somente a maior pontuacao contextual e escolhida;
- o produto precisa atingir 42 pontos na escala final normalizada;
- o status economico fica apenas no servidor e nao e replicado em Attributes.

## Instrumentacao de teste

Os principais estados ficam em Attributes do jogador para inspecao no Studio:

- `OfferSignal_Deaths`;
- `OfferSignal_Chests`;
- `OfferSignal_Elites`;
- `OfferSignal_Heals`;
- `OfferSignal_Captures`;
- `OfferSignal_WheelSpins`;
- `MerchantOfferReady`;
- `MerchantOfferProductId`;
- `MerchantOffersShown`;
- `LastMonetizationPurchase`;
- `MonetizationPurchaseSerial`.

Antes do lancamento, teste:

1. compra concluida e cancelada de cada produto;
2. reconexao durante boosts;
3. dois compradores estendendo o mesmo boost;
4. conta com roleta paga restrita;
5. precos regionais exibidos no cliente;
6. morte com Developer Product;
7. limite de quatro slots;
8. asas no celular, teclado e controle;
9. capa contra Slimes, Mimicos, mobs genericos e Ground Slam;
10. Mercador sem estoque, mas com recompensas gratuitas e loja premium
    acessiveis.
