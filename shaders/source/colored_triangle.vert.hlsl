struct VSOutput {
    float4 Position : SV_POSITION;
    float3 Color : COLOR;
};

VSOutput main(uint vertexID : SV_VertexID)
{
    // const array of positions for the triangle
    const float3 positions[3] = {
        float3(1.0, 1.0, 0.0),
        float3(-1.0, 1.0, 0.0),
        float3(0.0, -1.0, 0.0)
    };

    // const array of colors for the triangle
    const float3 colors[3] = {
        float3(1.0, 0.0, 0.0), // red
        float3(0.0, 1.0, 0.0), // green
        float3(0.0, 0.0, 1.0)  // blue
    };

    VSOutput output;
    output.Position = float4(positions[vertexID], 1.0);
    output.Color = colors[vertexID];

    return output;
}
