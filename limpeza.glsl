// ===================================================================================
// S3_enhancement.glsl — Módulo de Restauração de Integridade para Conteúdo Destruido
// ===================================================================================
// Licença: MIT / GPLv3 — Código aberto, auditável, modular
// Autor: Pipeline GRX - Estágio 3 com Restauração de Integridade (Nova Abordagem)
// ===================================================================================
// OBJETIVO: Restaurar a integridade do sinal para entregar ao mpv um conteúdo limpo
// SAÍDA: STAGE3_ENHANCED (RGBA): .rgb=imagem restaurada em sRGB, .a=restoration_confidence
// ===================================================================================
// PRINCÍPIO FUNDAMENTAL:
// ✅ NÃO COMPETIR com o mpv (--target-trc=srgb)
// ✅ ENTREGAR um sinal limpo com micro-contraste restaurado, gama corrigida e cores naturais
// ✅ DEIXAR o mpv fazer seu trabalho final de mapeamento de tom e HDR
// ===================================================================================
// REGRAS DE OURO IMPLEMENTADAS:
// ✅ Remoção completa do HDR simulado (conflita com o mpv)
// ✅ Restauração de micro-contraste com LCE (Local Contrast Enhancement)
// ✅ Normalização adaptativa de gama para mid-tones esmagados
// ✅ Sistema de vibrance inteligente (não saturação global)
// ✅ Correção avançada de subamostragem YUV 4:2:0
// ✅ Proteção robusta de tons de pele
// ✅ Anti-aliasing direcional com preservação de detalhes
// ✅ Sistema de ruído estético para mascaramento natural
// ✅ Integração completa com mapas do S1/S2 para decisões inteligentes
// ===================================================================================
// -------------------------
// 3.1 🔧 CONFIGURAÇÕES PRINCIPAIS - CONTROLES DO USUÁRIO
// -------------------------
// PARÂMETROS PRINCIPAIS CONTROLADOS PELO USUÁRIO (0.0-1.0)
#define MICRO_CONTRAST_STRENGTH  0.75  // Força da restauração de micro-contraste (0.0=desligado, 1.0=máximo)
#define GAMMA_NORMALIZATION      0.80  // Força da normalização de gama (0.0=desligado, 1.0=completa)
#define VIBRANCE_ENHANCEMENT     0.75  // Força do vibrance inteligente (0.0=natural, 1.0=vibrante)
#define SKIN_TONE_PROTECTION     0.95  // Proteção de tons de pele (0.0=desligado, 1.0=máximo)
#define YUV420_CORRECTION        1.0   // 0.0=desligado, 1.0=correção completa
#define MOTION_ADAPTIVE_STRENGTH 0.70  // Adaptação a movimento (0.0=conservador, 1.0=agressivo)
#define EDGE_PROTECTION_STRENGTH 0.90  // Proteção contra perda de detalhes em bordas
// PARÂMETROS INTERNOS (não ajuste a menos que saiba o que está fazendo)
#define LCE_RADIUS               2.0   // Raio do LCE (Local Contrast Enhancement)
#define LCE_CURVE_STEEPNESS      1.2   // Inclinação da curva S para mid-tones
#define VIBRANCE_BASE_BOOST      1.15  // Boost base para cores desbotadas
#define VIBRANCE_PROTECTION      0.30  // Proteção para cores já saturadas
#define GAMMA_BASE_ADJUST        1.10  // Fator de ajuste de gama base
#define GAMMA_ADAPTIVE_FACTOR    0.25  // Fator de adaptação para áreas problemáticas
#define SKIN_TONE_RANGE_MIN      0.15  // Limite mínimo de luminância para tons de pele
#define SKIN_TONE_RANGE_MAX      0.85  // Limite máximo de luminância para tons de pele
#define MAX_GAMMA_EXPANSION      1.4   // Limite máximo de expansão de gama
#define QUALITY_CLAMP_THRESHOLD  0.35  // Limite para detecção de artefatos
// ===================================================================================
// 🎯 CONSTANTES ÁUREAS FIXAS
// ===================================================================================
#define GOLDEN_RATIO             1.618033988749895
#define GOLDEN_ANGLE             2.399963229728653
#define GOLDEN_CONJUGATE         0.618033988749895
#define GOLDEN_SEQUENCE          2.618033988749895
#define GOLDEN_SQRT              1.272019649514069
// ===================================================================================
// 🔧 FUNÇÕES UTILITÁRIAS UNIFICADAS
// ===================================================================================
#ifndef GRX_UTILS_DEFINED
#define GRX_UTILS_DEFINED
// ✅ FUNÇÃO ÚNICA: Cálculo de Luminância Segura
float safe_luma(vec3 rgb) {
    rgb = clamp(rgb, 0.0, 1.0);
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}
// ✅ FUNÇÃO ÚNICA: Cálculo de Saturação
float saturation(vec3 c) {
    float maxc = max(max(c.r, c.g), c.b);
    float minc = min(min(c.r, c.g), c.b);
    return (maxc - minc) / max(maxc, 1e-6);
}
// ✅ FUNÇÃO ÚNICA: Ruído Azul (Blue Noise)
float blueNoise(vec2 uv) {
    uv = fract(uv * vec2(0.5, 0.75));
    vec2 p = floor(uv);
    uv = fract(uv);
    float t = dot(uv.xy, uv.yx + vec2(33.3, 77.7));
    return fract(sin(t) * 1e5 + p.x * 1e3 + p.y * 1e2);
}
// ✅ FUNÇÃO ÚNICA: Conversão HSV para RGB
vec3 hsv2rgb(vec3 hsv) {
    vec3 rgb = clamp(abs(mod(hsv.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return ((rgb - 1.0) * hsv.y + 1.0) * hsv.z;
}
// ✅ FUNÇÃO ÚNICA: Conversão RGB para HSV
vec3 rgb2hsv(vec3 rgb) {
    vec3 hsv = vec3(0.0);
    float cmax = max(rgb.r, max(rgb.g, rgb.b));
    float cmin = min(rgb.r, min(rgb.g, rgb.b));
    float delta = cmax - cmin;
    hsv.z = cmax;
    if (delta > 0.0) {
        hsv.y = delta / cmax;
        if (rgb.r == cmax) hsv.x = (rgb.g - rgb.b) / delta;
        else if (rgb.g == cmax) hsv.x = 2.0 + (rgb.b - rgb.r) / delta;
        else hsv.x = 4.0 + (rgb.r - rgb.g) / delta;
        hsv.x = fract(hsv.x / 6.0);
    }
    return hsv;
}
#endif
// ===================================================================================
// 🛡️ SISTEMA DE SEGURANÇA PADRÃO
// ===================================================================================
#ifndef GRX_SAFETY_SYSTEM_DEFINED
#define GRX_SAFETY_SYSTEM_DEFINED
// ✅ FUNÇÃO ÚNICA: Validação de Textura
bool is_texture_valid(sampler2D tex, vec2 uv) {
    #if ENABLE_SAFETY_CHECKS
    vec4 sample = texture(tex, uv);
    return all(greaterThanEqual(sample.rgb, vec3(0.0))) &&
    all(lessThanEqual(sample.rgb, vec3(1.0))) &&
    (length(sample.rgb) > 1e-6) &&
    !isnan(sample.r) && !isnan(sample.g) && !isnan(sample.b);
    #else
    return true;
    #endif
}
// ✅ FUNÇÃO ÚNICA: Detecção de Artefatos
bool detect_processing_artifacts(vec3 original, vec3 processed, float threshold) {
    #if ENABLE_SAFETY_CHECKS
    float diff = length(original - processed);
    float high_freq = 0.0;
    vec2 p = HOOKED_pt;
    for (int i = 0; i < 4; i++) {
        vec2 offset = vec2(0.0);
        if (i == 0) offset = vec2( p.x, 0.0);
        else if (i == 1) offset = vec2(-p.x, 0.0);
        else if (i == 2) offset = vec2(0.0,  p.y);
        else offset = vec2(0.0, -p.y);
        vec2 sample_uv = clamp(HOOKED_pos + offset, vec2(0.0), vec2(1.0));
        high_freq += length(processed - sRGB_to_linear(texture(OUTPUT, sample_uv).rgb));
    }
    return (diff > threshold) || (high_freq > threshold * 2.0);
    #else
    return false;
    #endif
}
#endif
// ===================================================================================
// 🎨 GESTÃO DE CORES CONSISTENTE
// ===================================================================================
#ifndef GRX_COLOR_MANAGEMENT_DEFINED
#define GRX_COLOR_MANAGEMENT_DEFINED
// ✅ FUNÇÃO ÚNICA: sRGB para Linear
vec3 sRGB_to_linear(vec3 srgb) {
    bvec3 cutoff = lessThan(srgb, vec3(0.04045));
    vec3 higher = pow((srgb + 0.055) / 1.055, vec3(2.4));
    vec3 lower = srgb / 12.92;
    return mix(higher, lower, cutoff);
}
// ✅ FUNÇÃO ÚNICA: Linear para sRGB
vec3 linear_to_sRGB(vec3 linear) {
    bvec3 cutoff = lessThan(linear, vec3(0.0031308));
    vec3 higher = 1.055 * pow(linear, vec3(1.0/2.4)) - 0.055;
    vec3 lower = linear * 12.92;
    return mix(higher, lower, cutoff);
}
// ✅ FUNÇÃO ÚNICA: Correção de Subamostragem YUV 4:2:0
vec3 correct_yuv420_subsampled(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps) {
    #if YUV420_CORRECTION > 0.0
    float edge = maps.r;
    float variance = maps.g;
    // Detecta áreas com alta chance de artefatos de subamostragem
    if (edge > 0.3 && variance < 0.15) {
        // Amostragem de vizinhos para correção de croma
        vec3 neighbors[4];
        neighbors[0] = sRGB_to_linear(texture(STAGE2_OUTPUT, clamp(uv + vec2( p.x, 0.0), vec2(0.0), vec2(1.0))).rgb);
        neighbors[1] = sRGB_to_linear(texture(STAGE2_OUTPUT, clamp(uv - vec2( p.x, 0.0), vec2(0.0), vec2(1.0))).rgb);
        neighbors[2] = sRGB_to_linear(texture(STAGE2_OUTPUT, clamp(uv + vec2(0.0,  p.y), vec2(0.0), vec2(1.0))).rgb);
        neighbors[3] = sRGB_to_linear(texture(STAGE2_OUTPUT, clamp(uv - vec2(0.0,  p.y), vec2(0.0), vec2(1.0))).rgb);
        // Calcula luminância e croma local
        float center_luma = safe_luma(linear_rgb);
        vec3 chroma_center = linear_rgb - vec3(center_luma);
        // Correção adaptativa baseada na consistência local
        vec3 avg_chroma = vec3(0.0);
        float chroma_weight = 0.0;
        for (int i = 0; i < 4; i++) {
            float neighbor_luma = safe_luma(neighbors[i]);
            vec3 neighbor_chroma = neighbors[i] - vec3(neighbor_luma);
            float luma_similarity = 1.0 - abs(center_luma - neighbor_luma) * 8.0;
            luma_similarity = clamp(luma_similarity, 0.0, 1.0);
            avg_chroma += neighbor_chroma * luma_similarity;
            chroma_weight += luma_similarity;
        }
        if (chroma_weight > 1e-6) {
            avg_chroma /= chroma_weight;
            // Mistura adaptativa
            float correction_strength = YUV420_CORRECTION * (1.0 - edge) * (1.0 - variance);
            vec3 corrected = vec3(center_luma) + mix(chroma_center, avg_chroma, correction_strength);
            return corrected;
        }
    }
    #endif
    return linear_rgb;
}
#endif

// ===================================================================================
// 3.3 🧠 RESTAURAÇÃO DE SALIÊNCIA (O ILUSIONISTA DE CONTRASTE)
// ===================================================================================
// Esta é a primeira parte do "joguinho".
// Usamos a Bússola Áurea (S1) para aplicar micro-contraste (LCE)
// APENAS em áreas que são "boas" (alta estética, baixa entropia/ruído).
// Isso "puxa" o olho para os detalhes que importam.
// ===================================================================================
vec3 restore_local_contrast(vec3 linear_rgb, vec4 maps, vec4 golden) {
    vec3 result = linear_rgb;
    #if MICRO_CONTRAST_STRENGTH > 0.01

    // INTELIGÊNCIA S1: Usa dados já calculados pelo Juiz
    float aesthetic_score = golden.a; // Saliência (Beleza)
    float edge_strength = maps.r;     // Bordas (Risco de Halo)
    float noise_entropy = golden.g;   // Caos (Ruído)

    // A "Certeza Estética": Só realça o que é bonito e não é ruído puro
    float saliency_score = aesthetic_score * (1.0 - noise_entropy * 0.75);

    // Força guiada pela saliência
    float lce_strength = MICRO_CONTRAST_STRENGTH * clamp(saliency_score, 0.0, 1.0);
    lce_strength *= (1.0 - edge_strength * 0.5); // Protege halos em bordas fortes

    if (lce_strength > 0.01) {
        float Y = safe_luma(linear_rgb);
        // Máscara de Mid-tone (Onde o contraste importa)
        float mid_tone_mask = 1.0 - pow(abs(Y - 0.5) * 2.0, 2.0);

        // Aplica curva S suave (LCE Otimizado)
        // Fórmula rápida de curva S sem texture lookups pesados
        vec3 curved = linear_rgb * (linear_rgb * (1.618 * linear_rgb - 0.618) + 1.0);
        result = mix(linear_rgb, curved, lce_strength * mid_tone_mask);
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 3.4 🎨 NORMALIZAÇÃO ADAPTATIVA DE GAMA (NOVO)
// ===================================================================================
vec3 normalize_adaptive_gamma(vec3 linear_rgb, vec4 maps, vec4 golden) {
    vec3 result = linear_rgb;
    #if GAMMA_NORMALIZATION > 0.01
    float variance = maps.g;
    float pattern_entropy = golden.g;
    float aesthetic_score = golden.a;
    // Detecta áreas com problemas de gama (mid-tones esmagados)
    bool has_gamma_issues = (variance < 0.03) && (pattern_entropy < 0.4);
    if (has_gamma_issues) {
        float Y = safe_luma(linear_rgb);
        // Foco nos mid-tones onde a compressão é mais perceptível
        float mid_tone_focus = smoothstep(0.2, 0.3, Y) * (1.0 - smoothstep(0.7, 0.8, Y));
        if (mid_tone_focus > 0.1) {
            // Cálculo adaptativo da expansão de gama
            float gamma_power = 1.0 / (GAMMA_BASE_ADJUST * (1.0 - GAMMA_NORMALIZATION * 0.3));
            float adaptive_factor = GAMMA_NORMALIZATION * (0.8 + 0.2 * aesthetic_score);
            adaptive_factor *= (1.0 - variance * 2.0); // Menos força em áreas com textura

            // Aplica normalização adaptativa
            vec3 normalized = pow(linear_rgb, vec3(gamma_power));
            result = mix(linear_rgb, normalized, adaptive_factor * mid_tone_focus);

            // Limite de segurança para evitar clipping
            result = clamp(result, 0.0, MAX_GAMMA_EXPANSION);
        }
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 3.5 🧠 O ILUSIONISTA DE COR (SALIÊNCIA VS. SUPRESSÃO)
// ===================================================================================
// Esta é a segunda parte do "joguinho", e a mais crítica.
// 1. Áreas "Boas" (golden.a): Aumenta o vibrance (Saliência).
// 2. Áreas "Ruins" (golden.g): Diminui ativamente a saturação (Supressão).
// Isso "engana" o cérebro, forçando-o a ignorar o "lixo" (que fica
// cinza) e focar na "beleza" (que fica vibrante).
// ===================================================================================
vec3 intelligent_vibrance_enhancement(vec3 linear_rgb, vec4 maps, vec4 golden, vec4 luma) {
    vec3 result = linear_rgb;
    #if VIBRANCE_ENHANCEMENT > 0.01

    vec3 hsv = rgb2hsv(linear_to_sRGB(linear_rgb));
    float sat = hsv.y;

    // INTELIGÊNCIA S1 v2.1
    float chroma_risk = luma.b;    // Ruído colorido em sombras
    float aesthetic = golden.a;    // Saliência

    // 1. Supressão de Ruído Cromático (Shadow Purifier)
    // Se o S1 diz que é risco cromático e a área não é esteticamente relevante -> MATAR COR
    if (chroma_risk > 0.2 && aesthetic < 0.4) {
        sat *= (1.0 - chroma_risk * 0.8);
    }

    // 2. Boost de Saliência (Inteligente)
    // Se é bonito -> Aumenta Vibrance
    if (aesthetic > 0.6) {
        float boost = (1.0 - sat) * sat * VIBRANCE_ENHANCEMENT * 0.5;
        sat += boost;
    }

    hsv.y = clamp(sat, 0.0, 0.95);
    result = sRGB_to_linear(hsv2rgb(hsv));
    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 3.5.1 MÓDULO LCE MULTI-ESCALA ULTIMATE (S1 DRIVEN)
// ===================================================================================
// Escultor de Luz que utiliza a inteligência total do S1 para separar
// "Textura Artística" de "Ruído Digital" e aplicar profundidade assimétrica.

vec3 apply_multi_scale_lce(vec3 linear_input, vec4 maps, vec4 golden, vec4 temporal) {
    // 1. LEITURA PROFUNDA DO S1 (O Cérebro)

    // A. Estética e Harmonia (Golden)
    float aesthetic_score = golden.a;  // Beleza geral
    float harmonic_balance = golden.b; // 1.0 = Grão/Textura boa, 0.0 = Ruído caótico

    // B. Estrutura e Defeitos (Maps)
    float edge_strength = maps.r;      // Bordas fortes (risco de Halo)
    float variance = maps.g;           // Atividade local
    float stream_confidence = maps.a;  // O Alarme Geral

    // C. Estabilidade (Temporal)
    // Objetos parados permitem mais escultura 3D. Objetos rápidos escondem textura.
    float stability = temporal.g;

    // --- FILTRO DE PASSAGEM (Gatekeeper) ---
    // Se o stream está quebrado, ou a área é lisa demais (céu), ou é borda pura: aborta.
    if (stream_confidence < 0.1 || variance < 0.0005 || edge_strength > 0.8) {
        return linear_input;
    }

    // 2. EXTRAÇÃO DE FREQUÊNCIA MÉDIA (A "Massa" da Textura)
    // Usamos o blur otimizado (Cross-Sampling) para isolar o volume.
    vec2 pixel = HOOKED_pt;
    vec3 blurred = vec3(0.0);
    float total_w = 0.0;

    // Kernel Cruzado 5-tap (Eficiência máxima)
    vec2 offsets[5] = vec2[](vec2(0,0), vec2(1.5, 1.5), vec2(-1.5, -1.5), vec2(1.5, -1.5), vec2(-1.5, 1.5));

    for(int i=0; i<5; i++) {
        vec3 samp = texture(GRX_COLOR_LINEAR, HOOKED_pos + offsets[i] * pixel).rgb;
        // Peso por luma inverso (Evita contaminar sombras com luz de vizinhos brilhantes)
        float w = 1.0 / (1.0 + luminance(samp) * 2.0 + 0.1);
        blurred += samp * w;
        total_w += w;
    }
    blurred /= total_w;

    // O "Delta" (A Textura isolada)
    vec3 texture_delta = linear_input - blurred;

    // 3. CÁLCULO DE FORÇA GUIADO PELO S1

    // Base: Começamos suave
    float lce_strength = 0.4;

    // Fator 1: Harmonia (O Grande Segredo)
    // Se for grão de filme (harmônico), aumentamos. Se for bloco de compressão, zeramos.
    lce_strength *= smoothstep(0.2, 0.8, harmonic_balance);

    // Fator 2: Estabilidade Temporal
    // Se o objeto é sólido e estável, podemos esculpir fundo (efeito 3D).
    // Se move muito, reduzimos para evitar "sizzling" (fervilhado).
    lce_strength *= (0.5 + 0.5 * stability);

    // Fator 3: Proteção de Halo (Anti-Ringing)
    // Perto de bordas fortes (edge_strength), reduzimos a força para não criar brilho falso.
    lce_strength *= (1.0 - edge_strength * 0.8);

    // Fator 4: Estética
    // Só investimos GPU onde a imagem vale a pena.
    lce_strength *= aesthetic_score;

    // 4. ESCULTURA ASSIMÉTRICA (Dark vs Light)
    // Textura real é feita de sombras (poros, tramas, ranhuras).
    // Halos digitais são feitos de luz.
    // -> Enfatizamos o escuro, seguramos o claro.

    float luma_delta = luminance(texture_delta);

    // Se o delta é positivo (brilho) -> reduz força (0.6x)
    // Se o delta é negativo (sombra/profundidade) -> aumenta força (1.3x)
    float asymmetry = (luma_delta > 0.0) ? 0.6 : 1.3;

    // Proteção de Sombras Profundas (Shadow Protect)
    // Não queremos realçar ruído no preto absoluto.
    float luma_base = luminance(linear_input);
    float shadow_protect = smoothstep(0.02, 0.15, luma_base);

    // 5. APLICAÇÃO FINAL
    vec3 final_delta = texture_delta * lce_strength * asymmetry * shadow_protect;

    return linear_input + final_delta;
}

// ===================================================================================
// 3.6 🧴 MÁSCARA DE TONS DE PELE (OTIMIZADA)
// ===================================================================================
float skin_tone_mask(vec3 srgb) {
    #if SKIN_TONE_PROTECTION > 0.01
    float Y = safe_luma(srgb);
    // Intervalo de luminância para tons de pele
    if (Y > SKIN_TONE_RANGE_MIN && Y < SKIN_TONE_RANGE_MAX) {
        // Relações de cor para detecção de pele
        float r_g_ratio = srgb.r / max(srgb.g, 0.001);
        float r_b_ratio = srgb.r / max(srgb.b, 0.001);
        bool skin_range = (r_g_ratio > 1.0 && r_g_ratio < 2.0) &&
        (r_b_ratio > 1.3 && r_b_ratio < 2.8);
        if (skin_range) {
            float sat = saturation(srgb);
            // Mapeamento suave para tons de pele
            float skinness = smoothstep(0.1, 0.4, sat) *
            smoothstep(0.2, 0.4, Y) *
            (1.0 - smoothstep(0.7, 0.8, Y));
            return skinness * SKIN_TONE_PROTECTION;
        }
    }
    #endif
    return 0.0;
}
// ===================================================================================
// 3.7 🔍 ANTI-ALIASING DIRECIONAL COM PRESERVAÇÃO DE DETALHES (OTIMIZADO)
// ===================================================================================
vec3 directional_aa_with_detail_preservation(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps, vec4 temporal) {
    vec3 result = linear_rgb;
    #if EDGE_PROTECTION_STRENGTH > 0.01
    float edge_strength = maps.r;
    float motion = temporal.r;
    // Só aplica AA em bordas problemáticas com proteção de detalhes
    if (edge_strength > 0.08 && edge_strength < 0.8) {
        // Amostras para detecção de direção
        vec3 north = sRGB_to_linear(texture(STAGE2_OUTPUT, clamp(uv + vec2(0.0,  p.y), vec2(0.0), vec2(1.0))).rgb);
        vec3 south = sRGB_to_linear(texture(STAGE2_OUTPUT, clamp(uv - vec2(0.0,  p.y), vec2(0.0), vec2(1.0))).rgb);
        vec3 east = sRGB_to_linear(texture(STAGE2_OUTPUT, clamp(uv + vec2( p.x, 0.0), vec2(0.0), vec2(1.0))).rgb);
        vec3 west = sRGB_to_linear(texture(STAGE2_OUTPUT, clamp(uv - vec2( p.x, 0.0), vec2(0.0), vec2(1.0))).rgb);
        float luma_n = safe_luma(north);
        float luma_s = safe_luma(south);
        float luma_e = safe_luma(east);
        float luma_w = safe_luma(west);
        float luma_c = safe_luma(linear_rgb);
        // Detecta direção predominante da borda
        float edge_h = abs(luma_e - luma_w);
        float edge_v = abs(luma_n - luma_s);
        float max_edge = max(edge_h, edge_v);
        if (max_edge > 0.08) {
            // Suavização direcional com preservação de detalhes
            vec3 blend_h = (east + west) * 0.5;
            vec3 blend_v = (north + south) * 0.5;
            float mix_ratio = edge_v / (edge_h + edge_v + 1e-6);
            vec3 blended = mix(blend_h, blend_v, mix_ratio);

            // Força adaptativa com proteção de detalhes
            float aa_strength = 0.6 * EDGE_PROTECTION_STRENGTH;
            aa_strength *= smoothstep(0.08, 0.5, max_edge);
            aa_strength *= (1.0 - motion * 0.7 * (1.0 - MOTION_ADAPTIVE_STRENGTH));

            // Preservação de crominância com limite anti-perda de detalhes
            float luma_old = luma_c;
            float luma_new = safe_luma(blended);
            vec3 chroma = linear_rgb - vec3(luma_old);

            // Controle de preservação de detalhes
            float detail_preservation = mix(0.9, 0.98, aa_strength);
            result = vec3(mix(luma_old, luma_new, aa_strength)) + chroma * detail_preservation;
        }
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 3.7.1 🌿 TEXTURA ORGÂNICA (WEIBULL GRAIN - NOVO)
// ===================================================================================
// Adiciona textura de "Filme" em áreas que ficaram plásticas (lisas demais).
vec3 organic_texture_synthesis(vec2 uv, vec3 linear_rgb, vec4 maps, vec4 golden, vec4 luma) {
    vec3 result = linear_rgb;
    // Defina a opacidade do grão aqui ou no config principal (0.6 é um bom padrão)
    float grain_opacity = 0.6;

    float aesthetic = golden.a;
    float entropy = golden.g;   // Detalhe existente
    // No novo S1, luma.g é "Shadow Dirt". Se for baixo, é liso.
    // Usamos maps.g (Variance) invertido como proxy de lisura também.
    float smoothness = 1.0 - maps.g;

    // Só aplicamos grão onde está liso E tem importância estética
    float grain_need = smoothness * (1.0 - entropy) * aesthetic;

    if (grain_need > 0.2) {
        // Gerador Weibull Simplificado (Grão Natural)
        vec2 seed = uv * vec2(12.9898, 78.233) + 1.0;
        float n = fract(sin(dot(seed, seed)) * 43758.5453);
        float weibull = pow(-log(1.0 - n), 1.0/1.5);
        float grain = (weibull - 0.9) * 0.03; // Amplitude fina

        // Modulação por Luminância (Grão vive nos midtones, não no preto/branco)
        float Y = safe_luma(linear_rgb);
        float mask = smoothstep(0.05, 0.2, Y) * (1.0 - smoothstep(0.9, 1.0, Y));

        result += grain * grain_opacity * grain_need * mask;
    }
    return result;
}

// ===================================================================================
// 3.7.2 🏥 GRADING DE PELE (NOVO)
// ===================================================================================
// Empurra tons de pele "doentes" para "saudáveis" usando detecção contextual
vec3 skin_tone_grading(vec3 linear_rgb, vec4 golden) {
    vec3 result = linear_rgb;
    float grading_strength = 0.8; // Força padrão

    vec3 hsv = rgb2hsv(linear_to_sRGB(linear_rgb));

    // Intervalo de pele amplo
    bool is_skin_range = (hsv.x > 0.0 && hsv.x < 0.12) && (hsv.y > 0.15 && hsv.y < 0.7);

    if (is_skin_range) {
        float target_hue = 0.04; // Laranja/Pêssego saudável
        float diff = target_hue - hsv.x;
        // Aplica correção suave
        hsv.x += diff * grading_strength * 0.5;

        // Boost sutil se estiver muito pálido
        if (hsv.y < 0.3) hsv.y *= 1.1;

        result = sRGB_to_linear(hsv2rgb(hsv));
        // Mistura baseada na confiança estética do S1 (para não pintar paredes de laranja)
        result = mix(linear_rgb, result, golden.a);
    }
    return result;
}

// ===================================================================================
// 3.8 🎯 SISTEMA DE CONTROLE DE QUALIDADE
// ===================================================================================
float calculate_restoration_confidence(vec3 original_linear, vec3 restored_srgb, vec4 maps, vec4 golden) {
    float confidence = 1.0;
    vec3 restored_linear = sRGB_to_linear(restored_srgb);
    // Diferença geral (moderada é boa)
    float overall_diff = length(original_linear - restored_linear);
    confidence -= overall_diff * 0.4;
    // Preservação de detalhes
    float detail_preservation = 1.0 - clamp(maps.g * overall_diff * 1.5, 0.0, 1.0);
    confidence += detail_preservation * 0.3;
    // Melhoria estética
    float aesthetic_improvement = golden.a;
    confidence += aesthetic_improvement * 0.2;
    // Penalidade por artefatos
    if (detect_processing_artifacts(original_linear, restored_linear, 0.25)) {
        confidence *= 0.8;
    }
    return clamp(confidence, 0.0, 1.0);
}
// Sistema de decisão para aplicação de restauração
bool should_apply_restoration(vec4 maps, vec4 temporal, vec4 golden, float stage) {
    float confidence = maps.a;
    float motion = temporal.r;
    float aesthetic_score = golden.a;
    // Fatores positivos
    bool high_confidence = confidence > 0.6;
    bool low_motion = motion < (0.4 - stage * 0.2);
    bool good_aesthetics = aesthetic_score > 0.5;
    // Combinação com pesos adaptativos
    float decision_score = (float(high_confidence) * 1.2 +
    float(low_motion) * 1.0 +
    float(good_aesthetics) * 0.8) / 3.0;
    // Ajuste baseado no estágio do processamento
    float stage_factor = 0.7 - stage * 0.1;
    return decision_score > stage_factor;
}

// ===================================================================================
// 3.9 🧠 HOOK PRINCIPAL - RESTAURAÇÃO DE INTEGRIDADE
// ===================================================================================
//!HOOK MAIN
//!DESC S3 - Módulo de Restauração de Integridade (Linear Tunnel Ready)
//!BIND HOOKED
//!BIND STAGE2_OUTPUT
//!BIND GRX_MAPS
//!BIND GRX_TEMPORAL
//!BIND GRX_GOLDEN
//!SAVE STAGE3_ENHANCED
//!COMPONENTS 4
vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 p = HOOKED_pt;

    // 3.9.1 CARREGA IMAGEM (PREPARADO PARA TÚNEL LINEAR)

    // NOTA: Se você JÁ alterou o S2 para sair em Linear, remova o sRGB_to_linear abaixo.
    // Se o S2 ainda sai em sRGB, mantenha assim por enquanto.
    vec3 cleaned_input = texture(STAGE2_OUTPUT, clamp(uv, vec2(0.0), vec2(1.0))).rgb;

    // ATENÇÃO: Comente a linha abaixo APENAS se o S2 já estiver entregando Linear puro.
    vec3 cleaned_linear = sRGB_to_linear(cleaned_input);
    // vec3 cleaned_linear = cleaned_input; // <-- Use esta se o S2 já for Linear.

    // 3.9.2 CARREGA MAPAS
    vec4 maps = GRX_MAPS_tex(uv);
    vec4 temporal = GRX_TEMPORAL_tex(uv);
    vec4 golden = GRX_GOLDEN_tex(uv);

    // 3.9.2.A 🚨 O ALARME S1 (S0 Confidence)
    float s0_confidence = maps.a;

    // 3.9.3 CORREÇÃO DE SUBAMOSTRAGEM YUV
    vec3 corrected_linear = correct_yuv420_subsampled(uv, p, cleaned_linear, maps);

    // 3.9.4 RESTAURAÇÃO EM CASCATA (LINEAR)
    vec3 restored_linear = corrected_linear;

    // BLOCO DE SEGURANÇA: Só processa se o S1 confiar no stream (> 1%)
    if (s0_confidence > 0.01) {

        // Estágio 0.5: Grading de Pele (NOVO - Antes de tudo para garantir cor base)
        restored_linear = skin_tone_grading(restored_linear, golden);

        // Estágio 1: Restauração de Micro-Contraste (Atualizado)
        if (should_apply_restoration(maps, temporal, golden, 0.0)) {
            restored_linear = restore_local_contrast(restored_linear, maps, golden);
        }

        // Estágio 2: Normalização Adaptativa de Gama
        if (should_apply_restoration(maps, temporal, golden, 0.1)) {
            restored_linear = normalize_adaptive_gamma(restored_linear, maps, golden);
        }

        // Estágio 2.5: Síntese de Textura Orgânica (NOVO - Adiciona "matéria" antes do AA)
        restored_linear = organic_texture_synthesis(uv, restored_linear, maps, golden, luma);

        // Estágio 3: Anti-Aliasing Direcional
        if (should_apply_restoration(maps, temporal, golden, 0.2)) {
            restored_linear = directional_aa_with_detail_preservation(uv, p, restored_linear, maps, temporal);
        }

        // Estágio 4: Vibrance Inteligente (Atualizado - agora pede 'luma')
        if (should_apply_restoration(maps, temporal, golden, 0.3)) {
            // NOTA: Adicionei 'luma' na chamada da função
            restored_linear = intelligent_vibrance_enhancement(restored_linear, maps, golden, luma);
        }

        // Estágio 5: Módulo LCE Multi-Escala Ultimate
        // Mantém como estava, pois este é o seu "peso pesado"
        restored_linear = apply_multi_scale_lce(restored_linear, maps, golden, temporal);
    }

    // Se s0_confidence < 0.01, o 'restored_linear' passa direto (Bypass), evitando amplificar defeitos.

    // 3.9.5 SAÍDA (MANTÉM LINEAR PARA O S4)
    vec3 final_output = max(restored_linear, vec3(0.0));

    // 3.9.6 CÁLCULO DE CONFIANÇA DA RESTAURAÇÃO
    float restoration_confidence = calculate_cleanliness_score(cleaned_linear, final_output, maps, golden);
    restoration_confidence = clamp(restoration_confidence, 0.0, 1.0);

    // Salva em LINEAR (RGBA32F preserva os dados para o S4 fazer o Upscale)
    return vec4(final_output, restoration_confidence);
}

// ===================================================================================
// 3.10 🧠 (MÓDULO ATUALIZADO) EXTRATOR DE DETALHES ÁUREOS "CURADOR"
// ===================================================================================
// OBJETIVO: Sincronizado com o S2 "Architect+".
// 1. Confia mais na estrutura do S2 (relaxa a guarda).
// 2. Respeita o "Polimento Nuclear" (não reinjeta ruído em sombras).
// 3. Purifica o detalhe (remove cor do ruído).
// ===================================================================================
//!HOOK GRX_DETAIL_HOOK
//!DESC S3.5 - Extrator de Detalhes Curador (S2-Aware)
//!BIND GRX_COLOR_LINEAR
//!BIND STAGE2_OUTPUT
//!BIND GRX_GOLDEN
//!BIND GRX_MAPS
//!BIND GRX_LUMA
//!SAVE GRX_DETAIL_MAP
//!COMPONENTS 3
vec4 hook_detail_extractor() {
    vec2 uv = HOOKED_pos;

    // 1. ANÁLISE DE CONTEXTO
    vec4 maps = GRX_MAPS_tex(uv);
    float stream_confidence = maps.a;

    // MUDANÇA 1: Relaxamento da Confiança (Trust Update)
    // O novo S2 é mais estável. Podemos tentar extrair detalhe mesmo em streams
    // um pouco mais sujos (0.2), pois o S2 já removeu os blocos grandes.
    if (stream_confidence < 0.2) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }

    // 2. LÊ AS IMAGENS
    vec3 original_linear = GRX_COLOR_LINEAR_tex(uv).rgb;
    vec3 clean_srgb = STAGE2_OUTPUT_tex(uv).rgb;
    vec3 clean_linear = sRGB_to_linear(clean_srgb);

    // 3. CALCULA O DELTA (A Matéria Bruta)
    vec3 detail_delta = original_linear - clean_linear;

    // Trava de sanidade
    if (any(isnan(detail_delta))) detail_delta = vec3(0.0);
    // Clamp mais solto para permitir texturas de alto contraste
    detail_delta = clamp(detail_delta, -0.6, 0.6);

    // 4. ANÁLISE DE SALIÊNCIA (O S1)
    vec4 golden = GRX_GOLDEN_tex(uv);
    vec4 luma = GRX_LUMA_tex(uv);

    float aesthetic_score = golden.a;  // Beleza
    float pattern_entropy = golden.g;  // Complexidade
    float brightness = luma.r;         // Brilho

    // 5. PURIFICAÇÃO CROMÁTICA (NOVO)
    // Ruído costuma ser colorido. Textura costuma ser luz e sombra.
    // Extraímos a luminância do delta.
    float delta_luma = dot(detail_delta, vec3(0.2126, 0.7152, 0.0722));

    // Se a área for MUITO bonita (rosto), permitimos cor (sardas, maquiagem).
    // Se não, forçamos o detalhe a ser monocromático (evita ruído RGB).
    float chroma_allowance = smoothstep(0.6, 0.9, aesthetic_score);
    vec3 purified_detail = mix(vec3(delta_luma), detail_delta, chroma_allowance);

    // 6. O "SELO DA SOMBRA" (Sincronia com S2 Nuclear)
    // O S2 limpou agressivamente sombras < 0.12. O S3 deve respeitar isso.
    // Criamos uma curva que mata a reinjeção nas sombras profundas.
    float shadow_seal = smoothstep(0.05, 0.25, brightness);

    // 7. MÁSCARA DE CURADORIA (A Peneira Refinada)
    // Aceitamos detalhe se:
    // (É complexo E bonito) OU (É uma borda fina que o S2 suavizou demais)
    float edge_restore = maps.r * 0.3; // Recupera levemente bordas perdidas
    float texture_score = pattern_entropy * aesthetic_score;

    float acceptance_mask = texture_score + edge_restore;

    // Modulações Finais
    acceptance_mask *= shadow_seal;              // Respeita o preto
    acceptance_mask *= smoothstep(0.15, 0.5, stream_confidence); // Escala com a confiança

    // Aplica a máscara
    vec3 final_detail = purified_detail * acceptance_mask;

    // Boost Sutil para Texturas Finas ("Pop")
    // Se for textura de alta qualidade, damos um leve ganho para compensar a perda no Delta
    if (aesthetic_score > 0.7) {
        final_detail *= 1.2;
    }

    return vec4(final_detail, 1.0);
}
