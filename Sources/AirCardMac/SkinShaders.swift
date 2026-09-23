import CoreImage
import Foundation
import Metal

enum SkinGeneratorKind: Int {
    case linear = 1, radial, conic, mesh, holographic, brushedMetal, sheen, grain, pattern
}

final class SkinGeneratorKernel: CIImageProcessorKernel {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pipelines: [ObjectIdentifier: MTLComputePipelineState] = [:]

    override class var outputFormat: CIFormat { .RGBAh }
    override class var synchronizeInputs: Bool { false }

    override class func process(
        with inputs: [CIImageProcessorInput]?,
        arguments: [String: Any]?,
        output: CIImageProcessorOutput
    ) throws {
        guard let commandBuffer = output.metalCommandBuffer,
              let texture = output.metalTexture,
              var params = arguments?["params"] as? [Float],
              var colors = arguments?["colors"] as? [Float] else {
            throw AirCardError.processFailed(AirCardL10n.text("El generador de efectos no recibió un contexto Metal."))
        }
        let pipeline = try pipeline(for: commandBuffer.device)
        params[3] = Float(output.region.minX)
        params[4] = Float(output.region.minY)
        params[5] = Float(output.region.height)
        if params.count < 64 { params += Array(repeating: 0, count: 64 - params.count) }
        if colors.count < 64 { colors += Array(repeating: 0, count: 64 - colors.count) }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw AirCardError.processFailed(AirCardL10n.text("No pude crear el encoder Metal."))
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(params, length: params.count * MemoryLayout<Float>.stride, index: 0)
        encoder.setBytes(colors, length: colors.count * MemoryLayout<Float>.stride, index: 1)
        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        let groups = MTLSize(
            width: (texture.width + width - 1) / width,
            height: (texture.height + height - 1) / height,
            depth: 1
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
        encoder.endEncoding()
    }

    private static func pipeline(for device: MTLDevice) throws -> MTLComputePipelineState {
        lock.lock()
        defer { lock.unlock() }
        let key = ObjectIdentifier(device)
        if let cached = pipelines[key] { return cached }
        let library = try device.makeLibrary(source: SkinShaderSource.metal, options: nil)
        guard let function = library.makeFunction(name: "skin_generate") else {
            throw AirCardError.processFailed(AirCardL10n.text("No encontré el shader skin_generate."))
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        pipelines[key] = pipeline
        return pipeline
    }

    static func image(
        kind: SkinGeneratorKind,
        canvas: CGSize,
        params: [Float],
        colors: [Float]
    ) throws -> CIImage {
        let header: [Float] = [Float(kind.rawValue), Float(canvas.width), Float(canvas.height), 0, 0, 0, 0, 0]
        return try apply(
            withExtent: CGRect(origin: .zero, size: canvas),
            inputs: nil,
            arguments: ["params": header + params, "colors": colors]
        )
    }
}

enum SkinShaderSource {
    static let metal = #"""
#include <metal_stdlib>
using namespace metal;

constant float TAU = 6.28318530718;

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * vnoise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        amplitude *= 0.5;
    }
    return value;
}

float2 rotate2(float2 p, float degrees) {
    float r = degrees * TAU / 360.0;
    float c = cos(r);
    float s = sin(r);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float4 stopsAt(constant float *c, int count, float t) {
    t = clamp(t, 0.0, 1.0);
    if (count <= 0) return float4(0);
    float4 previous = float4(c[0], c[1], c[2], c[3]);
    float previousLocation = c[4];
    if (t <= previousLocation) return previous;
    for (int i = 1; i < count && i < 12; i++) {
        float4 current = float4(c[i * 5], c[i * 5 + 1], c[i * 5 + 2], c[i * 5 + 3]);
        float location = c[i * 5 + 4];
        if (t <= location) {
            float span = max(location - previousLocation, 1e-4);
            return mix(previous, current, (t - previousLocation) / span);
        }
        previous = current;
        previousLocation = location;
    }
    return previous;
}

float3 toLinear(float3 c) {
    return pow(max(c, 0.0), 2.2);
}

float4 linearGradient(constant float *p, constant float *c, float2 q, float aspect) {
    float2 dir = rotate2(float2(1, 0), p[8]);
    float extent = abs(dir.x) * 0.5 * aspect + abs(dir.y) * 0.5;
    float t = dot(q, dir) / max(extent, 1e-4) * 0.5 + 0.5;
    return stopsAt(c, int(p[9]), t);
}

float4 radialGradient(constant float *p, constant float *c, float2 uv, float aspect) {
    float2 d = (uv - float2(p[8], p[9])) * float2(aspect, 1.0);
    float t = length(d) / max(p[10] * aspect, 1e-4);
    return stopsAt(c, int(p[11]), t);
}

float4 conicGradient(constant float *p, constant float *c, float2 uv, float aspect) {
    float2 d = (uv - float2(p[8], p[9])) * float2(aspect, 1.0);
    float a = atan2(d.y, d.x) / TAU + 0.5 + p[10] / 360.0;
    return stopsAt(c, int(p[11]), fract(a));
}

float4 meshGradient(constant float *p, constant float *c, float2 uv) {
    float warp = p[8];
    float seed = p[9];
    float2 w = uv + (float2(fbm(uv * 2.2 + seed), fbm(uv * 2.2 + seed + 11.7)) - 0.5) * warp;
    w = clamp(w, 0.0, 1.0) * 2.0;
    int2 cell = int2(min(floor(w), float2(1.0)));
    float2 f = w - float2(cell);
    f = f * f * (3.0 - 2.0 * f);
    int i00 = (cell.y * 3 + cell.x) * 4;
    int i10 = (cell.y * 3 + cell.x + 1) * 4;
    int i01 = ((cell.y + 1) * 3 + cell.x) * 4;
    int i11 = ((cell.y + 1) * 3 + cell.x + 1) * 4;
    float4 a = float4(c[i00], c[i00 + 1], c[i00 + 2], c[i00 + 3]);
    float4 b = float4(c[i10], c[i10 + 1], c[i10 + 2], c[i10 + 3]);
    float4 d = float4(c[i01], c[i01 + 1], c[i01 + 2], c[i01 + 3]);
    float4 e = float4(c[i11], c[i11 + 1], c[i11 + 2], c[i11 + 3]);
    return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

float4 holographic(constant float *p, float2 q, float2 uv, float2 pos) {
    float scale = p[8];
    float angle = p[9];
    float turbulence = p[10];
    float sparkle = p[11];
    float seed = p[12];
    float tilt = p[21];
    float2 dir = rotate2(float2(1, 0), angle);
    float t = dot(q, dir) * scale + fbm(uv * 3.0 + seed) * turbulence + (tilt - 0.5) * 1.6;
    float3 rgb = float3(0.58, 0.56, 0.62) + float3(0.42, 0.40, 0.38) * cos(TAU * (t + float3(0.0, 0.16, 0.34)));
    float spacing = 22.0;
    float2 cell = floor(pos / spacing);
    float h = hash21(cell + seed);
    if (h > 1.0 - sparkle * 0.25) {
        float2 jitter = float2(hash21(cell + seed + 1.7), hash21(cell + seed + 4.3));
        float2 d = pos - (cell + 0.15 + jitter * 0.7) * spacing;
        float twinkle = pow(0.5 + 0.5 * sin((h * 37.0 + tilt * 6.0) * TAU), 3.0);
        float size = 1.2 + 2.2 * hash21(cell + seed + 9.1);
        float core = exp(-dot(d, d) / (size * size));
        float cross = exp(-abs(d.x) / 0.9) * exp(-abs(d.y) / (size * 4.0)) + exp(-abs(d.y) / 0.9) * exp(-abs(d.x) / (size * 4.0));
        rgb = mix(rgb, float3(1.0), clamp((core + cross * 0.6) * twinkle, 0.0, 1.0));
    }
    return float4(rgb, 1.0);
}

float4 brushedMetal(constant float *p, constant float *c, float2 q, float2 pos) {
    float4 tint = float4(c[0], c[1], c[2], c[3]);
    float grain = p[9];
    float sheen = p[10];
    float tilt = p[21];
    float2 r = rotate2(q, p[8]);
    float2 rp = rotate2(pos, p[8]);
    float streak = vnoise(float2(rp.x * 0.004, rp.y * 1.1)) * 0.6 + vnoise(float2(rp.x * 0.02, rp.y * 3.0)) * 0.4;
    float3 rgb = tint.rgb * (0.82 + (streak - 0.5) * grain * 0.6);
    float bandCenter = (tilt - 0.5) * 1.4;
    float band = exp(-pow((r.x - bandCenter) / 0.35, 2.0));
    float band2 = exp(-pow((r.x - bandCenter + 0.9) / 0.2, 2.0)) * 0.5;
    rgb += (band + band2) * sheen * 0.55;
    return float4(clamp(rgb, 0.0, 1.0), tint.a);
}

float4 sheenLight(constant float *p, constant float *c, float2 q) {
    float4 color = float4(c[0], c[1], c[2], c[3]);
    float2 dir = rotate2(float2(1, 0), p[8]);
    float center = (p[9] - 0.5) * 2.0 + (p[21] - 0.5) * 1.2;
    float width = max(p[10], 0.01);
    float d = dot(q, dir) - center;
    float a = exp(-(d * d) / (width * width));
    return float4(color.rgb, color.a * a);
}

float4 grain(constant float *p, float2 pos) {
    float size = max(p[8], 0.5);
    float2 cell = floor(pos / size);
    float seed = p[10];
    float n = hash21(cell + seed);
    if (p[9] > 0.5) return float4(float3(n), 1.0);
    return float4(n, hash21(cell + seed + 3.1), hash21(cell + seed + 7.7), 1.0);
}

float4 pattern(constant float *p, constant float *c, float2 uv, float2 pos, float aspect) {
    int style = int(p[8]);
    float spacing = max(p[9], 2.0);
    float thickness = clamp(p[10], 0.01, 0.95);
    float2 r = rotate2(pos, p[11]);
    float mask = 0.0;
    if (style == 0) {
        float f = fract(r.y / spacing);
        mask = 1.0 - smoothstep(thickness * 0.5, thickness * 0.5 + 0.04, abs(f - 0.5));
    } else if (style == 1) {
        float2 f = fract(r / spacing) - 0.5;
        mask = 1.0 - smoothstep(thickness * 0.5, thickness * 0.5 + 0.05, length(f));
    } else if (style == 2) {
        float2 f = abs(fract(r / spacing) - 0.5);
        float edge = thickness * 0.25;
        mask = 1.0 - smoothstep(edge, edge + 0.03, min(f.x, f.y));
    } else if (style == 3) {
        float2 cell = floor(r / spacing);
        float2 f = fract(r / spacing);
        bool flip = fmod(abs(cell.x + floor(cell.y * 0.5) * 2.0 + cell.y), 2.0) < 1.0;
        float across = flip ? f.y : f.x;
        float along = flip ? f.x : f.y;
        float tube = sin(across * 3.14159);
        float fiber = 0.85 + 0.15 * sin(along * 3.14159 * 18.0 + across * 5.0);
        float shade = pow(tube, 0.7) * fiber;
        float4 base = float4(c[0], c[1], c[2], c[3]);
        float3 rgb = base.rgb * mix(0.25, 1.0 + thickness, shade);
        return float4(rgb, base.a);
    } else if (style == 4) {
        float2 d = (uv - 0.5) * float2(aspect, 1.0);
        float rad = length(d) * 1000.0 / spacing;
        float ang = atan2(d.y, d.x);
        float acc = 0.0;
        for (int k = 0; k < 3; k++) {
            float petals = 7.0 + float(k) * 5.0;
            float v = rad + sin(ang * petals + float(k) * 1.3) * (2.0 + float(k));
            float line = abs(fract(v) - 0.5);
            acc = max(acc, 1.0 - smoothstep(thickness * 0.2, thickness * 0.2 + 0.05, line));
        }
        mask = acc;
    } else {
        float v = r.y / spacing + sin(r.x / spacing * 0.6) * 0.8;
        float line = abs(fract(v) - 0.5);
        mask = 1.0 - smoothstep(thickness * 0.4, thickness * 0.4 + 0.05, line);
    }
    float4 color = float4(c[0], c[1], c[2], c[3]);
    return float4(color.rgb, color.a * clamp(mask, 0.0, 1.0));
}

kernel void skin_generate(texture2d<half, access::write> output [[texture(0)]],
                          constant float *p [[buffer(0)]],
                          constant float *c [[buffer(1)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    int kind = int(p[0]);
    float2 canvas = float2(p[1], p[2]);
    float2 ciPos = float2(p[3] + float(gid.x) + 0.5, p[4] + p[5] - float(gid.y) - 0.5);
    float2 uv = float2(ciPos.x / canvas.x, 1.0 - ciPos.y / canvas.y);
    float2 pos = float2(ciPos.x, canvas.y - ciPos.y) * (1536.0 / canvas.x);
    float aspect = canvas.x / canvas.y;
    float2 q = float2((uv.x - 0.5) * aspect, uv.y - 0.5);

    float4 color = float4(0);
    if (kind == 1) color = linearGradient(p, c, q, aspect);
    else if (kind == 2) color = radialGradient(p, c, uv, aspect);
    else if (kind == 3) color = conicGradient(p, c, uv, aspect);
    else if (kind == 4) color = meshGradient(p, c, uv);
    else if (kind == 5) color = holographic(p, q, uv, pos);
    else if (kind == 6) color = brushedMetal(p, c, q, pos);
    else if (kind == 7) color = sheenLight(p, c, q);
    else if (kind == 8) color = grain(p, pos);
    else if (kind == 9) color = pattern(p, c, uv, pos, aspect);

    float alpha = clamp(color.a, 0.0, 1.0);
    output.write(half4(half3(toLinear(color.rgb) * alpha), half(alpha)), gid);
}
"""#
}
