struct PushConstants
{
    float4 data1;
    float4 data2;
    float4 data3;
    float4 data4;
};

[[vk_push_constant]]
PushConstants push_constants;

RWTexture2D<float4> image;

[shader("compute")]
[numthreads(16, 16, 1)]
void main(uint3 globalID: SV_DispatchThreadID)
{
    uint2 texelCoord = globalID.xy;

    uint2 size;
    image.GetDimensions(size.x, size.y);

    float4 topColor = push_constants.data1;
    float4 bottomColor = push_constants.data2;

    if (texelCoord.x < size.x && texelCoord.y < size.y)
    {
        float blend = float(texelCoord.y) / float(size.y);

        image[texelCoord] = lerp(topColor, bottomColor, blend);
    }
}
