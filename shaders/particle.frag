#version 460 core

in float vColorIntensity;
in float vAlpha;

out vec4 fragColor;

void main() {
    // Circular point with soft edges
    vec2 coord = gl_PointCoord - vec2(0.5);
    float dist = length(coord);
    if (dist > 0.5) discard;

    float alpha = smoothstep(0.5, 0.3, dist) * vAlpha;

    // Color gradient: blue to cyan based on intensity
    vec3 color = mix(
        vec3(0.2, 0.4, 1.0),   // Blue
        vec3(0.2, 1.0, 1.0),   // Cyan
        clamp(vColorIntensity, 0.0, 1.0)
    );

    fragColor = vec4(color, alpha);
}
