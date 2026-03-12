#version 460 core

layout(location = 0) in vec4 aPositionColor;  // xy = position, z = color intensity, w = alpha

out float vColorIntensity;
out float vAlpha;

void main() {
    gl_Position = vec4(aPositionColor.xy, 0.0, 1.0);
    gl_PointSize = 3.0;

    vColorIntensity = aPositionColor.z;
    vAlpha = aPositionColor.w;
}
