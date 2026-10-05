import SpriteKit

/// The holographic sheen. A rainbow band sweeps diagonally across each piece of
/// money on a slow loop, and a second softer sheen tracks how the phone is
/// tilted — so the foil catches the light as the handset moves.
enum HoloShine {

    // SpriteKit transpiles this to Metal, rewriting `gl_FragColor = x` into a
    // return — so there is a single assignment and no early exit.
    private static let source = """
    void main() {
        vec4 tex = texture2D(u_texture, v_tex_coord);

        // Diagonal coordinate across the face of the money.
        float p = v_tex_coord.x * 1.35 + (1.0 - v_tex_coord.y) * 0.75;

        // Slow automatic sweep. u_seed staggers the pieces so they do not flash together.
        float cycle = fract(u_time * 0.14 + u_seed);
        float band  = smoothstep(0.0, 0.26, 0.26 - abs(p - (cycle * 2.9 - 0.75)));
        band = band * band;

        // Tilt-reactive sheen.
        float sheen = smoothstep(0.0, 0.62, 0.62 - abs(p - (u_tilt * 0.8 + 0.9)));

        // Rainbow ramp.
        float h = fract(p * 0.55 + u_tilt * 0.2 + u_time * 0.04 + u_seed);
        vec3 rainbow = 0.5 + 0.5 * cos(6.2831853 * (h + vec3(0.00, 0.33, 0.67)));

        float gain = band * 0.85 + sheen * 0.22;

        // Textures arrive premultiplied, so the sheen is scaled by alpha and
        // clamped to it — transparent corners stay transparent.
        vec3 lit = tex.rgb + rainbow * gain * tex.a;

        gl_FragColor = vec4(min(lit, vec3(tex.a)), tex.a);
    }
    """

    /// Four shader instances, handed out round-robin, so the sweep is staggered
    /// without compiling a program per piece of money.
    private static let variants: [SKShader] = (0..<4).map { index in
        let shader = SKShader(source: source)
        shader.uniforms = [
            SKUniform(name: "u_seed", float: Float(index) * 0.25),
            SKUniform(name: "u_tilt", float: 0)
        ]
        return shader
    }

    static func shader(variant index: Int) -> SKShader {
        variants[abs(index) % variants.count]
    }

    /// Feed the device roll in, roughly -1...1.
    static func updateTilt(_ tilt: Float) {
        let clamped = max(-1.4, min(1.4, tilt))
        for shader in variants {
            shader.uniformNamed("u_tilt")?.floatValue = clamped
        }
    }
}
