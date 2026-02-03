# vinishaderproject
project shader pipeline for mpv

## Como instalar os arquivos .glsl no mpv

### Linux/macOS

Pasta do usuário mpv: `~/.config/mpv/shaders/`

Comando de exemplo:

```bash
mkdir -p ~/.config/mpv/shaders && cp shaders/*.glsl ~/.config/mpv/shaders/
```

### Windows

Pasta do usuário mpv: `%APPDATA%\mpv\shaders\` (ex.: `C:\Users\<Você>\AppData\Roaming\mpv\shaders\`)

Copie os `.glsl` para esse diretório com Explorer ou PowerShell.

### Permissões

Em Linux/macOS garanta leitura:

```bash
chmod a+r ~/.config/mpv/shaders/*.glsl
```

---

## Configuração mpv recomendada (essenciais e opcionais)

Observação: ajustes externos em `mpv.conf` ajudam, mas os essenciais a seguir garantem que a pipeline opere corretamente.

**Essencial** (coloque em `~/.config/mpv/mpv.conf` ou equivalente):

```
vo=gpu-next
gpu-api=opengl
opengl-es=yes
fbo-format=rgba32f
vf=format=rgba
gpu-shader-cache=yes
```

**Recomendado** (melhora qualidade/linear pipeline — use se seu driver e GPU suportarem):

```
vo=gpu-next
gpu-api=opengl
opengl-es=yes
hwdec=auto-copy-safe
fbo-format=rgba32f
vf=format=rgba
video-output-levels=full
force-media-title=force_full_rgb
hdr-compute-peak=no
target-colorspace-hint=yes
scale=ewa_lanczos4sharpest
cscale=sinc
dscale=ewa_lanczos
tscale=sphinx
gamut-mapping-mode=linear
target-gamut=aces-ap0
target-trc=srgb
target-prim=aces-ap1
target-peak=1200
gpu-context=auto
gpu-shader-cache=yes
video-sync=display-resample
correct-downscaling=yes
sigmoid-upscaling=yes
linear-downscaling=yes
deband=no
interpolation=yes
dither-depth=auto
temporal-dither=yes
```

---

## Linha de execução (exemplo que carrega os 4 shaders em ordem)

```bash
mpv caminho/do/video.mp4 \
  --glsl-shader=~/.config/mpv/shaders/analise.glsl \
  --glsl-shader=~/.config/mpv/shaders/limpeza.glsl \
  --glsl-shader=~/.config/mpv/shaders/restauração.glsl \
  --glsl-shader=~/.config/mpv/shaders/upscale.glsl
```

---

# 📌 Visão geral do pipeline (ordem obrigatória)

**S1 -> S2 -> S3 -> S4**

A ordem é crítica. Cada estágio gera mapas e decisões que o próximo utiliza. Se você inverter ou remover etapas, o pipeline perde as referências internas e pode gerar artefatos ou falhar.

**Resumo dos estágios:**

- **S1 (analise.glsl)** — gera mapas analíticos (bordas, variância, exposição, movimento, estética). É o “cérebro” que guia os outros estágios.
- **S2 (limpeza.glsl)** — faz limpeza (denoise/deblock/deband) adaptativa usando os mapas do S1.
- **S3 (restauração.glsl)** — restaura micro-contraste, corrige gama, melhora cor e corrige YUV 4:2:0.
- **S4 (upscale.glsl)** — faz upscale híbrido, refine, TAA, sharpen, deband e ajustes finais.

---

# 🧭 Como ajustar a pipeline (guia prático)

A intenção desta documentação é ensinar você a **ajustar o resultado ao seu gosto**, sem perder estabilidade.
Os valores atuais já são um **equilíbrio entre qualidade e performance**, mas você pode montar **seus próprios presets** ajustando os parâmetros nos arquivos `.glsl`.

## 1) Regras básicas antes de mexer

✅ **Sempre preserve a ordem** S1 → S2 → S3 → S4.  
✅ **Ajuste um parâmetro por vez** e compare em cenas reais.  
✅ **Use cenas difíceis** (grãos, sombras, movimento rápido, pele).  
✅ **Se algo ficar “plástico” ou “lavado”**, diminua denoise/deblock.  
✅ **Se aparecer halo, ringing ou cintilação**, reduza sharpen, LCE ou TAA.  

---

# 🎛️ Entenda cada estágio e seus parâmetros (o que muda no resultado)

## ✅ S1 — `analise.glsl` (Mapas de decisão)

**O que este estágio faz**: cria mapas (borda, variância, movimento, estética, luminância) que controlam todo o pipeline. Se você desativa algo aqui, os próximos estágios ficam “cegos”.

**Principais ajustes e efeitos:**

- `ENABLE_TEMPORAL_ANALYSIS`
  - **Desativar**: menos estabilidade temporal e TAA mais fraco.
  - **Impacto**: pode reduzir peso da correção de movimento (útil em PCs fracos).

- `ENABLE_GOLDEN_ANALYSIS`
  - **Desativar**: perde análise estética (rosto/pele/contraste).
  - **Impacto**: limpeza pode ficar mais agressiva em áreas importantes.

- `ENABLE_LUMA_ANALYSIS`
  - **Desativar**: perde análise de sombra/midtones.
  - **Impacto**: mais risco de ruído cromático ou sombras mal tratadas.

- `LOW_LIGHT_THRESHOLD`
  - **Aumentar**: considera mais áreas como “baixa luz” → mais proteção.
  - **Diminuir**: sombras ficam mais expostas a limpeza e correções.

- `MOTION_SENSITIVITY`
  - **Aumentar**: detecta movimentos pequenos, mas pode gerar falsas detecções.
  - **Diminuir**: menos sensível, bom para conteúdo ruidoso.

- `EDGE_STRENGTH_FACTOR`
  - **Aumentar**: protege mais bordas (menos limpeza nelas).
  - **Diminuir**: bordas ficam mais “tratadas” (risco de blur).

- `GRID_DETECTION_MIN`
  - **Aumentar**: menos detecção de macroblocos.
  - **Diminuir**: mais agressivo contra macroblocos.

---

## ✅ S2 — `limpeza.glsl` (Denoise / Deblock / Deband)

**O que este estágio faz**: remove ruído feio e artefatos de compressão, tentando preservar textura legítima.

**Principais ajustes e efeitos:**

- `DENOISE_STRENGTH`
  - **Aumentar**: remove mais ruído (pode apagar textura).  
  - **Diminuir**: preserva grão e textura (mais ruído residual).

- `DEBLOCK_STRENGTH`
  - **Aumentar**: remove macroblocos fortes.  
  - **Diminuir**: preserva detalhes, mas pode deixar blocos visíveis.

- `DEBAND_STRENGTH`
  - **Aumentar**: reduz banding em gradientes.  
  - **Diminuir**: preserva leve granulação nos gradientes.

- `STRUCTURAL_PROTECTION_FACTOR`
  - **Aumentar**: protege bordas e estrutura.  
  - **Diminuir**: permite limpeza mais agressiva.

- `ENABLE_ANIME_CHAOS_SOLVER`
  - **Ativar**: melhora linhas e traços de anime.  
  - **Desativar**: conteúdo live-action pode ficar mais natural.

---

## ✅ S3 — `restauração.glsl` (Restauração de integridade)

**O que este estágio faz**: restaura micro-contraste, corrige gama, melhora cor e cuida de pele.

**Principais ajustes e efeitos:**

- `MICRO_CONTRAST_STRENGTH`
  - **Aumentar**: mais textura e “punch”, risco de halo.  
  - **Diminuir**: imagem mais suave.

- `GAMMA_NORMALIZATION`
  - **Aumentar**: corrige midtones “lavados”.  
  - **Diminuir**: mantém look mais original (mas pode ficar sem vida).

- `VIBRANCE_ENHANCEMENT`
  - **Aumentar**: cores mais vivas.  
  - **Diminuir**: visual mais neutro.

- `SKIN_TONE_PROTECTION`
  - **Aumentar**: protege pele, evita saturação excessiva.  
  - **Diminuir**: cores podem ficar mais fortes em pele.

- `YUV420_CORRECTION`
  - **Aumentar**: corrige subamostragem, melhora borda de cor.  
  - **Diminuir**: menos custo computacional, mas mais artefato de cor.

---

## ✅ S4 — `upscale.glsl` (Upscale + refinamento final)

**O que este estágio faz**: aplica upscale híbrido, corrige resíduos, aplica TAA, sharpen e ajustes finais.

**Principais ajustes e efeitos:**

- `UPSCALE_STRENGTH`
  - **Aumentar**: upscale mais agressivo.  
  - **Diminuir**: mais próximo do bilinear.

- `NOISE_CLEANUP_STRENGTH`
  - **Aumentar**: limpa ruído residual pós-upscale.  
  - **Diminuir**: preserva textura.

- `BANDING_REDUCTION`
  - **Aumentar**: reduz banding em gradientes.  
  - **Diminuir**: preserva textura/ruído fino.

- `SHARPNESS_LEVEL`
  - **Aumentar**: mais nitidez (risco de halo).  
  - **Diminuir**: mais natural e suave.

- `ENABLE_TEMPORAL_AA`
  - **Desativar**: remove TAA → menos ghosting, mais flicker.  
  - **Ativar**: imagem mais estável (risco de blur temporal).

- `FILM_LOOK_STRENGTH`
  - **Aumentar**: mais “cinematic look”.  
  - **Diminuir**: mais neutro.

---

# 🧩 Como criar presets personalizados

Aqui está um método simples para usuários intermediários/entusiastas:

### ✅ 1) Escolha o tipo de conteúdo
- **Anime/2D:** linhas nítidas, pouco ruído, cores sólidas.  
- **Live-action:** texturas orgânicas, pele realista.  
- **Conteúdo antigo / baixa qualidade:** ruído alto, blocos e banding.

### ✅ 2) Ajuste só 3 blocos principais primeiro
- **S2 (limpeza)** → controla ruído, blocos e banding.  
- **S3 (restauração)** → controla contraste, gama e cor.  
- **S4 (upscale)** → controla nitidez e estabilidade.

### ✅ 3) Exemplo de presets (ponto de partida)

**Preset: Anime nítido**
- S2: `DENOISE_STRENGTH` ↓, `DEBLOCK_STRENGTH` ↓, `ENABLE_ANIME_CHAOS_SOLVER` ON
- S3: `MICRO_CONTRAST_STRENGTH` ↑, `VIBRANCE_ENHANCEMENT` ↑
- S4: `SHARPNESS_LEVEL` ↑, `ENABLE_TEMPORAL_AA` ON

**Preset: Live-action natural**
- S2: `DENOISE_STRENGTH` médio, `DEBAND_STRENGTH` médio
- S3: `GAMMA_NORMALIZATION` médio, `SKIN_TONE_PROTECTION` ↑
- S4: `SHARPNESS_LEVEL` médio, `FILM_LOOK_STRENGTH` médio

**Preset: Conteúdo antigo / muito ruído**
- S2: `DENOISE_STRENGTH` ↑↑, `DEBLOCK_STRENGTH` ↑, `DEBAND_STRENGTH` ↑
- S3: `GAMMA_NORMALIZATION` ↑, `VIBRANCE_ENHANCEMENT` ↓
- S4: `NOISE_CLEANUP_STRENGTH` ↑, `BANDING_REDUCTION` ↑, `SHARPNESS_LEVEL` ↓

---

# ⚠️ Interações importantes entre estágios

Algumas combinações mudam bastante o resultado final:

- **Muito denoise (S2) + muito sharpen (S4)** → pode criar halos e aparência artificial.
- **LCE alto (S3) + Sharpen alto (S4)** → aumenta micro-detalhes, mas também o risco de ringing.
- **Denoise baixo (S2) + TAA alto (S4)** → ruído pode “vazar” e gerar shimmer.
- **Gamma alto (S3) + Brightness alto (S4)** → imagem pode ficar lavada/explodida.

---

# ✅ Dicas rápidas de ajuste por sintoma

- **Imagem “plástica”** → reduza `DENOISE_STRENGTH` (S2) e `NOISE_CLEANUP_STRENGTH` (S4).
- **Muitos blocos** → aumente `DEBLOCK_STRENGTH` (S2).
- **Banding visível** → aumente `DEBAND_STRENGTH` (S2) e `BANDING_REDUCTION` (S4).
- **Halo/contornos duros** → reduza `SHARPNESS_LEVEL` (S4) ou `MICRO_CONTRAST_STRENGTH` (S3).
- **Cores exageradas** → reduza `VIBRANCE_ENHANCEMENT` (S3).
- **Flicker em movimento** → aumente `MOTION_SENSITIVITY` (S1) ou `ENABLE_TEMPORAL_AA` (S4).

---

## Conclusão

Esta pipeline foi desenhada para ser **flexível e ajustável**, permitindo que você obtenha o equilíbrio ideal entre qualidade e performance.  
Os valores padrão já são um “meio termo” bem equilibrado, mas a ideia é justamente permitir que você **crie presets pessoais** para cada tipo de conteúdo.

Se quiser, você pode compartilhar seus presets e feedback para evoluir os valores-base no futuro.
