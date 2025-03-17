struct VSOutput
{
    float4 pos : SV_Position;
    [vk_location(0)]
    float3 color : COLOR0;
    [vk_location(1)]
    float2 uv : TEXCOORD0;
};

struct Vertex
{
    float3 position;
    float uv_x;
    float3 normal;
    float uv_y;
    float4 color;
};

struct PushConstants
{
    float4x4 render_matrix;
    Vertex *vertex_buffer;
};

[vk_push_constant]
PushConstants push_constants;

[shader("vertex")]
VSOutput main(uint vertex_index: SV_VertexID)
{
    Vertex v = push_constants.vertex_buffer[vertex_index];

    VSOutput output;
    output.pos = mul(push_constants.render_matrix, float4(v.position, 1.0));
    output.color = v.color.xyz;
    output.uv.x = v.uv_x;
    output.uv.y = v.uv_y;

    return output;
}
