// Thread group size definition - 16x16 threads per group
#define THREAD_GROUP_SIZE_X 16
#define THREAD_GROUP_SIZE_Y 16

// Resource binding - This texture will store our output image
RWTexture2D<float4> image : register(u0);

// Main compute shader function
// - numthreads decorator defines the thread group dimensions (equivalent to GLSL's local_size)
// - DTid (DispatchThreadID) - Global thread ID (equivalent to gl_GlobalInvocationID in GLSL)
// - GTid (GroupThreadID) - Thread ID within the current group (equivalent to
//   gl_LocalInvocationID in GLSL)
[numthreads(THREAD_GROUP_SIZE_X, THREAD_GROUP_SIZE_Y, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID)
{
	// Get the current pixel coordinate from the global thread ID
	int2 texelCoord = int2(DTid.xy);

	// Get the dimensions of our texture
	// This replaces imageSize() in GLSL
	uint width, height;
	image.GetDimensions(width, height);

	// Only process pixels within the bounds of the texture
	if (texelCoord.x < width && texelCoord.y < height)
	{
		// Initialize with black color (fully opaque)
		float4 color = float4(0.0, 0.0, 0.0, 1.0);

		// Skip border threads (where local IDs are 0)
		// This creates a grid pattern where the outer edge of each thread group is black
		if (GTid.x != 0 && GTid.y != 0)
		{
			// Calculate color based on normalized coordinates
			// Red channel increases with x position
			color.x = float(texelCoord.x) / (width);
			// Green channel increases with y position
			color.y = float(texelCoord.y) / (height);
		}

		// Write the calculated color to the texture
		// This replaces imageStore() in GLSL
		image[texelCoord] = color;
	}
}
