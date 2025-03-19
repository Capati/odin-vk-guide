#include "inc_input_structures.slang"

struct VSOutput
{
    float4 pos : SV_Position;
    [vk_location(0)]
    float3 outNormal : NORMAL;
    [vk_location(1)]
    float3 outColor : COLOR;
    [vk_location(2)]
    float2 outUV : TEXCOORD0;
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

    float4 position = float4(v.position, 1.0);
    VSOutput output;
    output.pos = mul(scene_data.view_proj, mul(push_constants.render_matrix, position));

    output.outNormal = (mul(push_constants.render_matrix, float4(v.normal, 0.0))).xyz;
    output.outColor = v.color.xyz * material_data.color_factors.xyz;
    output.outUV.x = v.uv_x;
    output.outUV.y = v.uv_y;

    return output;
}
