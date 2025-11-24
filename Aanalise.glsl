// ===================================================================================
// S1_analysis_temporal.glsl — Meta-Cérebro Neuro-Estético Blindado (v3.0)
// ===================================================================================
// Licença: MIT / GPLv3 — Código aberto, auditável, modular
// Autor: Pipeline GRX - Estágio 1 (O Juiz Neuro-Estético)
// ===================================================================================
// OBJETIVO: Gerar mapas de análise com segurança robusta contra falhas numéricas.
// ===================================================================================
// SAÍDAS (BLINDADAS E SANITIZADAS):
//   GRX_MAPS (RGBA):
//      .r = SKELETON (Borda estrutural baseada em Sobel + Continuidade)
//      .g = VARIANCE (Atividade bruta local)
//      .b = EXPOSURE (Nível de luz)
//      .a = META_CONFIDENCE (Confiança Emocional do stream)
//
//   GRX_TEMPORAL (RGBA):
//      .r = MOTION (Intensidade)
//      .g = STABILITY (Inverso do movimento + Coerência)
//      .b = FLOW_CONFIDENCE (Saúde do vetor de movimento)
//      .a = FLICKER_SCORE (Detecção de oscilação temporal artificial)
//
//   GRX_GOLDEN (RGBA):
//      .r = GRID_SCORE (Probabilidade de Macrobloco - Baixa Freq)
//      .g = TEXTURE_ENTROPY (Grão/Detalhe - Alta Freq)
//      .b = HARMONIC_BALANCE (Equilíbrio visual)
//      .a = AESTHETIC_SCORE (Saliência: Pele + Contraste + Luz)
//
//   GRX_LUMA (RGBA):
//      .r = BRIGHTNESS (Luma Linear)
//      .g = SHADOW_DIRT (Densidade de sujeira na sombra)
//      .b = CHROMA_RISK (Risco de ruído colorido)
//      .a = MID_TONE_DENSITY (Densidade de ruído em tons médios)
//
//   GRX_COLOR_LINEAR (RGB): Cores normalizadas em espaço linear
// ===================================================================================

// -------------------------
// 1.1 🔧 CONFIGURAÇÕES PRINCIPAIS
// -------------------------
// Ativação de Funcionalidades (1=ON, 0=OFF)
#define ENABLE_TEMPORAL_ANALYSIS 1 // Análise de movimento e estabilidade
#define ENABLE_GOLDEN_ANALYSIS   1 // Análise de Bússola Áurea (estética/entropia)
#define ENABLE_LUMA_ANALYSIS     1 // Análise de Áreas Claras/Zonal
#define ENABLE_SAFETY_CHECKS     1 // Ativa verificações de segurança robustas

// Parâmetros de Análise
#define LOW_LIGHT_THRESHOLD      0.15 // Limiar para detecção de baixa luz
#define MOTION_SENSITIVITY       1.2  // Sensibilidade da detecção de movimento
#define EDGE_STRENGTH_FACTOR     1.5  // Multiplicador para detecção de borda
#define VARIANCE_THRESHOLD       0.001 // Limiar mínimo para cálculo de variância
#define GRID_DETECTION_MIN       0.1  // Limiar mínimo para detecção de grade
#define AESTHETIC_SENSITIVITY    1.1  // Sensibilidade da pontuação estética

// Parâmetros de Segurança
#define CONFIDENCE_FALLBACK      0.5  // Confiança padrão em caso de falha

// ===================================================================================
// 1.2 🎯 CONSTANTES ÁUREAS FIXAS
// ===================================================================================
#define GOLDEN_RATIO             1.618033988749895
#define GOLDEN_CONJUGATE         0.618033988749895
#define GOLDEN_ANGLE             2.399963229728653
#define GOLDEN_SEQUENCE          2.618033988749895
#define GOLDEN_SQRT              1.272019649514069

// ===================================================================================
// 1.3 🔧 FUNÇÕES UTILITÁRIAS UNIFICADAS (PADRÃO ROBUSTO S4 COMPATÍVEL)
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
// ✅ FUNÇÃO ÚNICA: ELU Shaper
float elu_shaper(float x, float a) {
    return x > 0.0 ? x : a * (exp(x) - 1.0);
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
// 1.4 🛡️ SISTEMA DE SEGURANÇA ANALÍTICO (REFORÇADO)
// ===================================================================================
#ifndef GRX_SAFETY_SYSTEM_DEFINED
#define GRX_SAFETY_SYSTEM_DEFINED

// 1. Validação Estrita (Anti-NaN e Anti-Inf)
bool is_texture_valid(sampler2D tex, vec2 uv) {
    #if ENABLE_SAFETY_CHECKS
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return false;
    vec4 sample = texture(tex, uv);
    return all(greaterThanEqual(sample.rgb, vec3(0.0))) &&
    all(lessThanEqual(sample.rgb, vec3(1.0))) &&
    (length(sample.rgb) > 1e-6) &&
    !isnan(sample.r) && !isnan(sample.g) && !isnan(sample.b) &&
    !isinf(sample.r) && !isinf(sample.g) && !isinf(sample.b);
    #else
    return true;
    #endif
}

// 2. Fallback Seguro para Amostragem
vec3 safe_texture_sample(sampler2D tex, vec2 uv, vec3 fallback_color) {
    if (is_texture_valid(tex, uv)) {
        return texture(tex, uv).rgb;
    }
    return fallback_color;
}

// 3. Sanitizador de Métricas (NOVO PARA O S1)
// Garante que mapas analíticos (Variance, Entropy) nunca quebrem a pipeline
// com valores impossíveis, protegendo S2, S3 e S4.
vec4 sanitize_metrics(vec4 metrics, float fallback_value) {
    if (any(isnan(metrics)) || any(isinf(metrics))) return vec4(fallback_value);
    return clamp(metrics, 0.0, 1.0);
}
#endif

// ===================================================================================
// 1.5 🎨 GESTÃO DE CORES CONSISTENTE
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
#endif

// ===================================================================================
// 1.6 🔬 DETETIVE NEURO-ESTÉTICO (Análise Espacial & Frequência)
// ===================================================================================
float calculate_skeleton_strength(vec2 uv, vec2 p, vec3 linear_rgb) {
    float gx = 0.0;
    float gy = 0.0;

    float c = safe_luma(linear_rgb);
    float n = safe_luma(safe_texture_sample(HOOKED, uv + vec2(0,-1)*p, linear_rgb));
    float s = safe_luma(safe_texture_sample(HOOKED, uv + vec2(0, 1)*p, linear_rgb));
    float w = safe_luma(safe_texture_sample(HOOKED, uv + vec2(-1,0)*p, linear_rgb));
    float e = safe_luma(safe_texture_sample(HOOKED, uv + vec2( 1,0)*p, linear_rgb));

    gx = e - w;
    gy = s - n;
    float mag = sqrt(gx*gx + gy*gy);

    // Heurística de Continuidade:
    float neighbors = (n+s+w+e) * 0.25;
    float isolation = abs(c - neighbors);

    // Se magnitude alta e isolamento baixo = Borda Estrutural.
    return smoothstep(0.05, 0.2, mag) * (1.0 - smoothstep(0.1, 0.3, isolation));
}

void calculate_frequency_metrics(vec2 uv, vec2 p, float luma, out float low_freq, out float high_freq) {
    vec3 luma_vec = vec3(luma);

    // Amostras Largas (Blocos)
    float n2 = safe_luma(safe_texture_sample(HOOKED, uv + vec2(0,-2)*p, luma_vec));
    float s2 = safe_luma(safe_texture_sample(HOOKED, uv + vec2(0, 2)*p, luma_vec));
    float w2 = safe_luma(safe_texture_sample(HOOKED, uv + vec2(-2,0)*p, luma_vec));
    float e2 = safe_luma(safe_texture_sample(HOOKED, uv + vec2( 2,0)*p, luma_vec));

    // Amostras Curtas (Grão)
    float n1 = safe_luma(safe_texture_sample(HOOKED, uv + vec2(0,-1)*p, luma_vec));
    float s1 = safe_luma(safe_texture_sample(HOOKED, uv + vec2(0, 1)*p, luma_vec));
    float w1 = safe_luma(safe_texture_sample(HOOKED, uv + vec2(-1,0)*p, luma_vec));
    float e1 = safe_luma(safe_texture_sample(HOOKED, uv + vec2( 1,0)*p, luma_vec));

    // Energia de Baixa Frequência (Blocos)
    low_freq = (abs(n2-luma) + abs(s2-luma) + abs(w2-luma) + abs(e2-luma)) * 0.25;

    // Energia de Alta Frequência (Grão - Laplaciano Local)
    float local_avg = (n1+s1+w1+e1) * 0.25;
    high_freq = abs(luma - local_avg) * 2.0;
}

// Wrapper principal
void calculate_spatial_metrics(vec2 uv, vec2 p, vec3 linear_rgb, float Y_linear, out float edge, out float variance, out float low_freq) {
    edge = calculate_skeleton_strength(uv, p, linear_rgb);
    float high_freq;
    calculate_frequency_metrics(uv, p, Y_linear, low_freq, high_freq);

    variance = clamp(high_freq, VARIANCE_THRESHOLD, 1.0);
    // Proteção extra interna
    if (isnan(variance) || isinf(variance)) variance = 0.0;
}

// Calcula exposição (brilho)
float calculate_exposure(float Y_linear) {
    return smoothstep(0.0, LOW_LIGHT_THRESHOLD * 2.0, Y_linear);
}

// ===================================================================================
// 1.7 ⏱️ DETETIVE TEMPORAL (Detector de Flickering)
// ===================================================================================
void calculate_temporal_metrics(vec2 uv, vec2 p, float Y_linear, out float motion, out float stability, out float flow_confidence, out float flicker_score) {
    motion = 0.0;
    stability = 1.0;
    flow_confidence = 0.0;
    flicker_score = 0.0;

    #if ENABLE_TEMPORAL_ANALYSIS
    #ifdef PREV_tex
    if (is_texture_valid(PREV, uv)) {
        vec3 prev_srgb = safe_texture_sample(PREV, uv, linear_to_sRGB(vec3(Y_linear)));
        float prev_Y = safe_luma(sRGB_to_linear(prev_srgb));

        // 1. Movimento (Diferença de Luma)
        float motion_raw = abs(Y_linear - prev_Y);
        motion = smoothstep(0.01, 0.2, motion_raw * MOTION_SENSITIVITY);
        stability = 1.0 - motion;

        // 2. Detecção de Flickering (Saúde Temporal)
        float flicker_raw = motion_raw * stability;
        flicker_score = smoothstep(0.03, 0.15, flicker_raw);

        // 3. Confiança do Fluxo
        float diff_sum = 0.0;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                vec2 offset = vec2(dx, dy) * p;
                float current_local = safe_luma(safe_texture_sample(HOOKED, uv + offset, vec3(Y_linear)));
                float prev_local = safe_luma(sRGB_to_linear(safe_texture_sample(PREV, uv + offset, prev_srgb)));
                diff_sum += abs(current_local - prev_local);
            }
        }
        float base_conf = 1.0 - smoothstep(0.0, 0.5, diff_sum / 9.0);
        flow_confidence = base_conf * (1.0 - flicker_score);
    }
    #endif
    #endif
}

// ===================================================================================
// 1.8 ⚜️ DETETIVE ÁUREO (Saliência e Frequência)
// ===================================================================================
float detect_skin_tone(vec3 linear) {
    float r = linear.r;
    float g = linear.g;
    float b = linear.b;
    bool condition1 = r > g && g > b;
    bool condition2 = (r - g) > 0.02 && (r - g) < 0.15;
    float skin_prob = 0.0;
    if (condition1 && condition2) {
        skin_prob = 1.0 - smoothstep(0.0, 0.1, abs((r-g) - (g-b)));
    }
    return skin_prob;
}

void calculate_golden_metrics(vec2 uv, vec2 p, vec3 linear_rgb, float skeleton, float low_freq, float high_freq, out float grid_score, out float texture_entropy, out float harmonic_balance, out float aesthetic_score) {
    // 1. Grid Score (Blocos)
    grid_score = smoothstep(0.05, 0.2, low_freq) * (1.0 - smoothstep(0.0, 0.1, high_freq));

    // 2. Texture Entropy (Grão)
    texture_entropy = smoothstep(0.01, 0.1, high_freq);

    // 3. Aesthetic Score (Saliência/Beleza)
    float luma = safe_luma(linear_rgb);
    float skin_score = detect_skin_tone(linear_rgb);
    float midtone_pref = 1.0 - abs(luma - 0.5) * 1.5;

    float aesthetic_raw = skin_score * 0.6 + skeleton * 0.3 + midtone_pref * 0.1;
    aesthetic_score = clamp(aesthetic_raw - grid_score, 0.0, 1.0);

    // 4. Harmonic Balance
    harmonic_balance = texture_entropy * aesthetic_score;
}

// ===================================================================================
// 1.9 💡 CARTÓGRAFO ZONAL (Análise de Densidade e Risco)
// ===================================================================================
void calculate_zonal_metrics(vec3 linear, float Y, float var, float skeleton, out float shadow_density, out float chroma_risk, out float mid_tone_density) {
    // 1. Zona de Sombra (Zona Abissal)
    float is_dark = 1.0 - smoothstep(0.02, 0.25, Y);
    shadow_density = is_dark * var * 12.0;

    // 2. Risco Cromático (Saturação alta no escuro)
    float sat = saturation(linear);
    chroma_risk = is_dark * sat * (1.0 - skeleton);

    // 3. Zona de Mid-Tones (Neblina)
    float is_mid = (1.0 - abs(Y - 0.45) * 2.2);
    mid_tone_density = clamp(is_mid * var * 5.0, 0.0, 1.0);
}

// ===================================================================================
// 1.10 🧠 HOOK PRINCIPAL (O CÉREBRO ZONAL BLINDADO)
// ===================================================================================
//!HOOK MAIN
//!DESC S1 - Meta-Cérebro Neuro-Estético (v3.0 Blindado)
//!SAVE GRX_MAPS
//!SAVE GRX_TEMPORAL
//!SAVE GRX_GOLDEN
//!SAVE GRX_LUMA
//!SAVE GRX_COLOR_LINEAR
//!BIND HOOKED
//!BIND PREV
//!COMPONENTS 4
vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 p = HOOKED_pt;

    // 1. LEITURA SEGURA
    if (!is_texture_valid(HOOKED, uv)) {
        return vec4(0.0); // Retorno seguro imediato em caso de corrupção
    }

    vec3 raw = clamp(texture(HOOKED, uv).rgb, 0.0, 1.0);
    // Compressor HDR Suave para análise
    vec3 safe_analysis_color = raw / (1.0 + raw);
    vec3 linear_color = sRGB_to_linear(safe_analysis_color);
    float Y_linear = safe_luma(linear_color);

    // 2. RELATÓRIOS DOS DETETIVES (COM INTELIGÊNCIA INJETADA)

    // Detetive Espacial
    float edge, variance, low_freq;
    calculate_spatial_metrics(uv, p, linear_color, Y_linear, edge, variance, low_freq);
    float exposure = calculate_exposure(Y_linear);

    // Detetive Temporal
    float motion, stability, flow_confidence, flicker_score;
    calculate_temporal_metrics(uv, p, Y_linear, motion, stability, flow_confidence, flicker_score);

    // Detetive Áureo
    float grid_density, pattern_entropy, harmonic_balance, aesthetic_score;
    calculate_golden_metrics(uv, p, linear_color, edge, low_freq, variance, grid_density, pattern_entropy, harmonic_balance, aesthetic_score);

    // Cartógrafo Zonal
    float shadow_dens, chroma_risk, mid_dens;
    calculate_zonal_metrics(linear_color, Y_linear, variance, edge, shadow_dens, chroma_risk, mid_dens);

    // ===================================================================================
    // 1.10.7 ⚖️ O JÚRI (JULGAMENTO E CÁLCULO DE CONFIANÇA)
    // ===================================================================================

    // Cálculo de Confiança Emocional
    float problems = grid_density + flicker_score + (chroma_risk * (1.0 - aesthetic_score));
    float stream_confidence = 1.0 - smoothstep(0.2, 0.8, problems);

    // Boost em áreas de Saliência
    stream_confidence = mix(stream_confidence, 1.0, aesthetic_score * 0.5);

    #ifndef PREV_tex
    stream_confidence = CONFIDENCE_FALLBACK;
    #endif

    // ++++++++++ ALARME TEMPORAL ++++++++++
    bool is_scene_cut = (flicker_score > 0.8) && (flow_confidence < 0.1);
    bool is_entropic_chaos = (pattern_entropy > 0.75) && (motion > 0.5);

    if (is_scene_cut || is_entropic_chaos) {
        stream_confidence = 0.0;
    }
    // +++++++++++++++++++++++++++++++++++++

    // ===================================================================================
    // 1.10.8 SAÍDA BLINDADA E SANITIZADA
    // ===================================================================================
    // A função sanitize_metrics garante que nenhum NaN/Inf vaze para a pipeline.

    // 1. GRX_MAPS (Dados Críticos de Estrutura)
    if (MAIN_index == 0) {
        vec4 result = vec4(edge, variance, exposure, stream_confidence);
        return sanitize_metrics(result, 0.0); // Fallback: sem estrutura
    }

    // 2. GRX_TEMPORAL (Dados de Movimento)
    if (MAIN_index == 1) {
        vec4 result = vec4(motion, stability, flow_confidence, flicker_score);
        return sanitize_metrics(result, 0.0); // Fallback: sem movimento (seguro)
    }

    // 3. GRX_GOLDEN (Dados Estéticos)
    if (MAIN_index == 2) {
        vec4 result = vec4(grid_density, pattern_entropy, harmonic_balance, aesthetic_score);
        return sanitize_metrics(result, 0.5); // Fallback: estética neutra
    }

    // 4. GRX_LUMA (Dados Zonais)
    if (MAIN_index == 3) {
        vec4 result = vec4(Y_linear, shadow_dens, chroma_risk, mid_dens);
        return sanitize_metrics(result, 0.0); // Fallback: sem risco
    }

    // 5. GRX_COLOR_LINEAR (Cor Base)
    if (MAIN_index == 4) {
        if (any(isnan(linear_color))) return vec4(0.0, 0.0, 0.0, 1.0);
        return vec4(linear_color, 1.0);
    }

    return vec4(0.5);
}
