RWTexture2D<float4> image;

[shader("compute")]
[numthreads(16, 16, 1)]
void main(
    uint3 dispatchThreadID: SV_DispatchThreadID,
    uint3 groupThreadID: SV_GroupThreadID)
{
    int2 texelCoord = int2(dispatchThreadID.xy);
    var size = uint2(0, 0);
    image.GetDimensions(size.x, size.y);

    if (texelCoord.x < size.x && texelCoord.y < size.y)
    {
        float4 color = float4(0.0, 0.0, 0.0, 1.0);

        if (groupThreadID.x != 0 && groupThreadID.y != 0)
        {
            color.x = float(texelCoord.x) / float(size.x);
            color.y = float(texelCoord.y) / float(size.y);
        }

        image[texelCoord] = color;
    }
}
