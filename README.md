# vinishaderproject
project shader pipeline for mpv

Como instalar os arquivos .glsl no mpv
Linux/macOS

Pasta do usuário mpv: ~/.config/mpv/shaders/

Comando de exemplo:

mkdir -p ~/.config/mpv/shaders && cp shaders/*.glsl ~/.config/mpv/shaders/

Windows

Pasta do usuário mpv: %APPDATA%\mpv\shaders\ (ex.: C:\Users\<Você>\AppData\Roaming\mpv\shaders\)

Copie os .glsl para esse diretório com Explorer ou PowerShell.

Permissões

Em Linux/macOS garanta leitura: chmod a+r ~/.config/mpv/shaders/*.glsl


Configuração mpv recomendada (essenciais e opcionais)
Observação: ajustes externos em mpv.conf ajudam, mas os essenciais a seguir garantem que a pipeline opere corretamente.

Essencial (coloque em ~/.config/mpv/mpv.conf ou equivalente):

vo=gpu-next
gpu-api=opengl
opengl-es=yes
fbo-format=rgba32f
vf=format=rgba
gpu-shader-cache=yes

Recomendado (melhora qualidade/linear pipeline — use se seu driver e GPU suportarem):

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


Linha de execução (exemplo que carrega os 4 shaders em ordem):

mpv caminho/do/video.mp4 \
  --glsl-shader=~/.config/mpv/shaders/analise.glsl \
  --glsl-shader=~/.config/mpv/shaders/limpeza.glsl \
  --glsl-shader=~/.config/mpv/shaders/restauração.glsl \
  --glsl-shader=~/.config/mpv/shaders/upscale.glsl

  Resumo do fluxo e responsabilidades de cada shader
analise.glsl (S1) — "Juiz Neuro-Estético": gera mapas analíticos blindados (GRX_MAPS, GRX_TEMPORAL, GRX_GOLDEN, GRX_LUMA, GRX_COLOR_LINEAR). Produz os dados que guiam todos os passos seguintes.

limpeza.glsl (S2) — "Firewall / Cirurgião de Fluxo": usa os mapas do S1 para denoise adaptativo, deblocking, debanding e produzir uma saída segura (STAGE2_OUTPUT). Também contém hooks para polir fluxo (GRX_FLOW_REFINED).

restauração.glsl (S3) — "Restauração de Integridade": aplica LCE, normalização de gama, correções YUV420, proteção de pele e prepara um linear robusto (STAGE3_ENHANCED). Também extrai mapas de detalhe para reinjeção.

upscale.glsl (S4) — "Upscale & Tone Mapping": faz upscale híbrido, refinamento CNN, denoise pós-upscale, TAA, sharpen e gera a saída final (OUTPUT). Usa todos os mapas e a confiança do pipeline para decidir técnicas.

A ordem importa: S1 -> S2 (+S2 hooks) -> S3 (+S3 hooks) -> S4. Romper ordem quebra bindings e leva a artefatos ou falha.



Sumário dos arquivos e categorias de parâmetros

analise.glsl (S1) — parâmetros de análise e segurança, thresholds de detecção e sensibilidade

limpeza.glsl (S2) — parâmetros de limpeza/denoise, modos (anime), proteções estruturais

flow_refine (hook dentro de S2) — parâmetros de polimento de fluxo (coerência, raio)

restauração.glsl (S3) — parâmetros de restauração, LCE, vibrance, correção YUV420, proteção de pele

detail_extractor (hook dentro de S3) — parâmetros de aceitação de detalhe e purificação cromática

upscale.glsl (S4) — parâmetros de upscale (Lanczos/CNN), sharpening, TAA, film grain, saída linear

Parâmetros de segurança e utilitários comuns (GRX_UTILS, GRX_SAFETY_SYSTEM, GRX_COLOR_MANAGEMENT) — macros que não se deve alterar sem motivo

Cada seção abaixo detalha os parâmetros do arquivo correspondente.

1) analise.glsl (S1) — parâmetros principais
Objetivo: gerar mapas analíticos blindados que guiam toda a pipeline (GRX_MAPS, GRX_TEMPORAL, GRX_GOLDEN, GRX_LUMA, GRX_COLOR_LINEAR).

Parâmetros listados (existentes no seu código):

ENABLE_TEMPORAL_ANALYSIS (0 / 1)

O que faz: ativa/desativa a análise temporal (comparação com frame anterior, detecção de motion, flicker).

Margem segura: 1 (ativado) para uso normal; 0 apenas para debugging ou se precisar economizar performance.

Pode desativar? Sim, sem quebrar o pipeline, porém S2/S4 que dependem de mapas temporais terão menos informação e podem reduzir qualidade de blending e detecção de flicker.

Risco: se desligado, efeitos temporais e decisões baseadas em estabilidade serão menos precisos; TAA/flow refinement perdem dados.

ENABLE_GOLDEN_ANALYSIS (0 / 1)

O que faz: ativa cálculo de métricas estéticas (grid, entropy, harmonic balance, aesthetic score).

Margem segura: 1.

Pode desativar? Sim, mas perderá sinais semânticos que guiam preservação de pele/áreas estéticas; S2/S3 podem tratar tudo de forma mais agressiva, resultando em detalhes perdidos ou oversmoothing.

Risco: perda de decisões “emocionais” (preservar rostos) e reinjeção de detalhe mais ruim.

ENABLE_LUMA_ANALYSIS (0 / 1)

O que faz: produz mapas de luminância/zonal (shadow dirt, chroma risk, mid-tone density).

Margem segura: 1.

Pode desativar? Desligar prejudica correções de sombra e detecção de risco cromático usadas em S3/S4.

Risco: pior correção de sombras/ruído cromático; degrade perceptível em áreas escuras.

ENABLE_SAFETY_CHECKS (0 / 1)

O que faz: ativa verificações anti-NaN/Inf, validações de UV e fallback seguros.

Margem segura: 1 (sempre).

Pode desativar? NÃO recomendado.

Por que não mudar: remove as proteções que evitam que valores corruptos se propaguem e causem falhas ou artefatos extremos.

LOW_LIGHT_THRESHOLD (float — ex.: 0.15)

O que faz: limiar para classificar baixa luminosidade; influencia exposure map e regras de proteção de sombras.

Faixa segura: 0.05 — 0.30.

Pode desativar? Não aplicável; pode ajustar.

Risco: valor muito alto classifica áreas normais como “low light”, acionando proteções excessivas; muito baixo pode ignorar áreas que requerem tratamento.

MOTION_SENSITIVITY (float — ex.: 1.2)

O que faz: multiplica a diferença de luma usada para gerar motion.

Faixa segura: 0.6 — 2.0.

Ajuste prático: diminuir para reduzir falsas detecções em fontes com ruído; aumentar para detectar movimentos fracos.

Risco: muito alto = ativa proteção temporal indevida (piora blending, flicker detection falsa).

EDGE_STRENGTH_FACTOR (float — ex.: 1.5)

O que faz: amplifica força de borda detectada; impacta preservação de detalhes em etapas seguintes.

Faixa segura: 0.5 — 3.0 (teste cauteloso > 2.0).

Risco: valores altos transformam texturas em “bordas” e causam excesso de proteção (pouca limpeza em texturas). Valores muito baixos reduzem proteção e aumentam risco de halos.

VARIANCE_THRESHOLD (float — ex.: 0.001)

O que faz: limite mínimo para variância; evita divisões por zero e garante estabilidade das métricas.

Faixa segura: 1e-6 — 0.01.

Pode desativar? Não.

Risco: aumentar demais elimina sensibilidade a pequenas variações; diminuir demais expõe a ruído numérico se funções fizerem divisões.

GRID_DETECTION_MIN (float)

O que faz: limiar mínimo para dizer que há grid/macrobloco.

Faixa segura: 0.05 — 0.2.

Ajuste: aumentar se detectar falsos-positivos em texturas naturais; diminuir para detectar grades mais sutis.

AESTHETIC_SENSITIVITY (float — ex.: 1.1)

O que faz: multiplica influência do score estético nas decisões (ex.: boost de confiança em áreas bonitas).

Faixa segura: 0.5 — 1.5.

Risco: muito alto pode fazer o sistema privilegiar estética e negligenciar limpeza onde necessário.

CONFIDENCE_FALLBACK (float — ex.: 0.5)

O que faz: valor default de confiança quando PREV ou outros dados não estão disponíveis.

Faixa segura: 0.0 — 1.0.

Risco: valor muito alto pode forçar processamento quando deveria haver fallback seguro; valor muito baixo pode desligar recursos úteis.

Constantes áureas (GOLDEN_RATIO, GOLDEN_CONJUGATE, etc.)

O que fazem: usadas em amostragem em espiral, sampling patterns e heurísticas; não altere.

Razão: matematicamente selecionadas para padrões de amostragem; mudar causa comportamento imprevisível.

Parâmetros internos adicionais (funções utilitárias) não devem ser alterados a menos que você entenda implicações numéricas.

2) limpeza.glsl (S2) — parâmetros principais
Objetivo: aplicar denoise adaptativo, deblocking, debanding, reconstrução e produzir STAGE2_OUTPUT. Contém modo anime, proteções e hooks de fluxo.

Parâmetros listados:

ENABLE_ADAPTIVE_DENOISE (0 / 1)

O que faz: ativa NL-Means adaptativo/denoise estrutural.

Margem segura: 1.

Pode desativar? Sim, para debugging ou performance; se desligar, o pipeline perde capacidade de limpar ruído estrutural e dependerá mais do S3/S4.

Risco: desativar pode deixar ruído evidente; ativar mantém textura mas custo GPU é maior.

ENABLE_DIRECTIONAL_DEBLOCK (0 / 1)

O que faz: ativa deblocking direcional (suaviza blocos seguindo orientação dominante).

Margem segura: 1 para streams com blocos; 0 se fonte não tiver compressão.

Risco: em imagens com linhas finas, deblocking forte pode borrar linhas.

ENABLE_GRADIENT_DEBAND (0 / 1)

O que faz: ativa debanding com base em gradientes e máscaras emocionais.

Margem segura: 1.

Risco: combinação com deband forte pode introduzir micro-ruído/dither perceptível.

ENABLE_CNN_LIGHT_RECON (0 / 1)

O que faz: ativa trecho leve de reconstrução inspirado em CNN (simulado no shader).

Margem segura: 1 se quiser reconstrução; 0 para menor custo.

Risco: simulação de CNN envolve operações repetidas — custo, e em casos de baixa confiança pode reintroduzir artefatos.

ENABLE_DETAIL_RECONSTRUCTION (0 / 1)

O que faz: habilita reinjeção/recuperação de detalhe fina.

Margem segura: 1.

Risco: se combinada com denoise agressivo pode criar contradição (remover e re-injetar), mas geralmente é desejado.

ENABLE_MULTI_VECTOR_POLISH (0 / 1)

O que faz: polimento multi-vetor (kinetic/flow polishing).

Margem segura: 1.

Risco: aumenta custo; em streams estáticos pouco útil.

ENABLE_SAFETY_CHECKS (0 / 1)

Igual ao S1 — não desative.

ENABLE_BRIGHT_AREA_PROTECTION (0 / 1)

O que faz: proteção extra para highlights/brights.

Margem segura: 1.

Risco: desligar pode causar clipping/overcorrection em áreas muito claras.

ENABLE_ANIME_CHAOS_SOLVER (0 / 1)

O que faz: ativa ramo específico que trata traços/flat colors (anime).

Margem segura: 1 para conteúdo 2D; 0 para live-action.

Risco: ativado em live-action pode suavizar e “achar” linhas onde não há, ou aplicar heurísticas inadequadas.

DENOISE_STRENGTH (float — ex.: 0.85)

O que faz: intensidade da limpeza.

Faixa prática: 0.4 — 0.95.

Ajuste prático: filmes com grão: 0.4–0.7; streams ruins: 0.8–0.95.

Risco: valor alto remove textura; valor baixo mantém ruído.

DEBLOCK_STRENGTH (float — ex.: 0.90)

O que faz: força do deblocking.

Faixa prática: 0.5 — 1.0.

Risco: excesso borra detalhes.

DEBAND_STRENGTH (float — ex.: 0.65)

O que faz: intensidade de debanding/dither.

Faixa prática: 0.3 — 0.9.

Risco: alto demais pode criar micro-ruído e “texturizar” áreas originalmente suaves.

RECONSTRUCTION_STRENGTH (float — ex.: 0.70)

O que faz: peso da reconstrução leve (reintrodução de detalhe).

Faixa prática: 0.2 — 0.9.

Risco: alto = possíveis artefatos reconstruídos; baixo = detalhe não recuperado.

DETAIL_STRENGTH (float — ex.: 0.35)

O que faz: força da preservação ou reintrodução de micro-detalhe.

Faixa prática: 0.1 — 0.6.

SHADOW_NUKE_LEVEL, CHROMA_NUKE_STRENGTH, FLAT_AREA_DEBAND_THRESHOLD, STRUCTURAL_PROTECTION_FACTOR

O que fazem: parâmetros de controle para tratamento em sombras, risco cromático, thresholds de banding e proteção de estrutura.

Margens seguras:

SHADOW_NUKE_LEVEL: 0.05 — 0.2 (muito alto “mata” grão em sombra).

CHROMA_NUKE_STRENGTH: 0.3 — 1.0 (alto reduz cromatic noise em sombras; cuidado com pele).

FLAT_AREA_DEBAND_THRESHOLD: 0.01 — 0.05 (baixa para cenas texturadas, alta para sky-like).

STRUCTURAL_PROTECTION_FACTOR: 0.5 — 1.0 (não reduzir abaixo ~0.4).

Constantes áureas (mantidas) e macros utilitárias

Não alterar.

Notas S2: muitos parâmetros são adaptativos (usam golden maps e maps do S1). Alterações nos pesos/forças interagem com S3/S4 — ajuste iterativo.

3) Flow refine (S2.5 hook) — parâmetros de refinamento de fluxo
Objetivo: refinar GRX_FLOW (vetor de movimento) para uso em TAA, kinetic cleaning e smear.

Parâmetros e comportamento:

Limites de confiança (maps.a thresholds) usados dentro do código

O que fazem: determinam se o fluxo é considerado válido para refinamento.

Margem segura: manter thresholds conservadores (ex.: 0.05 — 0.2).

Risco: aceitar fluxo com baixa confiança causa ghosting e smear.

radius (int) / coherence weights

O que fazem: controlam quantos vizinhos são combinados e peso espacial.

Faixa prática: radius = 1–2 (depende confiança).

Risco: radius alto suaviza demais (perde detalhe de movimento); radius baixo pode deixar ruído no fluxo.

variance_w, coherence_w (pesos)

O que fazem: priorizam vizinhos coerentes ou com baixa variance.

Ajuste prático: valores altos para coherence reduzem influência de vizinhos incoerentes.

Risco: valores extremos resultam em fluxo instável ou perda de suavidade.

fallback behavior: quando confidence baixo retornam zero flow

Importante: não mexer em política de fallback sem considerar TAA e kinetic cleaning.

Recomendação: deixar parâmetros adaptativos (como no arquivo) e ajustar apenas se observar ghosting persistente ou erro sistemático de reprojeção.

4) restauração.glsl (S3) — parâmetros principais
Objetivo: restaurar micro-contraste, normalizar gama, corrigir YUV 4:2:0, proteger pele e gerar STAGE3_ENHANCED (linear).

Parâmetros listados:

MICRO_CONTRAST_STRENGTH (float — ex.: 0.75)

O que faz: força de LCE (Local Contrast Enhancement).

Faixa prática: 0.2 — 0.9.

Risco: alto promove halos e enfatiza ruído; baixo deixa imagem suave.

GAMMA_NORMALIZATION (float — ex.: 0.80)

O que faz: aplica normalização adaptativa de gama em midtones.

Faixa prática: 0.0 — 1.0.

Risco: se conteúdo já tiver correção de gama/HDR, pode causar clipping ou alterações colorimétricas. Em geral, testar com e sem para ver impacto.

VIBRANCE_ENHANCEMENT (float — ex.: 0.75)

O que faz: aumento inteligente de saturação guiado por maps.

Faixa prática: 0.0 — 1.0.

Risco: alta saturação pode alterar tonalidade de pele; SKIN_TONE_PROTECTION mitiga isso.

SKIN_TONE_PROTECTION (float — ex.: 0.95)

O que faz: peso de proteção de tons de pele.

Margem segura: 0.7 — 1.0; normalmente manter alto (0.9+) é recomendado.

Nunca defina muito baixo se o objetivo é preservar aparência natural da pele.

YUV420_CORRECTION (0 / 1)

O que faz: corrige artefatos de croma de subamostragem 4:2:0.

Usar se a fonte for codificada YUV 4:2:0 (streams, arquivos H264/HEVC). Se a fonte for RGBA/4:4:4, desligue para evitar leituras desnecessárias que podem suavizar cor.

Risco: em fontes 4:4:4, ligar pode introduzir smoothing indesejado.

MOTION_ADAPTIVE_STRENGTH, EDGE_PROTECTION_STRENGTH, LCE_RADIUS, LCE_CURVE_STEEPNESS, MAX_GAMMA_EXPANSION, QUALITY_CLAMP_THRESHOLD

O que fazem: controlam adaptação a movimento, proteção em bordas, comportamento da curva S local, limites de expansão de gama e limiares de qualidade.

Recomenda-se NÃO alterar os valores internos como MAX_GAMMA_EXPANSION e QUALITY_CLAMP_THRESHOLD sem teste; eles previnem clipping e artefatos.

Funções de utilitários (sRGB_to_linear, linear_to_sRGB, saturação, blueNoise)

Não alterar.

Parâmetros que devem permanecer: SKIN_TONE_PROTECTION, QUALITY_CLAMP_THRESHOLD, limites de gama e normas de proteção de sombra.

5) detail_extractor (S3.5 hook) — parâmetros de reinjeção de detalhe
Objetivo: extrair delta entre original e estágio limpo, purificar cromaticamente e produzir máscara/aceitação para reinjeção no S4.

Parâmetros e implicações:

stream_confidence threshold (e.g., early return se < 0.2)

O que faz: evita extrair detalhes em streams de baixa confiança (ruidosos).

Recomendação: manter threshold conservador (~0.2). Reduzir permite mais detalhe mas pode reintroduzir ruído.

chroma_allowance (smoothstep(0.6,0.9,aesthetic_score))

O que faz: permite reintroduzir detalhe colorido em áreas esteticamente relevantes (ex.: rostos).

Ajuste prático: valores mais permissivos devolvem cor, útil em cenas com maquiagem/pele com sardas; arrisca reintroduzir cromatic noise.

shadow_seal (smoothstep(0.05,0.25,brightness))

O que faz: evita reinjeção de detalhe em sombras profundas.

Não reduzir: previne reintrodução de ruído em pretos.

acceptance_mask formula (texture_score + edge_restore) e multiplicadores (shadow_seal, stream_confidence)

O que faz: controla quanto do detail_delta entra no OUTPUT.

Ajuste prático: aumentar acceptance_mask aumenta “pop” de textura; cuidado com ruído em fundofrio.

Parâmetros a não mexer sem testes: limites que previnem reinjeção em sombras profundas e threshold de confiança.

6) upscale.glsl (S4) — parâmetros principais
Objetivo: realizar upscale híbrido com proteção contra ringing, refinamento CNN, denoise pós-upscale, TAA, sharpening adaptativo, film look e saída final (linear ou sRGB dependendo de OUTPUT_LINEAR_FOR_MPV).

Parâmetros listados:

UPSCALE_FACTOR (float — ex.: 2.0)

O que faz: fator de escala.

Faixa segura: 1.5 — 4.0 (maiores valores exigem muito VRAM e computação).

Risco: usar 4.0 em GPUs com pouca VRAM pode causar falhas; também aumenta tempo de processamento.

UPSCALE_STRENGTH (float — ex.: 0.65)

O que faz: mistura/força do algoritmo híbrido (Lanczos + CNN refinamento).

Faixa prática: 0.3 — 0.9.

Risco: alto aumenta possibilidade de ringing; baixo pode deixar upscale simples (bicubic).

NOISE_CLEANUP_STRENGTH (float — ex.: 0.75)

O que faz: força de limpeza pós-upscale.

Faixa: 0.3 — 1.0.

Risco: alto demais suaviza detalhes.

BANDING_REDUCTION (float — ex.: 0.80)

O que faz: reduz banding em áreas lisas.

Faixa: 0.2 — 0.9.

Risco: pode “criar” micro-ruído e mascarar textura.

BRIGHTNESS_ADJUSTMENT, CONTRAST_ENHANCEMENT, GAMMA_ADJUSTMENT

O que fazem: controles do Tone Mapping Yin-Yang.

Margens: BRIGHTNESS_ADJUSTMENT ≈ -0.3 — 1.0 (positive = brighten), CONTRAST_ENHANCEMENT 0.0 — 1.0; GAMMA_ADJUSTMENT ≈ -0.2 — 0.2.

Risco: ajustes errados afetam mapeamento tonal global e saturação.

SHARPNESS_LEVEL (float — ex.: 0.60)

O que faz: intensidade do sharpening adaptativo.

Faixa: 0.0 — 1.0.

Recomendações: reduzir em conteúdo com movimento (shimmer); combinar com TAA.

Risco: alto cria halos e shimmering.

MOTION_STABILITY, TAA_STRENGTH, TAA_MOTION_THRESHOLD

O que fazem: controlam estabilidade temporal e força do TAA.

Faixa: TAA_STRENGTH 0.5 — 1.0; TAA_MOTION_THRESHOLD 0.05 — 0.2.

Risco: TAA fraco → ghosting; TAA forte → suavização excessiva.

FILM_LOOK_STRENGTH, ENABLE_FILM_GRAIN, FILM_GRAIN_INTENSITY, FILM_GRAIN_CONTRAST

O que fazem: adicionam granulação cinematográfica e efeitos de smear.

Faixa prática: FILM_LOOK_STRENGTH 0.0 — 0.5, FILM_GRAIN_INTENSITY 0.05 — 0.25.

Risco: abusar mascara detalhes finos e reintroduz ruído de forma perceptível.

ENABLE_HYBRID_UPSCALE, ENABLE_MOTION_COMP, ENABLE_POST_UPSCALE_CLEAN, ENABLE_ADAPTIVE_SHARPEN, ENABLE_TEMPORAL_AA, ENABLE_DIRECTIONAL_SMEAR

O que fazem: ligam/desligam grandes blocos de lógica.

Recomendações: manter ENABLE_HYBRID_UPSCALE = 1 para qualidade; ENABLE_MOTION_COMP = 1 se GRX_FLOW_REFINED presente; desativar blocos apenas para debugging ou performance.

LANCZOS_RADIUS_BASE, LANCZOS_ANTI_RINGING

O que fazem: controlam comportamento do kernel Lanczos e anti-ringing.

NÃO alterar sem testes — impactam ringing e estabilidade.

Risco: aumentar radius sem anti-ring provoca ringing forte; modificar anti-ring mal = perda de detalhe.

CNN_REFINEMENT_STRENGTH, CNN_ITERATIONS_DEFAULT, CNN_CONVERGENCE_RATE

O que fazem: parâmetros do refinamento iterativo (simulação de CNN).

Risco: numero alto de iterações aumenta custo drásticamente; valores mal escolhidos geram overshoot/nan se não houver clamp. Não mexer sem benchmarking.

SAFETY_FALLBACK, MIN_QUALITY_THRESHOLD, BASE_MARGIN

O que fazem: fallback seguro quando detecta artefatos; limites de qualidade da saída.

Deixar como está — protegem saída final. Desativar causa risco de output entregue com qualidade baixa ou com artefatos.

OUTPUT_LINEAR_FOR_MPV (0 / 1)

O que faz: quando 1, o shader retorna linear (assume mpv configurado para pipeline linear); quando 0, converte para sRGB antes de saída.

Margem segura: 1 se mpv.conf tiver gamut-mapping-mode=linear e fbo-format=rgba32f; caso contrário 0.

Risco: inconsistencia entre essa flag e mpv.conf gera cores erradas, clipping, brilho incorreto.

Paramêtros de dither/noise e smear (blueNoise scale, WASHED_RUBBER_STRENGTH, SMEAR_FLOW_FACTOR_NEW)

O que fazem: geram e aplicam granulação e smear direcional.

Ajuste com cuidado; desative se quiser saída “limpa” sem efeito film.

7) Parâmetros de segurança e macros comuns (não alterar)
Existem macros/funções e defines compartilhados:

GRX_UTILS_DEFINED, GRX_SAFETY_SYSTEM_DEFINED, GRX_COLOR_MANAGEMENT_DEFINED

São guards que previnem redefinição de utilitários entre arquivos. Não remova.

is_texture_valid(...), sanitize_metrics(...), validate_s1_data(...)

Funções centrais de saneamento e validação. NÃO remover ou simplificar.

Conversões de cor: sRGB_to_linear, linear_to_sRGB

Essas funções devem existir e ser usadas consistentemente. Mudar sem rever toda pipeline causa corrupção de cor.

Blue noise / ELU shaper / hsv2rgb / rgb2hsv

Utilitários matemáticos; não mexer os coeficientes básicos.

Detect_processing_artifacts (e variantes nas versões)

Mecanismo crítico para fallback soft quando processo gera erro; não desabilitar.

Resumo: qualquer alteração nestes núcleos deve ser acompanhada de testes extensivos e de uma revisão de toda a cadeia.

8) Classificação prática dos parâmetros para manutenção e ajuste
Para priorizar o que tocar:

Ajustar frequentemente (boa relação impacto/segurança)

DENOISE_STRENGTH (S2) — influencia visual muito e é seguro testar

DEBLOCK_STRENGTH (S2) — ajustável por cenário de compressão

DEBAND_STRENGTH (S2 / S4) — ajustável para skies/céus

MICRO_CONTRAST_STRENGTH (S3) — para realce de midtones

VIBRANCE_ENHANCEMENT (S3) — estética pessoal

UPSCALE_FACTOR (S4) — controle de resolução/recursos

SHARPNESS_LEVEL (S4) — ajuste fino pós-upscale

Ajustes intermediários (exigem testes)

MOTION_SENSITIVITY (S1) — afeta decisions temporais

EDGE_STRENGTH_FACTOR (S1) — protege demais se alto

RECONSTRUCTION_STRENGTH (S2), DETAIL_STRENGTH (S2) — interação com S3

GAMMA_NORMALIZATION (S3) — pode clippar highlights

NOISE_CLEANUP_STRENGTH (S4) — importante para pós-upscale

Não recomendado alterar sem conhecimento profundo (não tocar normalmente)

ENABLE_SAFETY_CHECKS e implementação de is_texture_valid / sanitize_metrics

OUTPUT_LINEAR_FOR_MPV sem ajustar mpv.conf

LANCZOS_RADIUS_BASE, LANCZOS_ANTI_RINGING

CNN_ITERATIONS_DEFAULT, CNN_CONVERGENCE_RATE

QUALITY_CLAMP_THRESHOLD, MAX_GAMMA_EXPANSION

STRUCTURAL_PROTECTION_FACTOR (reduzir muito pode destruir bordas)

9) Recomendações práticas de workflow para ajustar parâmetros
Versão de controle: mantenha um repositório com commits antes de qualquer alteração. Use tags (vX.Y) para marcar estados testados.

Teste “triple set”: para cada alteração, teste em:

Cena estática (paisagem/sky)

Close de rosto (pele)

Cena com movimento (esportes / carro)

Mude apenas 1 parâmetro por vez. Documente com comentário no commit: “Ajuste X: DENOISE_STRENGTH = 0.80 — resultado: ...”

Se notar halos/ ringing/ghosting:

Halos → reduzir SHARPNESS_LEVEL / MICRO_CONTRAST_STRENGTH / UPSCALE_STRENGTH

Ringing → aumentar LANCZOS_ANTI_RINGING (com cautela) ou reduzir UPSCALE_STRENGTH

Ghosting → ajustar MOTION_SENSITIVITY / TAA_MOTION_THRESHOLD / GRX_FLOW_REFINED parâmetros

Para performance: desative módulos pesados (ENABLE_CNN_LIGHT_RECON, ENABLE_MULTI_VECTOR_POLISH) somente se necessário. Meça FPS/VRAM antes/depois.

Para replicabilidade: inclua mpv.conf usado nos testes no repositório (config/mpv.conf) e documente versão mpv e driver GPU.

10) Checklist rápido — parâmetros que você nunca deve desativar completamente
ENABLE_SAFETY_CHECKS (qualquer shader)

sanitize_metrics / validate_s1_data / is_texture_valid

Conversões de cor essenciais (sRGB_to_linear / linear_to_sRGB) a não ser que você replaneje pipeline inteira

OUTPUT_LINEAR_FOR_MPV inconsistente com mpv.conf

LIMIAR DE CONFIDENCE (stream_confidence) completamente removido (mantê-lo evita aplicar processamento a dados inválidos)

11) Exemplos de ajustes recomendados por cenário (valores sugeridos)
Stream YouTube muito compactado (blocky, chroma noise)

S1: MOTION_SENSITIVITY = 1.2 (ou manter)

S2: DENOISE_STRENGTH = 0.90, DEBLOCK_STRENGTH = 0.95, DEBAND_STRENGTH = 0.7

S3: YUV420_CORRECTION = 1, MICRO_CONTRAST_STRENGTH = 0.6

S4: UPSCALE_FACTOR = 2.0, NOISE_CLEANUP_STRENGTH = 0.8, SHARPNESS_LEVEL = 0.5

Filme 35mm com grão

S2: DENOISE_STRENGTH = 0.45, DEBLOCK_STRENGTH = 0.6, DEBAND_STRENGTH = 0.4

S3: MICRO_CONTRAST_STRENGTH = 0.75, SKIN_TONE_PROTECTION = 0.98, VIBRANCE_ENHANCEMENT = 0.5

S4: ENABLE_FILM_GRAIN = 1, FILM_GRAIN_INTENSITY = 0.12, SHARPNESS_LEVEL = 0.45

Anime / 2D

S2: ENABLE_ANIME_CHAOS_SOLVER = 1, DENOISE_STRENGTH = 0.6, DEBLOCK_STRENGTH = 0.4

S3: YUV420_CORRECTION = 0 (se 4:4:4), VIBRANCE_ENHANCEMENT = 0.6

S4: SHARPNESS_LEVEL = 0.35, UPSCALE_FACTOR = 2.0

Esportes / alto movimento

S1: MOTION_SENSITIVITY = 1.0 (ou menor)

S2: DENOISE_STRENGTH = 0.6

S4: TAA_MOTION_THRESHOLD = 0.12, SHARPNESS_LEVEL = 0.35, ENABLE_TEMPORAL_AA = 1


