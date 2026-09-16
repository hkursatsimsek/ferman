// Single overhead lamp: light falls off from the lit center toward the sand
// edge (design brief §3.1 — "ışık tek yönlü ve yukarıdan"). Mirrors
// DesignSystem/Shaders/SandTableLight.metal; SpriteKit shaders compile as
// GLSL ES, not Metal, so the two can't share source.
void main() {
    vec2 center = vec2(0.5, 0.66);
    vec2 radius = vec2(0.7, 0.5);
    vec2 delta = (v_tex_coord - center) / radius;
    float t = clamp(length(delta), 0.0, 1.0);
    gl_FragColor = mix(u_lit_color, u_shadow_color, t);
}
