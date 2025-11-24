// ===================================================================================
// S4_upscale_output.glsl — Upscale Híbrido Estético com Tone Mapping Yin-Yang (v2.0)
// ===================================================================================
// Licença: MIT / GPLv3 — Código aberto, auditável, modular
// Autor: Pipeline GRX - Estágio 4 (Mestre Upscaler & Tone Mapper)
// ===================================================================================
// OBJETIVO: Upscale inteligente, correção de erro e Tone Mapping "Yin-Yang"
// SAÍDA: OUTPUT (RGBA): .rgb=imagem final tratada, .a=quality_score
// ===================================================================================
// REGRAS DE OURO IMPLEMENTADAS:
// ✅ ORDEM OTIMIZADA: Denoise -> Deband -> Yin-Yang -> Sharpening -> TAA -> Efeitos
// ✅ Tone Mapping "Yin-Yang": Equilíbrio semântico entre esconder lixo e revelar luz
// ✅ Integração com Alarme S1 (Desligamento em Cascata para caos temporal)
// ✅ Upscale Híbrido Áureo com reprojeção de fluxo polido
// ✅ Sistema de Segurança Reforçado (Anti-NaN/Inf e Sanitização)
// ===================================================================================

// -------------------------
// 4.1 🔧 CONFIGURAÇÕES PRINCIPAIS - CONTROLES DO USUÁRIO
// -------------------------
// PARÂMETROS PRINCIPAIS (0.0-1.0)
#define UPSCALE_STRENGTH          0.65  // Força do upscale (0.0=bilinear, 1.0=máximo)
#define NOISE_CLEANUP_STRENGTH    0.75  // Força da limpeza de ruído pós-upscale
#define BANDING_REDUCTION         0.80  // Redução de banding
#define BRIGHTNESS_ADJUSTMENT     1.00  // Força do Yang (Luz) (-1.0 a 1.0)
#define CONTRAST_ENHANCEMENT      0.65  // Força do Yin (Contraste/Profundidade)
#define GAMMA_ADJUSTMENT          0.10  // Ajuste fino de Gama (0.05 a 0.20 ideal)
#define SHARPNESS_LEVEL           0.60  // Nível de nitidez
#define MOTION_STABILITY          0.85  // Estabilidade em movimento
#define FILM_LOOK_STRENGTH        0.35  // Intensidade do "look" cinematográfico

// FATOR DE UPSCALE
#define UPSCALE_FACTOR            2.0   // 1.5-4.0: Escala desejada

// CONTROLE DE SAÍDA (CRÍTICO)
// Defina como 1 se usar --gamut-mapping-mode=linear e --target-colorspace-hint=yes no MPV.
#define OUTPUT_LINEAR_FOR_MPV     1

// ATIVAÇÃO DE FUNCIONALIDADES (1=ON, 0=OFF)
#define ENABLE_HYBRID_UPSCALE     1
#define ENABLE_MOTION_COMP        1     // Requer TRAJECTORY_MAP ou Fluxo Polido
#define ENABLE_POST_UPSCALE_CLEAN 1
#define ENABLE_ADAPTIVE_SHARPEN   1
#define ENABLE_TEMPORAL_AA        1
#define ENABLE_FILM_GRAIN         1
#define ENABLE_DIRECTIONAL_SMEAR  1     // Smear direcional (Borracha Lavada)

// PARÂMETROS INTERNOS (Ajuste Fino)
#define LANCZOS_RADIUS_BASE       12.0
#define LANCZOS_ANTI_RINGING      0.95
#define CNN_REFINEMENT_STRENGTH   0.95
#define CNN_ITERATIONS_DEFAULT    256
#define CNN_CONVERGENCE_RATE      0.85
#define DEBAND_STRENGTH           0.55
#define DEBAND_SMOOTHNESS         0.85
#define BRIGHTEN_STRENGTH_BASE    0.95
#define DARKEN_STRENGTH_BASE      0.60
#define SHARP_BASE_GAIN           0.15
#define SHARP_MAX_GAIN            0.40
#define SHARP_MOTION_PENALTY      1.8
#define TAA_STRENGTH              0.95
#define TAA_MOTION_THRESHOLD      0.08
#define WASHED_RUBBER_STRENGTH    0.70
#define WASHED_RUBBER_EDGE_PROTECT 0.85
#define SMEAR_FLOW_FACTOR_NEW     0.75
#define FILM_GRAIN_INTENSITY      0.18
#define FILM_GRAIN_CONTRAST       0.75
#define SAFETY_FALLBACK           0.7
#define MIN_QUALITY_THRESHOLD     0.3
#define BASE_MARGIN               0.015

// ===================================================================================
// 4.2 🎯 CONSTANTES ÁUREAS FIXAS
// ===================================================================================
#define GOLDEN_RATIO              1.618033988749895
#define GOLDEN_CONJUGATE          0.618033988749895
#define GOLDEN_ANGLE              2.399963229728653
#define GOLDEN_SEQUENCE           2.618033988749895
#define GOLDEN_SQRT               1.272019649514069

// ===================================================================================
// 4.3 🔧 FUNÇÕES UTILITÁRIAS UNIFICADAS
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
// ✅ FUNÇÃO ÚNICA: ELU Shaper (para curvas suaves)
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
// 4.4 🛡️ SISTEMA DE SEGURANÇA PADRÃO
// ===================================================================================
#ifndef GRX_SAFETY_SYSTEM_DEFINED
#define GRX_SAFETY_SYSTEM_DEFINED
// ✅ FUNÇÃO ÚNICA: Validação de Textura
bool is_texture_valid(sampler2D tex, vec2 uv) {
    vec4 sample = texture(tex, uv);
    return all(greaterThanEqual(sample.rgb, vec3(0.0))) &&
    all(lessThanEqual(sample.rgb, vec3(1.0))) &&
    (length(sample.rgb) > 1e-6) &&
    !isnan(sample.r) && !isnan(sample.g) && !isnan(sample.b) &&
    !isinf(sample.r) && !isinf(sample.g) && !isinf(sample.b);
}
// ✅ FUNÇÃO ÚNICA: Detecção de Artefatos
bool detect_processing_artifacts(vec3 original, vec3 processed, vec2 uv, vec2 p, float threshold) {
    float diff = length(original - processed);
    float high_freq = 0.0;
    // Nota: A leitura de OUTPUT aqui assume que o shader anterior já escreveu algo
    // ou está sendo usado para comparação de vizinhança do passo anterior.
    for (int i = 0; i < 4; i++) {
        vec2 offset = vec2(0.0);
        if (i == 0) offset = vec2( p.x, 0.0);
        else if (i == 1) offset = vec2(-p.x, 0.0);
        else if (i == 2) offset = vec2(0.0,  p.y);
        else offset = vec2(0.0, -p.y);
        vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));
        high_freq += length(processed - sRGB_to_linear(texture(OUTPUT, sample_uv).rgb));
    }
    return (diff > threshold) || (high_freq > threshold * 2.0);
}
// ✅ FUNÇÃO ÚNICA: Sanitização de Saída
vec3 sanitize_output(vec3 color, vec3 fallback) {
    if (any(isnan(color)) || any(isinf(color))) return fallback;
    return max(color, vec3(0.0));
}
#endif

// ===================================================================================
// 4.5 🎨 GESTÃO DE CORES CONSISTENTE
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
// 4.6 🧹 LIMPEZA PÓS-UPSCALE
// ===================================================================================
vec3 residual_post_upscale_denoise(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps) {
    vec3 result = linear_rgb;
    #if ENABLE_POST_UPSCALE_CLEAN && NOISE_CLEANUP_STRENGTH > 0.01
    float denoise_mask = (1.0 - maps.r) * maps.g; // Áreas lisas
    float strength = clamp(denoise_mask * NOISE_CLEANUP_STRENGTH * 1.5, 0.0, 1.0);
    if (strength > 0.01) {
        vec3 accum = vec3(0.0);
        float total_weight = 0.0;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                vec2 offset = vec2(dx, dy) * p;
                vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));
                vec3 sample_linear = sRGB_to_linear(texture(OUTPUT, sample_uv).rgb);
                float spatial_weight = exp(-(dx*dx + dy*dy) * 0.8);
                float color_weight = exp(-length(sample_linear - linear_rgb) * 6.0);
                float weight = spatial_weight * color_weight;
                accum += sample_linear * weight;
                total_weight += weight;
            }
        }
        if (total_weight > 1e-6) {
            vec3 denoised = accum / total_weight;
            result = mix(linear_rgb, denoised, strength);
        }
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

vec3 intelligent_deband_post_upscale(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps, vec4 golden) {
    vec3 result = linear_rgb;
    #if ENABLE_POST_UPSCALE_CLEAN && BANDING_REDUCTION > 0.01
    float variance = maps.g;
    float pattern_entropy = golden.g;
    float aesthetic_score = golden.a;
    if (variance < 0.03 && pattern_entropy < 0.4 && BANDING_REDUCTION > 0.2) {
        vec3 neighbors[4];
        neighbors[0] = sRGB_to_linear(texture(OUTPUT, clamp(uv + vec2( p.x, 0.0), vec2(0.0), vec2(1.0))).rgb);
        neighbors[1] = sRGB_to_linear(texture(OUTPUT, clamp(uv - vec2( p.x, 0.0), vec2(0.0), vec2(1.0))).rgb);
        neighbors[2] = sRGB_to_linear(texture(OUTPUT, clamp(uv + vec2(0.0,  p.y), vec2(0.0), vec2(1.0))).rgb);
        neighbors[3] = sRGB_to_linear(texture(OUTPUT, clamp(uv - vec2(0.0,  p.y), vec2(0.0), vec2(1.0))).rgb);
        float smoothness = 0.0;
        for (int i = 0; i < 4; i++) smoothness += length(neighbors[i] - linear_rgb);
        smoothness = 1.0 - clamp(smoothness * 2.5, 0.0, 1.0);
        if (smoothness > 0.6) {
            vec3 avg = (neighbors[0] + neighbors[1] + neighbors[2] + neighbors[3]) * 0.25;
            float dither_strength = DEBAND_STRENGTH * BANDING_REDUCTION * smoothness;
            dither_strength *= (1.0 - aesthetic_score * 0.4);
            float noise = blueNoise(uv * HOOKED_size * GOLDEN_RATIO) * 0.012;
            float smoothness_factor = DEBAND_SMOOTHNESS * (1.0 - variance * 2.0);
            result = mix(linear_rgb, mix(avg, avg + vec3(noise), smoothness_factor), dither_strength);
        }
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 4.7 ☯️ EQUILÍBRIO YIN-YANG (COM PROTEÇÃO CROMÁTICA S1)
// ===================================================================================
vec3 adaptive_brightness_adjustment(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps, vec4 golden, vec4 luma) {
    vec3 result = linear_rgb;

    #if BRIGHTNESS_ADJUSTMENT != 0.0 || CONTRAST_ENHANCEMENT != 0.0

    // [DETECTOR DE HDR / SUPER-WHITES]
    float max_val = max(linear_rgb.r, max(linear_rgb.g, linear_rgb.b));
    float hdr_bypass = smoothstep(1.0, 1.5, max_val);
    if (hdr_bypass > 0.99) return linear_rgb;

    // [LEITURA DOS MAPAS S1 v2.1]
    float Y = safe_luma(linear_rgb);
    float chroma_risk = luma.b;    // Risco de ruído colorido
    float shadow_dirt = luma.g;    // Sujeira em sombras
    float aesthetic = golden.a;    // Saliência
    float entropy = golden.g;

    // [YIN - COMPRESSÃO DE SOMBRA]
    // Se houver sujeira confirmada ou risco cromático, aumentamos o ponto preto
    float yin_trigger = max(shadow_dirt, chroma_risk * 0.5);
    float yin_strength = smoothstep(0.05, 0.2, yin_trigger) * (1.0 - aesthetic * 0.5);

    float black_level_target = 0.03 * yin_strength * DARKEN_STRENGTH_BASE;
    black_level_target *= (1.0 - smoothstep(0.02, 0.15, Y));

    // [YANG - EXPANSÃO DE LUZ]
    float lift_factor = BRIGHTNESS_ADJUSTMENT * BRIGHTEN_STRENGTH_BASE;
    lift_factor *= (0.7 + 0.3 * aesthetic);

    // [APLICAÇÃO]
    vec3 soft_base = max(vec3(1e-5), linear_rgb - black_level_target);
    float gamma_guide = 1.0 - (lift_factor * 0.3);
    vec3 processed = pow(soft_base, vec3(gamma_guide));

    // Contraste
    float contrast_power = 1.0 + (CONTRAST_ENHANCEMENT * 0.4) + (yin_strength * 0.1);
    processed = pow(processed, vec3(contrast_power));

    // Recuperação de Saturação (INTELIGENTE: Usa hsv2rgb centralizado)
    float saturation_boost = (1.0 + CONTRAST_ENHANCEMENT * 0.15);
    saturation_boost *= (1.0 - chroma_risk);

    vec3 hsv = rgb2hsv(linear_to_sRGB(processed));
    hsv.y *= saturation_boost;
    processed = sRGB_to_linear(hsv2rgb(hsv));

    // [MISTURA FINAL COM BYPASS HDR]
    result = mix(processed, linear_rgb, hdr_bypass);

    #endif

    // Patch de Gama Global
    #if GAMMA_ADJUSTMENT != 0.0
    if (abs(GAMMA_ADJUSTMENT) < 0.3) {
        vec3 gamma_corrected = pow(max(vec3(1e-5), result), vec3(1.0 + GAMMA_ADJUSTMENT));
        result = mix(gamma_corrected, linear_rgb, hdr_bypass);
    }
    #endif

    // [DITHERING SDR]
    if (hdr_bypass < 0.5) {
        float dither = blueNoise(uv * HOOKED_size * GOLDEN_RATIO) * 0.004;
        result += (dither - 0.002);
    }

    return max(result, vec3(0.0));
}

// ===================================================================================
// 4.8 🔍 SHARPENING ULTIMATE (S1 DRIVEN + ASSIMÉTRICO)
// ===================================================================================
vec3 adaptive_sharpening_safe(vec2 uv, vec2 p, vec3 input_linear, vec4 maps, vec4 temporal, vec4 golden, sampler2D linear_tex) {
    vec3 result = input_linear;

    #if ENABLE_ADAPTIVE_SHARPEN && SHARPNESS_LEVEL > 0.01

    // 1. Kill Switch de Caos (S1 Confidence)
    if (maps.a < 0.2) return input_linear;

    // 2. PARÂMETROS DO S1
    float edge = maps.r;            // Bordas
    float noise_entropy = golden.g; // Grão / Textura Fina
    float aesthetic = golden.a;     // Saliência
    float stability = temporal.g;   // Estabilidade

    // 3. MÁSCARA DE PROTEÇÃO
    float sharpen_mask = (1.0 - edge * 0.4) * (1.0 - noise_entropy * 0.6);
    sharpen_mask *= (0.6 + 0.4 * aesthetic);
    sharpen_mask *= stability;

    if (sharpen_mask < 0.05) return input_linear;

    // 4. CAS SIMPLIFICADO
    vec3 n = texture(linear_tex, uv + vec2(0, -1) * p).rgb;
    vec3 s = texture(linear_tex, uv + vec2(0,  1) * p).rgb;
    vec3 w = texture(linear_tex, uv + vec2(-1, 0) * p).rgb;
    vec3 e = texture(linear_tex, uv + vec2( 1, 0) * p).rgb;

    vec3 min_c = min(input_linear, min(min(n, s), min(w, e)));
    vec3 max_c = max(input_linear, max(max(n, s), max(w, e)));

    float amp = 1.0 / (SHARPNESS_LEVEL * sharpen_mask + 0.01);
    amp = clamp(amp, 0.0, 3.0);

    // Soft Limiting
    vec3 sharp = input_linear + (input_linear - (n + s + w + e) * 0.25) * amp;
    sharp = clamp(sharp, min_c, max_c);

    // 5. ASSIMETRIA (Dark-bias)
    vec3 delta = sharp - input_linear;
    float luma_delta = dot(delta, vec3(0.299, 0.587, 0.114));
    if (luma_delta > 0.0) delta *= 0.6; // Reduz halos claros
    else delta *= 1.2;                  // Aumenta definição escura

    result = input_linear + delta;

    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 4.9 ⏱️ TAA QUANTUM LÁZARO (S1 DRIVEN + SANITIZED HISTORY)
// ===================================================================================
// Função auxiliar para ler o histórico de forma "Sanitizada"
vec3 sample_lazarus_history(sampler2D prev_tex, vec2 uv, vec2 p) {
    vec3 acc = vec3(0.0);
    acc += texture(prev_tex, uv + vec2( 0.5,  0.5) * p).rgb;
    acc += texture(prev_tex, uv + vec2(-0.5,  0.5) * p).rgb;
    acc += texture(prev_tex, uv + vec2( 0.5, -0.5) * p).rgb;
    acc += texture(prev_tex, uv + vec2(-0.5, -0.5) * p).rgb;
    return acc * 0.25;
}

vec3 complete_taa_processing(vec2 uv, vec2 p, vec3 sharpened_linear, vec4 maps, vec4 temporal, vec4 golden) {
    vec3 result = sharpened_linear;

    #if ENABLE_TEMPORAL_AA && ENABLE_MOTION_COMP
    #ifdef PREV_tex
    if (true) {
        // 1. DADOS DE FLUXO
        vec2 motion_vector = GRX_FLOW_REFINED_tex(uv).rg;
        vec2 prev_uv = uv - motion_vector;

        // Validação de limites (reforçada)
        if (any(lessThan(prev_uv, vec2(0.0))) || any(greaterThan(prev_uv, vec2(1.0)))) return result;

        // 2. INTELIGÊNCIA S1
        float stability = temporal.g;
        float aesthetic = golden.a;   // Saliência
        float motion_mag = temporal.r;// Magnitude

        // 3. LEITURA LÁZARO (Híbrida)
        vec3 prev_linear;
        if (stability > 0.8) {
            prev_linear = texture(PREV, prev_uv).rgb;
        } else {
            // Em caos, misturamos com o histórico borrado (Lázaro)
            vec3 sharp_hist = texture(PREV, prev_uv).rgb;
            vec3 soft_hist = sample_lazarus_history(PREV, prev_uv, p);
            prev_linear = mix(sharp_hist, soft_hist, 1.0 - smoothstep(0.3, 0.9, stability));
        }

        // 4. VIZINHANÇA (Clamping)
        vec3 n = texture(GRX_COLOR_LINEAR, uv + vec2(0, p.y)).rgb;
        vec3 s = texture(GRX_COLOR_LINEAR, uv - vec2(0, p.y)).rgb;
        vec3 w = texture(GRX_COLOR_LINEAR, uv + vec2(p.x, 0)).rgb;
        vec3 e = texture(GRX_COLOR_LINEAR, uv - vec2(p.x, 0)).rgb;

        vec3 min_c = min(sharpened_linear, min(min(n, s), min(w, e)));
        vec3 max_c = max(sharpened_linear, max(max(n, s), max(w, e)));

        float relax = 0.01 + stability * 0.05;
        prev_linear = clamp(prev_linear, min_c - vec3(relax), max_c + vec3(relax));

        // 5. MISTURA FINAL (O FACE GUARD)
        float blend = TAA_STRENGTH;
        blend *= (0.5 + 0.5 * stability);

        // *** FACE GUARD ***
        if (aesthetic > 0.65 && motion_mag > 0.1) {
            blend *= 0.2;
        }

        result = mix(sharpened_linear, prev_linear, blend);
    }
    #endif
    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 4.10 🎨 NEURO-GRANULADOR ÁUREO (FILM LOOK SEMÂNTICO)
// ===================================================================================
vec3 washed_rubber_effect(vec2 uv, vec2 p, vec3 rgb_linear, vec4 maps, vec4 temporal, vec4 golden) {
    vec3 result = rgb_linear;

    #if FILM_LOOK_STRENGTH > 0.01 && ENABLE_FILM_GRAIN

    // 1. ANÁLISE DA FRAGILIDADE
    float edge = maps.r;
    float variance = maps.g;
    float aesthetic = golden.a;
    float motion = temporal.r;
    float luma = safe_luma(rgb_linear);

    float fragility_mask = (1.0 - variance * 2.0) * (1.0 - aesthetic * 0.5);
    fragility_mask = clamp(fragility_mask, 0.0, 1.0);

    // 2. PROTEÇÃO LUMINOSA
    float luma_mask = 1.0 - smoothstep(0.0, 0.15, luma);
    luma_mask *= (1.0 - smoothstep(0.85, 1.0, luma));

    // 3. MÁSCARA FINAL DE INJEÇÃO
    float grain_strength = FILM_LOOK_STRENGTH;
    grain_strength *= (1.0 + fragility_mask * 0.8);
    grain_strength *= (1.0 - edge * 0.8) * (1.0 - motion * 0.5);
    grain_strength *= luma_mask;

    // Patch S0: Confiança
    float stream_confidence = maps.a;
    grain_strength *= stream_confidence;

    if (grain_strength > 0.005) {
        // 4. GERAÇÃO DO GRÃO ÁUREO
        float noise_high = blueNoise(uv * HOOKED_size * GOLDEN_RATIO);
        float noise_mid  = blueNoise(uv * HOOKED_size * GOLDEN_CONJUGATE + vec2(13.37));
        float noise_low  = blueNoise(uv * HOOKED_size * 0.5 + vec2(GOLDEN_SEQUENCE));

        float organic_noise = (noise_high * 0.6 + noise_mid * 0.3 + noise_low * 0.1);
        organic_noise -= 0.5;

        // 5. APLICAÇÃO
        vec3 grain_layer = vec3(organic_noise) * FILM_GRAIN_INTENSITY * grain_strength;
        result += grain_layer * vec3(1.0, 0.95, 1.05);

        // 6. SMEAR LÍQUIDO
        #if ENABLE_DIRECTIONAL_SMEAR == 1
        vec2 clean_flow = GRX_FLOW_REFINED_tex(uv).rg;
        float flow_len = length(clean_flow);

        if (flow_len > 0.002 && WASHED_RUBBER_STRENGTH > 0.0) {
            float is_chaos = 1.0 - stream_confidence;
            float dynamic_factor = SMEAR_FLOW_FACTOR_NEW * (1.0 - is_chaos * 0.5);
            vec2 smear_uv = uv - clean_flow * dynamic_factor;
            vec3 smear_sample = textureLod(STAGE3_ENHANCED, clamp(smear_uv, 0.0, 1.0), 1.0).rgb;

            float smear_opacity = WASHED_RUBBER_STRENGTH * flow_len * 10.0;
            smear_opacity *= (1.0 - edge * 0.8);
            smear_opacity = mix(smear_opacity, smear_opacity * 1.5, is_chaos);
            smear_opacity = clamp(smear_opacity, 0.0, 0.4);

            result = mix(result, smear_sample, smear_opacity);
        }
        #endif
    }
    #endif

    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 4.11 🌑 UPSCALE HÍBRIDO ÁUREO (COM ANTI-RINGING ESTRITO)
// ===================================================================================
float lanczos_weight(float x, float a) {
    if (abs(x) < 1e-6) return 1.0;
    x = abs(x); if (x >= a) return 0.0;
    float pix = 3.141592653589793 * x;
    return (sin(pix) / pix) * (sin(pix/a) / (pix/a));
}
vec3 high_quality_lanczos_upscale(vec2 uv, vec2 p, vec2 source_size, vec2 target_size, sampler2D source_tex, vec4 maps) {
    vec2 scale = target_size / source_size;
    vec2 source_p = p * (1.0 / scale);
    vec2 source_uv = uv * (1.0 / scale);

    float adaptive_radius = LANCZOS_RADIUS_BASE * (0.5 + 0.5 * UPSCALE_STRENGTH);
    adaptive_radius *= mix(1.0, 0.7, maps.r);

    vec3 accum = vec3(0.0);
    float weight_accum = 0.0;
    vec3 min_val = vec3(1.0), max_val = vec3(0.0);

    for (float dy = -adaptive_radius; dy <= adaptive_radius; dy += 1.0) {
        for (float dx = -adaptive_radius; dx <= adaptive_radius; dx += 1.0) {
            vec2 off = vec2(dx, dy) * source_p;
            vec2 suv = clamp(source_uv + off, 0.0, 1.0);
            vec3 sample = sRGB_to_linear(texture(source_tex, suv).rgb);

            float w = lanczos_weight(dx, adaptive_radius) * lanczos_weight(dy, adaptive_radius);
            min_val = min(min_val, sample); max_val = max(max_val, sample);
            accum += sample * w;
            weight_accum += w;
        }
    }
    vec3 result = (weight_accum > 1e-6) ? accum / weight_accum : sRGB_to_linear(texture(source_tex, source_uv).rgb);

    // [CORREÇÃO DO TRAMPOLIM HDR]
    float ringing = LANCZOS_ANTI_RINGING * (1.0 - maps.r);
    float margin = ringing * 0.1;
    vec3 limit_min = max(vec3(0.0), min_val - vec3(margin));
    vec3 limit_max = max_val + vec3(margin);

    return clamp(result, limit_min, limit_max);
}

// ===================================================================================
// 4.12 🧠 REFINAMENTO CNN AVANÇADO (DILATADO E GUIADO PELO S1)
// ===================================================================================
vec3 cnn_advanced_refinement(vec2 uv, vec2 p, vec3 upscaled_linear, vec4 maps, vec4 temporal, vec4 golden) {
    vec3 result = upscaled_linear;
    #if CNN_REFINEMENT_STRENGTH > 0.01

    float edge = maps.r;
    float confidence = maps.a;
    float grid = golden.r;

    // 2. CONFIGURAÇÃO DINÂMICA DO KERNEL
    float refine_strength = CNN_REFINEMENT_STRENGTH * UPSCALE_STRENGTH;
    refine_strength *= (1.2 - confidence * 0.4);
    refine_strength *= (1.0 + grid * 0.5);
    refine_strength = clamp(refine_strength, 0.0, CNN_REFINEMENT_STRENGTH * 1.5);

    if (refine_strength > 0.01) {
        float dilation = 1.0 + (1.0 - edge) * 1.5 + grid * 2.0;
        if (confidence < 0.2) dilation = 3.0;

        // Pesos do Kernel (Áureos)
        float w_center = 0.40;
        float w_cardinal = 0.10 * GOLDEN_CONJUGATE;
        float w_diagonal = 0.05 * GOLDEN_CONJUGATE;

        float ringing_dampener = 1.0 - edge * 0.5;
        w_cardinal *= ringing_dampener;
        w_diagonal *= ringing_dampener;

        float total_weight = w_center + 4.0 * w_cardinal + 4.0 * w_diagonal;
        w_center /= total_weight;
        w_cardinal /= total_weight;
        w_diagonal /= total_weight;

        // 4. A CONVOLUÇÃO (Residual Learning)
        vec3 cnn_accum = vec3(0.0);
        int iterations = clamp(int(CNN_ITERATIONS_DEFAULT * refine_strength), 1, 128);

        for (int iter = 0; iter < iterations; iter++) {
            vec3 local_accum = vec3(0.0);

            // Centro
            local_accum += texture(OUTPUT, uv).rgb * w_center;

            // Cardeais + Diagonais
            vec2 d = p * dilation;
            local_accum += sRGB_to_linear(texture(OUTPUT, uv + vec2( d.x, 0.0)).rgb) * w_cardinal;
            local_accum += sRGB_to_linear(texture(OUTPUT, uv - vec2( d.x, 0.0)).rgb) * w_cardinal;
            local_accum += sRGB_to_linear(texture(OUTPUT, uv + vec2(0.0,  d.y)).rgb) * w_cardinal;
            local_accum += sRGB_to_linear(texture(OUTPUT, uv - vec2(0.0,  d.y)).rgb) * w_cardinal;

            local_accum += sRGB_to_linear(texture(OUTPUT, uv + vec2( d.x,  d.y)).rgb) * w_diagonal;
            local_accum += sRGB_to_linear(texture(OUTPUT, uv - vec2( d.x,  d.y)).rgb) * w_diagonal;
            local_accum += sRGB_to_linear(texture(OUTPUT, uv + vec2( d.x, -d.y)).rgb) * w_diagonal;
            local_accum += sRGB_to_linear(texture(OUTPUT, uv - vec2( d.x, -d.y)).rgb) * w_diagonal;

            vec3 residual = local_accum - result;
            float learn_rate = (confidence < 0.2) ? 0.5 : CNN_CONVERGENCE_RATE;
            float step_strength = refine_strength * pow(learn_rate, float(iter));

            result += residual * step_strength;
        }

        // 5. PROTEÇÃO DE CROMA
        float Y_orig = safe_luma(upscaled_linear);
        float Y_refined = safe_luma(result);
        float luma_mix = mix(Y_refined, Y_orig, confidence);

        vec3 chroma_refined = result - vec3(Y_refined);
        result = vec3(luma_mix) + chroma_refined;
    }
    #endif

    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 4.13 🎯 SISTEMA DE CONTROLE DE SAÍDA (MODO LINEAR/ACES)
// ===================================================================================

float calculate_final_quality_score(vec3 orig, vec3 final, vec4 maps, vec4 golden) {
    float diff = length(orig - final);
    float q = 1.0 - diff * 0.4;
    q += golden.a * 0.2;
    return clamp(q, MIN_QUALITY_THRESHOLD, 1.0);
}
bool should_apply_technique(vec4 maps, vec4 temporal, vec4 golden, float cost) {
    float score = (float(maps.a > 0.6)*2.0 + float(temporal.r < 0.3)*1.5 + float(golden.a > 0.4)) / 4.5;
    return score > (0.6 - cost * 0.2);
}

//!HOOK MAIN
//!DESC S4 - Upscale (Content Aware & Linear)
//!BIND HOOKED
//!BIND STAGE3_ENHANCED
//!BIND GRX_MAPS
//!BIND GRX_TEMPORAL
//!BIND GRX_GOLDEN
//!BIND GRX_LUMA
//!BIND GRX_COLOR_LINEAR
//!BIND GRX_FLOW_REFINED
//!BIND PREV
//!BIND GRX_DETAIL_MAP
//!BIND OUTPUT
//!SAVE OUTPUT
//!COMPONENTS 4
vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 p = HOOKED_pt;
    vec2 source_size = HOOKED_size;
    vec2 target_size = vec2(MAIN_w, MAIN_h) * UPSCALE_FACTOR;

    vec4 maps = GRX_MAPS_tex(uv);
    vec4 temporal = GRX_TEMPORAL_tex(uv);
    vec4 golden = GRX_GOLDEN_tex(uv);
    vec3 stage3_linear = texture(STAGE3_ENHANCED, clamp(uv, 0.0, 1.0)).rgb;

    // --- DETECTOR DE CONTEÚDO (ANIME vs REAL) ---
    float entropy = golden.g;
    float variance = maps.g;
    float is_anime_score = (1.0 - smoothstep(0.2, 0.6, entropy)) * (1.0 - smoothstep(0.01, 0.05, variance));

    // MODULADORES AUTOMÁTICOS:
    float auto_sharp_mod = mix(1.0, 0.6, is_anime_score);
    float auto_grain_mod = mix(1.0, 0.2, is_anime_score);
    float stream_confidence = maps.a;
    float chaos_dampener = clamp(pow(stream_confidence, 3.0), 0.0, 1.0);

    // --- 1. UPSCALE HÍBRIDO ---
    vec3 upscaled_linear = stage3_linear;
    if (ENABLE_HYBRID_UPSCALE) {
        upscaled_linear = high_quality_lanczos_upscale(uv, p, source_size, target_size, STAGE3_ENHANCED, maps);
        if (stream_confidence < 0.5) {
            vec3 bicubic = texture(STAGE3_ENHANCED, uv).rgb;
            upscaled_linear = mix(bicubic, upscaled_linear, stream_confidence * 2.0);
        }
    }

    // --- 2. REFINAMENTO CNN ---
    vec3 current = upscaled_linear;
    if (should_apply_technique(maps, temporal, golden, 0.2)) {
        vec3 cnn_result = cnn_advanced_refinement(uv, p, current, maps, temporal, golden);
        current = mix(current, cnn_result, chaos_dampener);
    }

    // --- 3. DENOISE E DEBAND ---
    if (should_apply_technique(maps, temporal, golden, 0.3)) current = residual_post_upscale_denoise(uv, p, current, maps);
    if (should_apply_technique(maps, temporal, golden, 0.4)) {
        current = intelligent_deband_post_upscale(uv, p, current, maps, golden);
    }

    // --- 4. TONE MAPPING ---
    if (BRIGHTNESS_ADJUSTMENT != 0.0 || CONTRAST_ENHANCEMENT != 0.0) {
        current = adaptive_brightness_adjustment(uv, p, current, maps, golden, GRX_LUMA_tex(uv));
    }

    // --- 5. RE-INJEÇÃO DE DETALHE ---
    vec3 good_detail = GRX_DETAIL_MAP_tex(uv).rgb;
    current += good_detail * maps.a * chaos_dampener * (1.0 - is_anime_score * 0.8);

    // --- 6. SHARPENING ---
    if (ENABLE_ADAPTIVE_SHARPEN && should_apply_technique(maps, temporal, golden, 0.6)) {
        vec3 sharp = adaptive_sharpening_safe(uv, p, current, maps, temporal, golden, GRX_COLOR_LINEAR);
        float final_sharp_strength = UPSCALE_STRENGTH * SHARPNESS_LEVEL * chaos_dampener * auto_sharp_mod;
        current = mix(current, sharp, final_sharp_strength);
    }

    // --- 7. TAA ---
    if (ENABLE_TEMPORAL_AA && should_apply_technique(maps, temporal, golden, 0.7)) {
        current = complete_taa_processing(uv, p, current, maps, temporal, golden);
    }

    // --- 8. NEURO-GRANULADOR ---
    if (should_apply_technique(maps, temporal, golden, 0.8)) {
        vec3 grain_result = washed_rubber_effect(uv, p, current, maps, temporal, golden);
        current = mix(current, grain_result, auto_grain_mod);
    }

    // --- 9. DITHERING FINAL ---
    if (is_anime_score > 0.8) {
        float dither = blueNoise(uv * source_size) * 0.003;
        current += (dither - 0.0015);
    }

    // --- 10. SEGURANÇA E SAÍDA ---
    // Usando a nova função detect_processing_artifacts (que agora lê OUTPUT com segurança)
    if (detect_processing_artifacts(stage3_linear, current, uv, p, 0.3)) {
        current = mix(stage3_linear, current, SAFETY_FALLBACK);
    }

    // Usando a nova função sanitize_output
    current = sanitize_output(current, stage3_linear);

    float quality = calculate_final_quality_score(stage3_linear, current, maps, golden);

    #if OUTPUT_LINEAR_FOR_MPV
    return vec4(current, quality);
    #else
    return vec4(linear_to_sRGB(current), quality);
    #endif
}
