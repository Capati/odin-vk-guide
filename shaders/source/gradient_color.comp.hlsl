[[vk::push_constant]]
struct PushConstantsBlock
{
    float4 data1;
    float4 data2;
    float4 data3;
    float4 data4;
} PushConstants;

RWTexture2D<float4> image : register(u0, space0);

[numthreads(16, 16, 1)]
void main(uint3 GlobalInvocationID : SV_DispatchThreadID)
{
    int2 texelCoord = int2(GlobalInvocationID.xy);

    // Get image dimensions
    uint width, height;
    image.GetDimensions(width, height);
    int2 size = int2(width, height);

    float4 topColor = PushConstants.data1;
    float4 bottomColor = PushConstants.data2;

    if (texelCoord.x < size.x && texelCoord.y < size.y)
	{
        float blend = (float)texelCoord.y / (float)(size.y);

        // HLSL lerp is equivalent to GLSL mix
        image[texelCoord] = lerp(topColor, bottomColor, blend);
    }
}
