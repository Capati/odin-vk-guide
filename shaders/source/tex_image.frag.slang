struct PSInput
{
    [vk_location(0)]
    float3 color : COLOR;
    [vk_location(1)]
    float2 uv : TEXCOORD0;
};

struct PSOutput
{
    [vk_location(0)]
    float4 color : COLOR0;
};

[[vk::binding(0, 0)]]
Sampler2D display_texture;

[shader("fragment")]
PSOutput main(PSInput input)
{
    PSOutput output;
    output.color = display_texture.Sample(input.uv);
    return output;
}
