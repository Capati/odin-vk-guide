package vk_bootstrap

// Core
import "core:log"

// Vendor
import vk "vendor:vulkan"

check_device_extension_support :: proc(
	available_extensions: ^[]vk.ExtensionProperties,
	required_extensions: []cstring,
) -> (
	supported: bool,
) {
	supported = true

	if len(required_extensions) == 0 || len(available_extensions) == 0 {
		return true
	}

	for avail_ext in available_extensions {
		for req_ext in required_extensions {
			if cstring(&avail_ext.extensionName[0]) != req_ext {
				log.warnf("Required extension [%s] is not available", req_ext)
				supported = false
			}
		}
	}

	return
}

check_device_features_support :: proc(
	supported: vk.PhysicalDeviceFeatures,
	requested: vk.PhysicalDeviceFeatures,
	extension_supported: ^[dynamic]Generic_Feature,
	extension_requested: ^[dynamic]Generic_Feature,
) -> bool {
	if requested.robustBufferAccess && !supported.robustBufferAccess do return false
	if requested.fullDrawIndexUint32 && !supported.fullDrawIndexUint32 do return false
	if requested.imageCubeArray && !supported.imageCubeArray do return false
	if requested.independentBlend && !supported.independentBlend do return false
	if requested.geometryShader && !supported.geometryShader do return false
	if requested.tessellationShader && !supported.tessellationShader do return false
	if requested.sampleRateShading && !supported.sampleRateShading do return false
	if requested.dualSrcBlend && !supported.dualSrcBlend do return false
	if requested.logicOp && !supported.logicOp do return false
	if requested.multiDrawIndirect && !supported.multiDrawIndirect do return false
	if requested.drawIndirectFirstInstance && !supported.drawIndirectFirstInstance do return false
	if requested.depthClamp && !supported.depthClamp do return false
	if requested.depthBiasClamp && !supported.depthBiasClamp do return false
	if requested.fillModeNonSolid && !supported.fillModeNonSolid do return false
	if requested.depthBounds && !supported.depthBounds do return false
	if requested.wideLines && !supported.wideLines do return false
	if requested.largePoints && !supported.largePoints do return false
	if requested.alphaToOne && !supported.alphaToOne do return false
	if requested.multiViewport && !supported.multiViewport do return false
	if requested.samplerAnisotropy && !supported.samplerAnisotropy do return false
	if requested.textureCompressionETC2 && !supported.textureCompressionETC2 do return false
	if requested.textureCompressionASTC_LDR && !supported.textureCompressionASTC_LDR do return false
	if requested.textureCompressionBC && !supported.textureCompressionBC do return false
	if requested.occlusionQueryPrecise && !supported.occlusionQueryPrecise do return false
	if requested.pipelineStatisticsQuery && !supported.pipelineStatisticsQuery do return false
	if requested.vertexPipelineStoresAndAtomics && !supported.vertexPipelineStoresAndAtomics do return false
	if requested.fragmentStoresAndAtomics && !supported.fragmentStoresAndAtomics do return false
	if requested.shaderTessellationAndGeometryPointSize && !supported.shaderTessellationAndGeometryPointSize do return false
	if requested.shaderImageGatherExtended && !supported.shaderImageGatherExtended do return false
	if requested.shaderStorageImageExtendedFormats && !supported.shaderStorageImageExtendedFormats do return false
	if requested.shaderStorageImageMultisample && !supported.shaderStorageImageMultisample do return false
	if requested.shaderStorageImageReadWithoutFormat && !supported.shaderStorageImageReadWithoutFormat do return false
	if requested.shaderStorageImageWriteWithoutFormat && !supported.shaderStorageImageWriteWithoutFormat do return false
	if requested.shaderUniformBufferArrayDynamicIndexing && !supported.shaderUniformBufferArrayDynamicIndexing do return false
	if requested.shaderSampledImageArrayDynamicIndexing && !supported.shaderSampledImageArrayDynamicIndexing do return false
	if requested.shaderStorageBufferArrayDynamicIndexing && !supported.shaderStorageBufferArrayDynamicIndexing do return false
	if requested.shaderStorageImageArrayDynamicIndexing && !supported.shaderStorageImageArrayDynamicIndexing do return false
	if requested.shaderClipDistance && !supported.shaderClipDistance do return false
	if requested.shaderCullDistance && !supported.shaderCullDistance do return false
	if requested.shaderFloat64 && !supported.shaderFloat64 do return false
	if requested.shaderInt64 && !supported.shaderInt64 do return false
	if requested.shaderInt16 && !supported.shaderInt16 do return false
	if requested.shaderResourceResidency && !supported.shaderResourceResidency do return false
	if requested.shaderResourceMinLod && !supported.shaderResourceMinLod do return false
	if requested.sparseBinding && !supported.sparseBinding do return false
	if requested.sparseResidencyBuffer && !supported.sparseResidencyBuffer do return false
	if requested.sparseResidencyImage2D && !supported.sparseResidencyImage2D do return false
	if requested.sparseResidencyImage3D && !supported.sparseResidencyImage3D do return false
	if requested.sparseResidency2Samples && !supported.sparseResidency2Samples do return false
	if requested.sparseResidency4Samples && !supported.sparseResidency4Samples do return false
	if requested.sparseResidency8Samples && !supported.sparseResidency8Samples do return false
	if requested.sparseResidency16Samples && !supported.sparseResidency16Samples do return false
	if requested.sparseResidencyAliased && !supported.sparseResidencyAliased do return false
	if requested.variableMultisampleRate && !supported.variableMultisampleRate do return false
	if requested.inheritedQueries && !supported.inheritedQueries do return false

	// Should only be false if extension_supported was unable to be filled out, due to the
	// physical device not supporting vk.GetPhysicalDeviceFeatures2 in any capacity.
	if len(extension_requested) != len(extension_supported) {
		return false
	}

	total := len(extension_requested)
	for i in 0 ..< total {
		if !generic_features_match(&extension_requested[i], &extension_supported[i]) {
			return false
		}
	}

	return true
}
