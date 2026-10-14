#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;

out vec4 fragColor;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;   // 0..1（y=0 顶）
    float up = 1.0 - uv.y;                      // 0 底 → 1 顶
    float x  = (uv.x - 0.5) * 2.0;              // -1..1

    // 火焰半宽：底部宽、向上收尖
    float halfW = mix(0.55, 0.05, up);

    // 抖动 + 越高越晃
    float flick = (noise(vec2(uv.x * 4.0, up * 3.0 - uTime * 2.5)) - 0.5);
    float cx = flick * 0.28 * up;

    float d = abs(x - cx) / halfW;              // 0 中心 → 1 边缘
    float a = smoothstep(1.0, 0.0, d);          // 内 1 外 0
    a *= smoothstep(1.06, 0.82, up);            // 顶收尖（不是硬切）
    a *= 0.75 + 0.5 * noise(vec2(uv.x * 8.0, up * 10.0 - uTime * 6.0));

    // 颜色：底 白黄 → 中橙 → 顶红
    vec3 hot  = vec3(1.0, 0.95, 0.72);
    vec3 mid  = vec3(1.0, 0.55, 0.10);
    vec3 tip  = vec3(1.0, 0.22, 0.05);
    vec3 col = mix(hot, mid, clamp(up * 1.5, 0.0, 1.0));
    col = mix(col, tip, clamp((up - 0.5) * 2.0, 0.0, 1.0));

    fragColor = vec4(mix(vec3(0.075, 0.075, 0.075), col, clamp(a, 0.0, 1.0)), 1.0);
}
