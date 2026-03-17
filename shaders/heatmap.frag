#version 460 core

uniform sampler2D u_densityTex;
uniform float     u_minValue;
uniform float     u_maxValue;
uniform float     u_alpha;

in  vec2 v_uv;
out vec4 fragColor;

void main()
{
    float raw = texture(u_densityTex, v_uv).r;
    float d = (raw - u_minValue) / max(u_maxValue - u_minValue, 1e-5);
    vec3  c = mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), clamp(d, 0.0, 1.0));
    fragColor = vec4(c, u_alpha);
}
