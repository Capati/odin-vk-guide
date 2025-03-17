struct PSInput
{
    [vk_location(0)]
    float3 color : COLOR0;
};

struct PSOutput
{
    [vk_location(0)]
    float4 frag_color : COLOR0;
};

[shader("fragment")]
PSOutput main(PSInput input)
{
    PSOutput output;
    output.frag_color = float4(input.color, 1.f);

    return output;
}
