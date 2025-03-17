struct VSOutput
{
    float4 pos : SV_Position;
    [vk_location(0)]
    float3 color : COLOR0;
};

[shader("vertex")]
VSOutput main(uint vertex_index: SV_VertexID)
{
    let positions = float3[3](
        float3(1.f, 1.f, 0.0f),
        float3(-1.f, 1.f, 0.0f),
        float3(0.f, -1.f, 0.0f));

    // Array of colors for the triangle
    let colors = float3[3](
        float3(1.0f, 0.0f, 0.0f), // red
        float3(0.0f, 1.0f, 0.0f), // green
        float3(0.0f, 0.0f, 1.0f)  // blue
    );

    VSOutput output;

    output.pos = float4(positions[vertex_index], 1.0f);
    output.color = colors[vertex_index];

    return output;
}
