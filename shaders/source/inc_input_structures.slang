struct SceneData
{
    float4x4 view;
    float4x4 proj;
    float4x4 view_proj;
    float4 ambient_color;
    float4 sunlight_direction; // w for sun power
    float4 sunlight_color;
};

[[vk::binding(0, 0)]]
ParameterBlock<SceneData> scene_data;

struct GLTFMaterialData
{
    float4 color_factors;
    float4 metal_rough_factors;
};
[[vk::binding(0, 1)]]
ParameterBlock<GLTFMaterialData> material_data;

[[vk::binding(1, 1)]]
Sampler2D color_tex;
[[vk::binding(2, 1)]]
Sampler2D metal_rough_tex;
