// Converted from GLSL to HLSL
// Original had Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License

// Push constants structure
[[vk::push_constant]]
struct PushConstantsBlock
{
    float4 data1;
    float4 data2;
    float4 data3;
    float4 data4;
} PushConstants;

// RWTexture for the image
RWTexture2D<float4> image : register(u0);

// Return random noise in the range [0.0, 1.0], as a function of x.
float Noise2d(in float2 x)
{
    float xhash = cos(x.x * 37.0);
    float yhash = cos(x.y * 57.0);
    return frac(415.92653 * (xhash + yhash));
}

// Convert Noise2d() into a "star field" by stomping everything below fThreshhold
// to zero.
float NoisyStarField(in float2 vSamplePos, float fThreshhold)
{
    float StarVal = Noise2d(vSamplePos);
    if (StarVal >= fThreshhold)
        StarVal = pow((StarVal - fThreshhold) / (1.0 - fThreshhold), 6.0);
    else
        StarVal = 0.0;
    return StarVal;
}

// Stabilize NoisyStarField() by only sampling at integer values.
float StableStarField(in float2 vSamplePos, float fThreshhold)
{
    // Linear interpolation between four samples.
    // Note: This approach has some visual artifacts.
    // There must be a better way to "anti alias" the star field.
    float fractX = frac(vSamplePos.x);
    float fractY = frac(vSamplePos.y);
    float2 floorSample = floor(vSamplePos);
    float v1 = NoisyStarField(floorSample, fThreshhold);
    float v2 = NoisyStarField(floorSample + float2(0.0, 1.0), fThreshhold);
    float v3 = NoisyStarField(floorSample + float2(1.0, 0.0), fThreshhold);
    float v4 = NoisyStarField(floorSample + float2(1.0, 1.0), fThreshhold);

    float StarVal = v1 * (1.0 - fractX) * (1.0 - fractY) +
                   v2 * (1.0 - fractX) * fractY + v3 * fractX * (1.0 - fractY) +
                   v4 * fractX * fractY;
    return StarVal;
}

void mainImage(out float4 fragColor, in float2 fragCoord)
{
    float2 iResolution;
    image.GetDimensions(iResolution.x, iResolution.y);

	float4 data1 = PushConstants.data1;

    // Sky Background Color
    // float3 vColor = float3(0.1, 0.2, 0.4) * fragCoord.y / iResolution.y;
    float3 vColor = data1.xyz * fragCoord.y / iResolution.y;

    // Note: Choose fThreshhold in the range [0.99, 0.9999].
    // Higher values (i.e., closer to one) yield a sparser starfield.
    float StarFieldThreshhold = data1.w; // 0.97;

    // Stars with a slow crawl.
    float xRate = 0.2;
    float yRate = -0.06;
    float2 vSamplePos = fragCoord.xy + float2(xRate * float(1), yRate * float(1));
    float StarVal = StableStarField(vSamplePos, StarFieldThreshhold);
    vColor += float3(StarVal, StarVal, StarVal);

    fragColor = float4(vColor, 1.0);
}

[numthreads(16, 16, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 value = float4(0.0, 0.0, 0.0, 1.0);
    int2 texelCoord = int2(DTid.xy);
    int2 size;
    image.GetDimensions(size.x, size.y);

    if (texelCoord.x < size.x && texelCoord.y < size.y)
    {
        float4 color;
        mainImage(color, texelCoord);

        image[texelCoord] = color;
    }
}
