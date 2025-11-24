// ===================================================================================
// S2_cleaning_reconstruction.glsl — Firewall Estrutural com Inteligência Contextual (v3.1 "Architect+")
// ===================================================================================
// Licença: MIT / GPLv3 — Código aberto, auditável, modular
// Autor: Pipeline GRX - Estágio 2 (O Cirurgião de Fluxo)
// ===================================================================================
// FILOSOFIA REVISADA:
// 1. Limpeza Inteligente: Remove APENAS o que o S1 identificou como "ruído feio"
// 2. Preservação do Esqueleto: Mantém a estrutura para o S3/S4 reinjetarem detalhe "bonito"
// 3. Adaptação Emocional: Trata sombras, midtones e highlights como ecossistemas distintos
// 4. Integração Total com o Alarme: Desliga em cascata quando o caos ataca
// ===================================================================================

// -------------------------
// 2.1 🔧 CONFIGURAÇÕES PRINCIPAIS (AJUSTADAS PARA A INTELIGÊNCIA CONTEXTUAL)
// -------------------------
#define ENABLE_ADAPTIVE_DENOISE       1
#define ENABLE_DIRECTIONAL_DEBLOCK    1 // Mantido, mas com controle do S1
#define ENABLE_GRADIENT_DEBAND        1 // Mantido, mas com máscara emocional
#define ENABLE_CNN_LIGHT_RECON        1
#define ENABLE_DETAIL_RECONSTRUCTION  1
#define ENABLE_MULTI_VECTOR_POLISH    1
#define ENABLE_SAFETY_CHECKS          1
#define ENABLE_BRIGHT_AREA_PROTECTION 1
#define ENABLE_ANIME_CHAOS_SOLVER     1 // 1=Auto (Ativa "IA" de traços se detectar Anime), 0=Off

// Intensidades Base (Agora adaptativas ao contexto emocional)
#define DENOISE_STRENGTH              0.85 // Reduzido para preservar textura artística
#define DEBLOCK_STRENGTH              0.90 // Reduzido para não lavar detalhes reais
#define DEBAND_STRENGTH               0.65 // Equilíbrio entre limpeza e naturalidade
#define RECONSTRUCTION_STRENGTH       0.70
#define DETAIL_STRENGTH               0.35

// Parâmetros Nucleares (Agora com controle emocional)
#define SHADOW_NUKE_LEVEL             0.12 // Limiar ajustado para não matar grão de filme
#define CHROMA_NUKE_STRENGTH          0.85 // Reduzido para preservar tons de pele no escuro
#define FLAT_AREA_DEBAND_THRESHOLD    0.03 // Limiar para detecção de banding
#define STRUCTURAL_PROTECTION_FACTOR  0.75 // Fator de proteção de estruturas reais

// ===================================================================================
// 🎯 CONSTANTES ÁUREAS FIXAS (MANTIDAS)
// ===================================================================================
#define GOLDEN_RATIO          1.618033988749895
#define GOLDEN_CONJUGATE      0.618033988749895
#define GOLDEN_ANGLE          2.399963229728653
#define GOLDEN_SEQUENCE       2.618033988749895
#define GOLDEN_SQRT           1.272019649514069

// ===================================================================================
// 2.2 🔧 FUNÇÕES UTILITÁRIAS UNIFICADAS (PADRÃO S2 BLINDADO)
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
// ✅ FUNÇÃO ÚNICA: Ruído Azul
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
// ✅ FUNÇÃO ÚNICA: Conversão HSV
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
vec3 hsv2rgb(vec3 hsv) {
    vec3 rgb = clamp(abs(mod(hsv.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return ((rgb - 1.0) * hsv.y + 1.0) * hsv.z;
}
#endif

// ===================================================================================
// 2.3 🛡️ SISTEMA DE SEGURANÇA E VALIDAÇÃO (ALFÂNDEGA S1)
// ===================================================================================
#ifndef GRX_SAFETY_SYSTEM_DEFINED
#define GRX_SAFETY_SYSTEM_DEFINED

// 1. Validação de Textura (Anti-NaN/Inf)
bool is_texture_valid(sampler2D tex, vec2 uv) {
    #if ENABLE_SAFETY_CHECKS
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return false;
    vec4 sample = texture(tex, uv);
    // Verifica validade numérica estrita
    return !any(isnan(sample)) && !any(isinf(sample));
    #else
    return true;
    #endif
}

// 2. Sanitizador de Dados do S1 (NOVO)
// Garante que o S2 nunca receba instruções de "Edge" ou "Variance" corrompidas.
vec4 validate_s1_data(vec4 map_data) {
    if (any(isnan(map_data)) || any(isinf(map_data))) {
        // Fallback seguro: Edge=0, Variance=0, Exposure=0.5, Confidence=0
        return vec4(0.0, 0.0, 0.5, 0.0);
    }
    return clamp(map_data, 0.0, 1.0);
}

// 3. Gradiente Seguro (Proteção contra leitura fora de borda)
vec3 get_gradient_safe(sampler2D tex, vec2 uv, vec2 p, vec2 dir, float edge_strength) {
    vec2 uv_fwd = clamp(uv + dir * p, 0.0, 1.0);
    vec2 uv_bwd = clamp(uv - dir * p, 0.0, 1.0);

    vec3 forward = texture(tex, uv_fwd).rgb;
    vec3 backward = texture(tex, uv_bwd).rgb;

    // Trava de segurança para NaNs
    if (any(isnan(forward))) forward = vec3(0.0);
    if (any(isnan(backward))) backward = vec3(0.0);

    // Se é borda forte, reduzimos o gradiente para não amplificar artefatos
    float edge_dampener = 1.0 - edge_strength * 0.8;
    return (forward - backward) * edge_dampener;
}

// 4. Detecção de Artefatos (CORRIGIDO)
// Agora sabe diferenciar "Limpeza" de "Destruição".
bool detect_processing_artifacts(vec3 original, vec3 processed, vec4 maps, vec4 golden, float base_threshold) {
    #if ENABLE_SAFETY_CHECKS

    // 1. LEITURA DO CONTEXTO (S1)
    float variance = maps.g;       // O quanto a área original era caótica?
    float aesthetic = golden.a;    // O quanto a área original era importante?
    float edge = maps.r;           // É uma borda?

    // 2. CÁLCULO DA MUDANÇA REAL
    float diff = length(original - processed);

    // Se a mudança for imperceptível, aprova logo.
    if (diff < 0.02) return false;

    // 3. TOLERÂNCIA DINÂMICA (A Mágica)
    // Começamos com o limite base (ex: 0.1)
    float dynamic_threshold = base_threshold;

    // PERMISSÃO PARA LIMPAR:
    // Se a variância é alta (ruído), PERMITIMOS que a imagem mude drasticamente.
    // Queremos que o ruído suma, então a diferença TEM que ser grande.
    // Se variance for 1.0 (chuvisco), a tolerância sobe muito.
    dynamic_threshold += variance * 2.0;

    // PROTEÇÃO DE ESTRUTURA:
    // Se for uma área estética (rosto) ou borda forte, apertamos a segurança.
    // Não queremos borrar rostos nem destruir bordas.
    float protection_factor = max(aesthetic, edge);
    dynamic_threshold *= (1.0 - protection_factor * 0.5);

    // 4. VERIFICAÇÃO DE ALTA FREQUÊNCIA (Ringing)
    // Artefatos digitais (erros de shader) costumam criar oscilações rápidas (pixels xadrez).
    // Limpeza de ruído costuma criar suavidade.
    // Vamos checar se criamos "lixo" de alta frequência.
    // (Simplificado para performance: checa se a diferença é errática)

    // Se a diferença é maior que a tolerância calculada -> ARTEFATO DETECTADO
    // Mas, se for apenas "limpeza" (diff alta mas variance alta), o dynamic_threshold absorve.
    bool is_failure = (diff > dynamic_threshold);

    // Salva-vidas final: Se o S1 disse que era CAOS TOTAL (Confidence < 0.1),
    // qualquer tentativa de "processar" pode ser perigosa.
    if (maps.a < 0.1 && diff > 0.1) is_failure = true;

    return is_failure;

    #else
    return false;
    #endif
}
#endif

// ===================================================================================
// 🎨 GESTÃO DE CORES (MANTIDA)
// ===================================================================================
#ifndef GRX_COLOR_MANAGEMENT_DEFINED
#define GRX_COLOR_MANAGEMENT_DEFINED
vec3 sRGB_to_linear(vec3 srgb) {
    bvec3 cutoff = lessThan(srgb, vec3(0.04045));
    vec3 higher = pow((srgb + 0.055) / 1.055, vec3(2.4));
    vec3 lower = srgb / 12.92;
    return mix(higher, lower, cutoff);
}
vec3 linear_to_sRGB(vec3 linear) {
    bvec3 cutoff = lessThan(linear, vec3(0.0031308));
    vec3 higher = 1.055 * pow(linear, vec3(1.0/2.4)) - 0.055;
    vec3 lower = linear * 12.92;
    return mix(higher, lower, cutoff);
}
#endif

// ===================================================================================
// 2.3 🧼 SISTEMA DE LIMPEZA INTELIGENTE (O CORAÇÃO DA INOVAÇÃO)
// ===================================================================================

// 1. Denoising Estrutural com Consciência Emocional (NL-Means Adaptativo)
vec3 emotional_structural_denoise(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps, vec4 golden, vec4 luma) {
    vec3 result = linear_rgb;
    #if ENABLE_ADAPTIVE_DENOISE
    float edge_strength = maps.r;       // Borda do S1 (0.0=liso, 1.0=borda forte)
    float pattern_entropy = golden.g;  // Entropia do S1 (0.0=organizado, 1.0=caos)
    float aesthetic_score = golden.a;  // Beleza do S1 (0.0=feio, 1.0=lindo)
    float brightness = luma.r;         // Brilho

    // 🎭 A INTELIGÊNCIA EMOCIONAL:
    // Se é "bonito" (aesthetic_score alto), reduzimos a limpeza para preservar a textura artística
    // Se é "caos" (pattern_entropy alto) e "feio", aumentamos a limpeza
    float emotional_factor = 1.0 - (aesthetic_score * 0.6) + (pattern_entropy * 0.4);
    emotional_factor = clamp(emotional_factor, 0.3, 1.2);

    // Força adaptativa com múltiplas proteções
    float strength = DENOISE_STRENGTH * emotional_factor;
    strength *= (1.0 - edge_strength * 0.85);       // Protege bordas fortes
    strength *= (1.0 - aesthetic_score * 0.3);     // Protege áreas bonitas
    strength *= (1.0 + (1.0 - brightness) * 0.4);  // Mais forte nas sombras

    if (strength < 0.03) return result;

    // 📐 ANÁLISE DE ESTRUTURA LOCAL (NL-Means Inteligente)
    vec3 accum = vec3(0.0);
    float total_weight = 0.0;

    // Raio adaptativo baseado na complexidade
    float base_radius = 1.5;
    float complexity_radius = pattern_entropy * 1.0; // Áreas caóticas precisam de busca maior
    float radius = base_radius + complexity_radius;

    // Amostragem em espiral áurea para eficiência e cobertura
    int samples = int(8.0 * (1.0 + pattern_entropy));
    for (int i = 0; i < samples; i++) {
        float ratio = float(i) / float(samples);
        float angle = float(i) * GOLDEN_ANGLE;
        float dist = ratio * radius;
        vec2 offset = vec2(cos(angle), sin(angle)) * dist * p;

        vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));
        vec3 sample_color = texture(GRX_COLOR_LINEAR, sample_uv).rgb;

        // 🎚️ PESOS ESTRATÉGICOS:
        // 1. Peso espacial (gaussiano)
        float spatial_dist = length(offset);
        float spatial_weight = exp(-spatial_dist * spatial_dist * 0.6);

        // 2. Peso de cor (adaptativo à borda)
        float color_diff = length(sample_color - linear_rgb);
        float color_sensitivity = 8.0 + edge_strength * 12.0; // Em bordas, mais sensível a diferenças
        float color_weight = exp(-color_diff * color_diff * color_sensitivity);

        // 3. Peso estrutural (coerência de padrão)
        float structural_weight = 1.0 + (1.0 - pattern_entropy) * 0.5;

        // Peso final combinado
        float weight = spatial_weight * color_weight * structural_weight;

        accum += sample_color * weight;
        total_weight += weight;
    }

    if (total_weight > 1e-6) {
        vec3 denoised = accum / total_weight;
        result = mix(linear_rgb, denoised, strength);
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

// 2. Deblocking Direcional com Proteção Estrutural (Wavelet Emocional)
vec3 emotional_directional_deblock(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps, vec4 golden, vec4 luma) {
    vec3 result = linear_rgb;
    #if ENABLE_DIRECTIONAL_DEBLOCK
    float grid_density = golden.r;      // Densidade de grade do S1
    float edge_strength = maps.r;       // Força de borda do S1
    float aesthetic_score = golden.a;  // Beleza do S1
    float pattern_entropy = golden.g;  // Entropia do S1

    // 🎭 A INTELIGÊNCIA EMOCIONAL:
    // Se é "bonito" e tem textura complexa, reduzimos o deblocking
    // Se é grade óbvia e "feio", aplicamos força total
    float emotional_factor = 1.0 + (grid_density * 0.8) - (aesthetic_score * 0.5) - (pattern_entropy * 0.3);
    emotional_factor = clamp(emotional_factor, 0.2, 1.0);

    if (grid_density > 0.15 && emotional_factor > 0.3) {
        // 🔍 ANÁLISE DIRECIONAL AVANÇADA (Wavelet-like)
        vec3 h_grad = get_gradient_safe(GRX_COLOR_LINEAR, uv, p, vec2(1.0, 0.0), edge_strength);
        vec3 v_grad = get_gradient_safe(GRX_COLOR_LINEAR, uv, p, vec2(0.0, 1.0), edge_strength);

        float h_magnitude = length(h_grad);
        float v_magnitude = length(v_grad);

        // 🧭 DETECÇÃO DE DIREÇÃO DOMINANTE:
        vec3 smoothed = linear_rgb;
        float dir_strength = DEBLOCK_STRENGTH * grid_density * emotional_factor;

        if (h_magnitude > v_magnitude * 1.8) {
            // 📏 Linhas verticais predominantes (blocos horizontais) - suaviza horizontalmente
            smoothed = (
                texture(GRX_COLOR_LINEAR, uv + vec2( p.x, 0.0)).rgb * 0.25 +
                texture(GRX_COLOR_LINEAR, uv - vec2( p.x, 0.0)).rgb * 0.25 +
                texture(GRX_COLOR_LINEAR, uv + vec2(2.0*p.x, 0.0)).rgb * 0.15 +
                texture(GRX_COLOR_LINEAR, uv - vec2(2.0*p.x, 0.0)).rgb * 0.15 +
                linear_rgb * 0.20
            );
            dir_strength *= 1.0;
        }
        else if (v_magnitude > h_magnitude * 1.8) {
            // 📏 Linhas horizontais predominantes (blocos verticais) - suaviza verticalmente
            smoothed = (
                texture(GRX_COLOR_LINEAR, uv + vec2(0.0,  p.y)).rgb * 0.25 +
                texture(GRX_COLOR_LINEAR, uv - vec2(0.0,  p.y)).rgb * 0.25 +
                texture(GRX_COLOR_LINEAR, uv + vec2(0.0, 2.0*p.y)).rgb * 0.15 +
                texture(GRX_COLOR_LINEAR, uv - vec2(0.0, 2.0*p.y)).rgb * 0.15 +
                linear_rgb * 0.20
            );
            dir_strength *= 1.0;
        }
        else {
            // 🔲 Grade isotrópica ou incerta - suavização controlada
            smoothed = (
                texture(GRX_COLOR_LINEAR, uv + vec2( p.x, 0.0)).rgb +
                texture(GRX_COLOR_LINEAR, uv - vec2( p.x, 0.0)).rgb +
                texture(GRX_COLOR_LINEAR, uv + vec2(0.0,  p.y)).rgb +
                texture(GRX_COLOR_LINEAR, uv - vec2(0.0,  p.y)).rgb
            ) * 0.25;
            dir_strength *= 0.7; // Menos força por incerteza
        }

        // 🛡️ PROTEÇÃO ESTRUTURAL:
        // Se há bordas fortes ou textura complexa, reduzimos a força
        float structure_protection = STRUCTURAL_PROTECTION_FACTOR + (edge_strength * 0.3) + (pattern_entropy * 0.2);
        dir_strength *= clamp(2.0 - structure_protection, 0.3, 1.0);

        // 🎨 PROTEÇÃO DE CORES:
        // Em áreas coloridas e bonitas, reduzimos para não lavar detalhes cromáticos
        float color_protection = saturation(linear_rgb) * aesthetic_score;
        dir_strength *= (1.0 - color_protection * 0.4);

        result = mix(linear_rgb, smoothed, dir_strength);
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

// 3. Debanding com Consciência de Gradiente e Emoção
vec3 emotional_gradient_deband(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps, vec4 golden, vec4 luma) {
    vec3 result = linear_rgb;
    #if ENABLE_GRADIENT_DEBAND
    float variance = maps.g;           // Variância do S1
    float flatness = luma.g;           // Lisura do S1 (do GRX_LUMA)
    float aesthetic_score = golden.a;  // Beleza do S1
    float brightness = luma.r;         // Brilho

    // 🎭 DETECÇÃO INTELIGENTE DE BANDING:
    // Banding geralmente ocorre em: áreas lisas + baixa variância + não é "bonito"
    bool is_banding_risk = (variance < FLAT_AREA_DEBAND_THRESHOLD) &&
    (flatness > 0.5) &&
    (aesthetic_score < 0.7);

    if (is_banding_risk) {
        // 📐 ANÁLISE DE GRADIENTE COM PROTEÇÃO DE BORDAS:
        vec3 grad_x = get_gradient_safe(GRX_COLOR_LINEAR, uv, p, vec2(2.0, 0.0), maps.r);
        vec3 grad_y = get_gradient_safe(GRX_COLOR_LINEAR, uv, p, vec2(0.0, 2.0), maps.r);

        float gx = dot(grad_x, vec3(0.333));
        float gy = dot(grad_y, vec3(0.333));
        float grad_magnitude = sqrt(gx*gx + gy*gy);

        // 🚫 PROTEÇÃO: Se o gradiente é muito forte, é borda real, não banding
        if (grad_magnitude < 0.12 && grad_magnitude > 0.005) {
            // 🧭 DIREÇÃO DO GRADIENTE (para dithering direcional):
            vec2 grad_direction = normalize(vec2(gx, gy));

            // 🌊 GERAÇÃO DE RUÍDO DIRECIONAL:
            // Usamos a direção do gradiente para aplicar dithering na direção da luz
            float noise = blueNoise(uv * HOOKED_size * GOLDEN_RATIO) - 0.5;

            // 🎚️ AMPLITUDE ADAPTATIVA:
            float base_amp = DEBAND_STRENGTH * 0.018;
            // Mais forte em áreas lisas e claras (céus)
            float amp = base_amp * (1.0 + flatness * 1.5) * (1.0 + brightness * 0.8);
            // Menos força em áreas com alguma textura
            amp *= (1.0 - variance * 30.0);
            // Proteção emocional - menos força em áreas bonitas
            amp *= (1.0 - aesthetic_score * 0.5);

            // 📐 APLICAÇÃO DIRECIONAL:
            // O ruído é aplicado principalmente na direção perpendicular ao banding
            vec2 noise_direction = vec2(-grad_direction.y, grad_direction.x); // Perpendicular
            float directional_factor = dot(noise_direction, vec2(noise));

            // Aplica o dithering
            result += vec3(directional_factor * amp);

            // ✨ ADIÇÃO DE MICRO-TEXTURA PARA EVITAR "PLASTICIDADE":
            // Mesmo após remover banding, adicionamos um pouco de textura orgânica
            if (flatness > 0.7 && variance < 0.01) {
                float micro_texture = blueNoise(uv * HOOKED_size * GOLDEN_SEQUENCE * 0.5) * 0.003;
                result += vec3(micro_texture) * (1.0 - aesthetic_score * 0.3);
            }
        }
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 2.3.1 🌪️ LIMPEZA CINÉTICA (A ILUSÃO DE MOVIMENTO)
// ===================================================================================
// Transforma ruído caótico em "velocidade" alinhada, enganando o olho humano.
vec3 kinetic_flow_cleaning(vec2 uv, vec2 p, vec3 current_rgb, vec4 maps, vec4 temporal) {

    // 1. DADOS DE FLUXO E CAOS
    vec2 flow = GRX_TEMPORAL_tex(uv).rg; // Vetor de movimento
    float motion_speed = length(flow);
    float chaos = 1.0 - maps.a;          // Confiança baixa = Caos

    // Só ativamos se houver movimento significativo E algum caos (ruído)
    // Se a imagem estiver parada, não tocamos.
    if (motion_speed < 0.002 || chaos < 0.1) return current_rgb;

    // 2. A "INTUIÇÃO" DA ANIMAÇÃO
    // Quanto mais rápido o movimento, mais podemos "esticar" a limpeza.
    float stretch_factor = clamp(motion_speed * 100.0, 1.0, 4.0);

    // 3. AMOSTRAGEM DIRECIONAL (Não circular!)
    // Amostramos pixels APENAS na linha do movimento (passado e futuro)
    vec3 accum = current_rgb;
    float total_weight = 1.0;

    // Amostra 2 passos para trás (rastro) e 1 para frente (previsão)
    for (float i = 1.0; i <= 2.0; i+=1.0) {
        // Direção do fluxo (Passado)
        vec2 offset_back = -flow * i * 0.5;
        vec3 sample_back = texture(GRX_COLOR_LINEAR, clamp(uv + offset_back, 0.0, 1.0)).rgb;

        // Direção do fluxo (Futuro)
        vec2 offset_fwd = flow * i * 0.5;
        vec3 sample_fwd = texture(GRX_COLOR_LINEAR, clamp(uv + offset_fwd, 0.0, 1.0)).rgb;

        // Peso decrescente (mais longe = menos influência)
        float weight = 1.0 / (1.0 + i);

        // PROTEÇÃO DE BORDA (Edge Guard)
        // Se encontrarmos uma borda forte no caminho, paramos de borrar para não criar "fantasmas"
        float edge_sample = texture(GRX_MAPS, clamp(uv + offset_back, 0.0, 1.0)).r;
        weight *= (1.0 - edge_sample);

        accum += (sample_back + sample_fwd) * weight;
        total_weight += weight * 2.0;
    }

    vec3 kinetic_clean = accum / total_weight;

    // 4. MISTURA ESTRATÉGICA
    // Se for caos total (Dragon Ball luta rápida), usamos mais o Kinetic Clean.
    // Se for movimento limpo, usamos menos.
    float mix_strength = smoothstep(0.0, 0.5, chaos) * smoothstep(0.002, 0.02, motion_speed);

    return mix(current_rgb, kinetic_clean, mix_strength);
}

// ===================================================================================
// 2.3.2 🧠 FIREWALL ESPACIAL MESTRE COM CONSCIÊNCIA EMOCIONAL
// ===================================================================================
vec3 master_spatial_firewall_emotional(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps, vec4 golden, vec4 luma) {
    vec3 processed = linear_rgb;

    // 🔄 ORDEM LÓGICA REFINADA:
    // 1. Deblocking primeiro (remove estruturas artificiais grandes)
    // 2. Denoising depois (limpa o ruído remanescente)
    // 3. Debanding por último (trata problemas finos em áreas lisas)

    processed = emotional_directional_deblock(uv, p, processed, maps, golden, luma);
    processed = emotional_structural_denoise(uv, p, processed, maps, golden, luma);
    processed = emotional_gradient_deband(uv, p, processed, maps, golden, luma);

    return processed;
}

// ===================================================================================
// 2.3.3 🚑 MÓDULO LÁZARO APRIMORADO (COM INTELIGÊNCIA EMOCIONAL)
// ===================================================================================
vec3 emotional_emergency_sanitizer(sampler2D prev_tex, vec2 uv, vec2 p, vec4 golden, vec4 luma) {
    vec3 accum = vec3(0.0);
    float total_weight = 0.0;

    // 🎭 ANÁLISE EMOCIONAL PARA DECIDIR O NÍVEL DE SANITIZAÇÃO:
    float aesthetic_score = golden.a;
    float pattern_entropy = golden.g;
    float brightness = luma.r;

    // Se é "bonito" mas caótico, aplicamos sanitização leve para preservar a essência
    // Se é "feio" e caótico, aplicamos sanitização nuclear
    float sanitization_level = 1.0 - (aesthetic_score * 0.7) + (pattern_entropy * 0.5);
    sanitization_level = clamp(sanitization_level, 0.4, 1.0);

    // 📏 RAIO ADAPTATIVO:
    float base_radius = 2.0;
    float emotional_radius = base_radius * sanitization_level;
    int radius = int(emotional_radius);

    // 🔍 AMOSTRAGEM COM PESOS ADAPTATIVOS:
    for (float y = -float(radius); y <= float(radius); y++) {
        for (float x = -float(radius); x <= float(radius); x++) {
            vec2 offset = vec2(x, y) * p * 1.2;
            vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));

            // Peso baseado na distância
            float dist = length(vec2(x, y));
            float spatial_weight = exp(-dist * dist * 0.3);

            // Peso adaptativo baseado na "beleza" da área
            // Se é área bonita, damos mais peso aos pixels próximos para preservar detalhes
            float aesthetic_weight = 0.8 + 0.2 * aesthetic_score;

            float weight = spatial_weight * aesthetic_weight;
            vec3 sample = sRGB_to_linear(texture(prev_tex, sample_uv).rgb);

            accum += sample * weight;
            total_weight += weight;
        }
    }

    return (total_weight > 1e-6) ? accum / total_weight : sRGB_to_linear(texture(prev_tex, uv).rgb);
}

// ===================================================================================
// 2.3.4 🧠 FIREWALL TEMPORAL UNIFICADO COM INTELIGÊNCIA EMOCIONAL
// ===================================================================================
vec3 unified_temporal_firewall_emotional(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps, vec4 golden, vec4 luma_maps, vec4 flow_refined, float flow_confidence) {
    // 1. Limpeza Espacial com Inteligência Emocional
    vec3 spatial_result = master_spatial_firewall_emotional(uv, p, linear_rgb, maps, golden, luma_maps);

    // 2. Reconstrução Temporal Adaptativa
    vec3 temporal_result;
    float stream_confidence = maps.a; // O Alarme do S1
    vec2 motion_vector = flow_refined.rg;
    vec2 prev_uv = clamp(uv - motion_vector, vec2(0.0), vec2(1.0));

    if (stream_confidence > 0.4) {
        #ifdef PREV_tex
        temporal_result = sRGB_to_linear(texture(PREV, prev_uv).rgb);
        #else
        temporal_result = spatial_result;
        #endif
    } else {
        // 🚨 LÁZARO EMOCIONAL ATIVO:
        // Não descartamos o frame anterior, mas o sanitizamos com inteligência emocional
        #ifdef PREV_tex
        temporal_result = emotional_emergency_sanitizer(PREV, prev_uv, p, golden, luma_maps);
        // Boost adaptativo de confiança
        float emotional_boost = 0.6 + golden.a * 0.2; // Áreas bonitas ganham mais confiança
        flow_confidence = mix(flow_confidence, emotional_boost, 0.5);
        #else
        temporal_result = spatial_result;
        #endif
    }

    // 🎚️ FATOR DE MISTURA COM PROTEÇÃO EMOCIONAL:
    float mix_factor = flow_confidence;

    // Proteções padrão
    mix_factor *= (1.0 - smoothstep(0.05, 0.2, maps.g)); // Variância
    mix_factor *= (1.0 - smoothstep(0.3, 0.8, maps.r));  // Borda

    // 🎭 PROTEÇÃO EMOCIONAL:
    // Em áreas bonitas, reduzimos a mistura temporal para preservar detalhes
    mix_factor *= (1.0 - golden.a * 0.3);

    return mix(spatial_result, temporal_result, clamp(mix_factor, 0.0, 1.0));
}

// ===================================================================================
// 2.4 🌀 POLIMENTO ZONAL EMOCIONAL (A MAQUIAGEM INTELIGENTE)
// ===================================================================================
vec3 emotional_zonal_polish(vec2 uv, vec2 p, vec3 linear_rgb, vec4 maps, vec4 golden, vec4 luma_maps) {
    vec3 result = linear_rgb;
    #if ENABLE_MULTI_VECTOR_POLISH
    float luma_val = luma_maps.r;
    float shadow_dirt = luma_maps.g;   // Sujeira na sombra (do S1)
    float chroma_risk = luma_maps.b;   // Risco cromático (do S1)
    float mid_noise = luma_maps.a;     // Ruído em midtones (do S1)
    float aesthetic_score = golden.a;  // Beleza emocional

    // 🌑 ZONA ABISSAL EMOCIONAL (Sombras com Inteligência):
    if (luma_val < 0.25) {
        // 🎭 DECISÃO EMOCIONAL:
        // Se é "bonito" (aesthetic_score > 0.6), preservamos mais detalhe
        // Se é "sujo" (shadow_dirt > 0.3), limpamos agressivamente

        float emotional_desat = CHROMA_NUKE_STRENGTH * chroma_risk * (1.0 - aesthetic_score * 0.4);

        // 1. Dessaturação Emocional (remove cor azul/roxa em sombras)
        if (emotional_desat > 0.1) {
            vec3 gray = vec3(safe_luma(result));
            result = mix(result, gray, emotional_desat);
        }

        // 2. Blur Adaptativo de Densidade:
        float blur_strength = shadow_dirt * 0.8 * (1.0 - aesthetic_score * 0.5);
        if (blur_strength > 0.1) {
            vec3 blur = vec3(0.0);
            // Kernel adaptativo baseado na "beleza"
            float kernel_size = 1.5 + (1.0 - aesthetic_score) * 1.0;
            for (float y = -kernel_size; y <= kernel_size; y++) {
                for (float x = -kernel_size; x <= kernel_size; x++) {
                    vec2 offset = vec2(x, y) * p * 1.5;
                    blur += texture(GRX_COLOR_LINEAR, uv + offset).rgb;
                }
            }
            float count = (2.0 * kernel_size + 1.0) * (2.0 * kernel_size + 1.0);
            result = mix(result, blur / count, blur_strength);
        }
    }

    // ☁️ ZONA DE NEBLINA EMOCIONAL (Midtones Ruidosos):
    if (mid_noise > 0.08 && maps.r < 0.3) {
        // 🎭 SÓ LIMPA SE NÃO FOR "BONITO":
        float emotional_cleanup = mid_noise * (1.0 - aesthetic_score * 0.6);
        if (emotional_cleanup > 0.1) {
            vec3 creamy = vec3(0.0);
            vec2 offsets[4] = vec2[](vec2(1,0), vec2(-1,0), vec2(0,1), vec2(0,-1));
            for(int i=0; i<4; i++) {
                creamy += texture(GRX_COLOR_LINEAR, uv + offsets[i]*p).rgb;
            }
            result = mix(result, creamy*0.25, emotional_cleanup * 1.8);
        }
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 2.5 🔧 RECONSTRUÇÃO LIGHT COM CONSCIÊNCIA ESTRUTURAL
// ===================================================================================
vec3 structural_cnn_reconstruction(vec2 uv, vec2 p, vec3 cleaned_linear, vec4 maps, vec4 golden, vec4 luma) {
    vec3 result = cleaned_linear;
    #if ENABLE_CNN_LIGHT_RECON
    float stream_confidence = maps.a;
    float aesthetic_score = golden.a;
    float edge_strength = maps.r;
    float brightness = luma.r;

    // 🎭 SÓ RECONSTRÓI SE FOR SEGURO E VALER A PENA:
    if (stream_confidence > 0.5 && aesthetic_score > 0.4) {
        // 🔍 ANÁLISE ESTRUTURAL LOCAL:
        vec3 blur = vec3(0.0);
        vec2 offsets[4] = vec2[](vec2(1,0), vec2(-1,0), vec2(0,1), vec2(0,-1));

        for(int i=0; i<4; i++) {
            blur += texture(GRX_COLOR_LINEAR, uv + offsets[i]*p).rgb;
        }
        blur *= 0.25;

        vec3 detail = cleaned_linear - blur;

        // 🎚️ FORÇA ADAPTATIVA:
        float recon_strength = RECONSTRUCTION_STRENGTH;
        recon_strength *= aesthetic_score;           // Mais força em áreas bonitas
        recon_strength *= (1.0 - edge_strength * 0.5); // Menos força em bordas já nítidas
        recon_strength *= (1.0 - brightness * 0.3);  // Menos força em highlights

        // ✨ RECONSTRUÇÃO DE MICRO-CONTRASTE:
        result += detail * recon_strength * 0.8;

        // 🎨 RECONSTRUÇÃO CROMÁTICA SUAVE:
        if (saturation(cleaned_linear) < 0.3 && aesthetic_score > 0.6) {
            vec3 hsv = rgb2hsv(linear_to_sRGB(cleaned_linear));
            hsv.y = min(hsv.y * 1.15, 1.0); // Aumenta saturação suavemente
            hsv.z = hsv.z * 0.98 + 0.02;    // Ajuste de brilho
            result = mix(result, sRGB_to_linear(hsv2rgb(hsv)), recon_strength * 0.3);
        }
    }
    #endif
    return clamp(result, 0.0, 1.0);
}

// ===================================================================================
// 2.6 🎯 SISTEMA DE CONTROLE DE QUALIDADE EMOCIONAL
// ===================================================================================
float emotional_cleanliness_score(vec3 original, vec3 cleaned, vec4 maps, vec4 golden) {
    float diff = length(original - cleaned);

    // 🎭 SCORE EMOCIONAL:
    // Não queremos diferença zero - queremos diferença que faça sentido emocionalmente
    float emotional_score = 1.0;

    // Penaliza se removeu muito de áreas bonitas
    emotional_score -= golden.a * diff * 0.6;

    // Bônus se removeu ruído de áreas feias
    emotional_score += (1.0 - golden.a) * (1.0 - exp(-diff * 5.0)) * 0.4;

    // Proteção de bordas
    emotional_score += maps.r * 0.2;

    // Penalidade por artefatos
    if (detect_processing_artifacts(original, cleaned, 0.2)) {
        emotional_score *= 0.8;
    }

    return clamp(emotional_score, 0.0, 1.0);
}

bool should_apply_emotional_processing(vec4 maps, vec4 golden, float cost) {
    float stream_confidence = maps.a;
    float aesthetic_score = golden.a;

    // 🎭 DECISÃO EMOCIONAL:
    // Processa se: confiança é alta OU é área feia (vale a pena limpar)
    float emotional_decision = stream_confidence + (1.0 - aesthetic_score) * 0.7;

    return emotional_decision > (0.4 + cost * 0.1);
}

// ===================================================================================
// 2.6.1 🧠 SOLUCIONADOR DE CAOS (SIMULAÇÃO DE PESOS NEURAIS PARA ANIME)
// ===================================================================================
float get_luma_weight(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 chaos_neural_solver(vec2 uv, vec2 p, vec3 current, vec4 maps, vec4 temporal) {
    float chaos_level = 1.0 - maps.a;    // 1.0 = Caos Total
    float is_line = maps.r;              // É uma linha?

    if (chaos_level < 0.2) return current; // Se está calmo, não toca

    float W_LINE = 1.5;   // Escurecer linhas
    float W_NOISE = 2.0;  // Achatar fundo
    float W_FLASH = 0.8;  // Recuperar flash

    vec3 result = current;

    // A. DESTRUIÇÃO DE TRAÇO (Recuperação de Linha)
    if (is_line > 0.2) {
        vec3 n = texture(GRX_COLOR_LINEAR, uv + vec2(0, -1)*p).rgb;
        vec3 s = texture(GRX_COLOR_LINEAR, uv + vec2(0,  1)*p).rgb;
        vec3 w = texture(GRX_COLOR_LINEAR, uv + vec2(-1, 0)*p).rgb;
        vec3 e = texture(GRX_COLOR_LINEAR, uv + vec2( 1, 0)*p).rgb;

        vec3 darkest = min(current, min(min(n, s), min(w, e)));
        float push = (get_luma_weight(current) - get_luma_weight(darkest)) * W_LINE * chaos_level;
        result = mix(current, darkest, clamp(push, 0.0, 0.8));
    }
    // B. EXPLOSÃO DE COMPRESSÃO (Limpeza de Fundo)
    else {
        vec3 avg = textureLod(GRX_COLOR_LINEAR, uv, 2.0).rgb;
        if (length(current - avg) > 0.1) {
            result = mix(current, avg, 0.6 * chaos_level * W_NOISE);
        }
    }

    // C. FLASH BRANCO
    if (temporal.a > 0.5) result *= (1.0 - temporal.a * 0.2 * W_FLASH);

    return result;
}


// ===================================================================================
// 2.6.2 🧠 NEURAL RESNET EMOCIONAL (SISR HÍBRIDO PARA LIVE ACTION)
// ===================================================================================
// Uma Mini-CNN simulada que entende a diferença entre ruído e textura orgânica.
// Baseada em Wavelets Direcionais e Atenção Emocional.
// ===================================================================================

// Função de Ativação PReLU Adaptativa
vec3 activation_prelu_emotional(vec3 x, float alpha, float emotional_confidence) {
    // Menos supressão em áreas emocionalmente importantes (preserva textura de pele)
    float adaptive_alpha = alpha * (1.0 - emotional_confidence * 0.7);
    return max(x, 0.0) + min(x, 0.0) * adaptive_alpha;
}

vec3 emotional_neural_resnet(vec2 uv, vec2 p, vec3 input_linear, vec4 maps, vec4 temporal, vec4 golden, vec4 luma) {
    // 1. GATILHO DE CONTEÚDO (Live Action vs Anime)
    float entropy = golden.g;
    float skin_risk = luma.b; // Risco cromático em sombra costuma ser pele em vídeos ruins
    float aesthetic = golden.a;

    // Live Action = Alta Entropia OU (Pele Detectada + Alta Estética)
    float is_live_action = smoothstep(0.4, 0.7, entropy) + (skin_risk * aesthetic);
    float chaos = 1.0 - maps.a;

    // Só ativa se for Live Action (>0.4) E tiver algum caos (>0.2)
    if (is_live_action < 0.4 || chaos < 0.2) return input_linear;

    // 2. EXTRAÇÃO DE CARACTERÍSTICAS DIRECIONAIS (Wavelets Otimizados)
    // Analisa contrastes em 4 direções para achar estrutura real
    vec3 center = input_linear;
    vec3 horiz = texture(GRX_COLOR_LINEAR, uv + vec2(2,0)*p).rgb - texture(GRX_COLOR_LINEAR, uv - vec2(2,0)*p).rgb;
    vec3 vert  = texture(GRX_COLOR_LINEAR, uv + vec2(0,2)*p).rgb - texture(GRX_COLOR_LINEAR, uv - vec2(0,2)*p).rgb;
    vec3 diag1 = texture(GRX_COLOR_LINEAR, uv + vec2(1,1)*p).rgb - texture(GRX_COLOR_LINEAR, uv - vec2(1,1)*p).rgb;
    vec3 diag2 = texture(GRX_COLOR_LINEAR, uv + vec2(1,-1)*p).rgb - texture(GRX_COLOR_LINEAR, uv - vec2(1,-1)*p).rgb;

    // Fusão das características (Max Pooling Suave)
    vec3 features = (horiz*horiz + vert*vert + diag1*diag1 + diag2*diag2) * 0.25;
    features = sqrt(features); // Magnitude do detalhe

    // 3. ATENÇÃO EMOCIONAL (O "Coração")
    // Onde devemos preservar o detalhe?
    float face_importance = aesthetic * maps.r; // Bordas em áreas bonitas (rostos)
    float skin_importance = skin_risk * aesthetic; // Tons de pele

    float emotional_confidence = clamp(face_importance + skin_importance, 0.0, 1.0);

    // Filtramos o ruído: Detalhes em áreas escuras e sem importância são suprimidos
    float noise_suppression = 1.0;
    if (luma.r < 0.2) noise_suppression = 0.3 + 0.7 * emotional_confidence;

    features *= noise_suppression;
    features = activation_prelu_emotional(features, 0.1, emotional_confidence);

    // 4. RECONSTRUÇÃO RESIDUAL COM PROTEÇÃO DE ESQUELETO
    // Base suave (fundo limpo)
    vec3 base_smooth = (
        texture(GRX_COLOR_LINEAR, uv + vec2(0,1)*p).rgb +
        texture(GRX_COLOR_LINEAR, uv + vec2(0,-1)*p).rgb +
        texture(GRX_COLOR_LINEAR, uv + vec2(1,0)*p).rgb +
        texture(GRX_COLOR_LINEAR, uv + vec2(-1,0)*p).rgb
    ) * 0.25;

    // Reinjetamos o detalhe validado (feature) na base suave
    // A força da injeção depende do caos: mais caos = mais reconstrução necessária
    vec3 reconstructed = base_smooth + features * (1.0 + chaos * 0.5);

    // Proteção de Esqueleto: Se havia uma borda forte original, traga ela de volta
    if (maps.r > 0.3) {
        reconstructed = mix(reconstructed, input_linear, maps.r * 0.5);
    }

    // 5. MISTURA FINAL
    // Misturamos o resultado reconstruído com o original baseado na certeza de que é Live Action
    float blend = smoothstep(0.2, 0.6, chaos) * clamp(is_live_action, 0.0, 1.0);

    return mix(input_linear, reconstructed, blend);
}

// ===================================================================================
// 2.7 🧠 HOOK PRINCIPAL (O CIRURGIÃO DE FLUXO EMOCIONAL)
// ===================================================================================
//!HOOK MAIN
//!DESC S2 - Firewall Estrutural (Chaos & Anime Aware)
//!BIND HOOKED
//!BIND GRX_MAPS
//!BIND GRX_TEMPORAL
//!BIND GRX_GOLDEN
//!BIND GRX_LUMA
//!BIND GRX_COLOR_LINEAR
//!BIND GRX_FLOW_REFINED
//!BIND PREV
//!SAVE STAGE2_OUTPUT
//!COMPONENTS 4
vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 p = HOOKED_pt;

    // 1. VALIDAÇÃO DE ENTRADA (Alfândega S1)
    vec4 maps = validate_s1_data(GRX_MAPS_tex(uv));

    // Safety Bypass: Se S1 falhou, retorna original e avisa (alpha=0)
    if (maps.a == 0.0) return vec4(linear_to_sRGB(GRX_COLOR_LINEAR_tex(uv).rgb), 0.0);

    vec4 temporal = GRX_TEMPORAL_tex(uv);
    vec4 golden = GRX_GOLDEN_tex(uv);
    vec4 luma = GRX_LUMA_tex(uv);
    vec4 flow_refined = GRX_FLOW_REFINED_tex(uv);
    vec3 input_linear = GRX_COLOR_LINEAR_tex(uv).rgb;

    // Variável de trabalho unificada
    vec3 current = input_linear;

    // 2. DETECTOR DE ANIME
    // Anime = Baixa Entropia + Baixa Variância
    float is_anime_score = (1.0 - smoothstep(0.2, 0.6, golden.g)) * (1.0 - smoothstep(0.01, 0.05, maps.g));

    // 3. LIMPEZA CINÉTICA (Primeiro Passo)
    if (ENABLE_MULTI_VECTOR_POLISH) {
        current = kinetic_flow_cleaning(uv, p, current, maps, temporal);
    }

    // 4. SOLUCIONADORES DE CAOS (Dual-Core: Anime vs ResNet Emocional)

    // ROTA A: ANIME (Traços e Cores Chapadas)
    // Detectamos anime se a entropia for baixa E a variância for baixa (áreas lisas)
    if (is_anime_score > 0.6) {
        #if ENABLE_ANIME_CHAOS_SOLVER
        vec3 solved = chaos_neural_solver(uv, p, current, maps, temporal);
        // Aplica com força proporcional à certeza de que é anime
        current = mix(current, solved, smoothstep(0.6, 0.9, is_anime_score));
        #endif
    }
    // ROTA B: LIVE ACTION (ResNet Emocional)
    else {
        // Se não for anime, ativamos a ResNet que entende pele e textura
        // Ela só age se houver caos real e conteúdo orgânico
        vec3 restored = emotional_neural_resnet(uv, p, current, maps, temporal, golden, luma);

        // Mistura proporcional à "não-anime-za" (certeza de ser real)
        current = mix(current, restored, (1.0 - is_anime_score));
    }

    // 5. DECISÃO EMOCIONAL DE PROCESSAMENTO
    // Vale a pena rodar o denoise pesado?
    if (should_apply_emotional_processing(maps, golden, 0.0)) {

        // A. Limpeza Espacial + Temporal (Firewall Unificado)
        vec3 cleaned = unified_temporal_firewall_emotional(uv, p, current, maps, golden, luma, flow_refined, temporal.b);

        // Mistura de Emergência
        float emergency_mix = 1.0 - smoothstep(0.0, 0.4, maps.a);
        float emotional_strength = mix(DENOISE_STRENGTH, 1.0, emergency_mix);
        emotional_strength *= (1.0 - golden.a * 0.4); // Protege beleza

        current = mix(current, cleaned, emotional_strength);
    }

    // 6. POLIMENTO ZONAL
    if (ENABLE_MULTI_VECTOR_POLISH && should_apply_emotional_processing(maps, golden, 0.3)) {
        current = emotional_zonal_polish(uv, p, current, maps, golden, luma);
    }

    // 7. RECONSTRUÇÃO LEVE
    if (should_apply_emotional_processing(maps, golden, 0.5)) {
        current = structural_cnn_reconstruction(uv, p, current, maps, golden, luma);
    }

    // 8. SEGURANÇA FINAL INTELIGENTE (Safety Net)
    // Verifica se "current" não se desviou demais de "input_linear" de forma errada
    if (detect_processing_artifacts(input_linear, current, maps, golden, 0.15)) {
        // Soft Fallback: Recupera 70% do original se detectar erro grave
        current = mix(input_linear, current, 0.3);
    }

    // Cálculo final do score de limpeza
    float score = emotional_cleanliness_score(input_linear, current, maps, golden);

    // Saída (sRGB para compatibilidade com S3 padrão)
    return vec4(linear_to_sRGB(current), score);
}

// ===================================================================================
// 2.8 🌀 POLIMENTO DE FLUXO COM CONSCIÊNCIA EMOCIONAL (MANTIDO OTIMIZADO)
// ===================================================================================
// Mantemos a lógica excelente do polimento de fluxo, mas adicionamos proteção emocional
vec2 emotional_refine_optical_flow(vec2 uv, vec2 p, vec4 maps, vec4 temporal, vec4 golden) {
    float confidence = maps.a;
    if (confidence < 0.05) return vec2(0.0);

    vec2 center_flow = temporal.rg;

    // 🎭 ANÁLISE EMOCIONAL DO FLUXO:
    // Em áreas bonitas, somos mais conservadores com o fluxo
    // Em áreas feias/chaóticas, somos mais agressivos na correção
    float emotional_conservatism = 0.7 + golden.a * 0.3;

    #ifdef PREV_tex
    vec2 test_uv = uv - center_flow;
    if(test_uv.x > 0.0 && test_uv.x < 1.0 && test_uv.y > 0.0 && test_uv.y < 1.0) {
        vec3 curr_col = texture(HOOKED, uv).rgb;
        vec3 prev_col = texture(PREV, test_uv).rgb;
        float reprojection_error = length(curr_col - prev_col);

        // 🎚️ ERRO ADAPTATIVO:
        float max_error = 0.15 + (1.0 - golden.a) * 0.1; // Áreas feias toleram mais erro
        float validity = 1.0 - smoothstep(0.1 * emotional_conservatism, max_error, reprojection_error);
        confidence *= validity;
    }
    #endif

    if (confidence < 0.1) return vec2(0.0);

    // Restante da lógica mantida (excelente), mas com pesos adaptativos
    vec2 refined_flow = vec2(0.0);
    float total_weight = 0.0;
    int radius = (confidence > 0.6) ? 2 : 1;

    for (int j = -radius; j <= radius; j++) {
        for (int i = -radius; i <= radius; i++) {
            vec2 offset = vec2(i, j) * p;
            vec2 neighbor_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));
            vec2 neighbor_flow = GRX_TEMPORAL_tex(neighbor_uv).rg;
            vec4 neighbor_maps = GRX_MAPS_tex(neighbor_uv);

            // Pesos com consciência emocional
            float spatial = exp(-(float(i*i + j*j)) * 0.5);
            float variance_w = 1.0 - smoothstep(0.01, 0.05, neighbor_maps.g);
            float coherence = dot(normalize(center_flow + 1e-6), normalize(neighbor_flow + 1e-6));
            float coherence_w = smoothstep(0.0, 0.5 * emotional_conservatism, coherence);

            float weight = spatial * variance_w * coherence_w;
            refined_flow += neighbor_flow * weight;
            total_weight += weight;
        }
    }

    if (total_weight < 1e-6) return center_flow * max(0.0, confidence - 0.2);

    refined_flow /= total_weight;
    refined_flow *= (1.0 - (1.0 - smoothstep(0.0, 0.01, maps.g)));
    return refined_flow;
}

//!HOOK GRX_FLOW_REFINED_HOOK
//!DESC S2.5 - Polidor de Fluxo com Inteligência Emocional
//!BIND GRX_TEMPORAL
//!BIND GRX_MAPS
//!BIND GRX_GOLDEN
//!BIND HOOKED
//!SAVE GRX_FLOW_REFINED
//!COMPONENTS 2
vec4 hook_flow_refine() {
    vec2 uv = HOOKED_pos;
    vec2 p = HOOKED_pt;
    vec4 maps = GRX_MAPS_tex(uv);
    vec4 temporal = GRX_TEMPORAL_tex(uv);
    vec4 golden = GRX_GOLDEN_tex(uv);
    vec2 polished_flow = emotional_refine_optical_flow(uv, p, maps, temporal, golden);
    return vec4(polished_flow, 0.0, 1.0);
}
