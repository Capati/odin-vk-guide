package main

// Vendor
import vk "vendor:vulkan"

command_pool_create_info :: proc(
	queue_family_index: u32,
	flags: vk.CommandPoolCreateFlags = {},
) -> (
	info: vk.CommandPoolCreateInfo,
) {
	info = vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = queue_family_index,
		flags            = flags,
	}

	return
}

command_buffer_allocate_info :: proc(
	pool: vk.CommandPool,
	count: u32,
) -> (
	info: vk.CommandBufferAllocateInfo,
) {
	info = vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool,
		commandBufferCount = count,
		level              = .PRIMARY,
	}

	return
}

command_buffer_begin_info :: proc(
	flags: vk.CommandBufferUsageFlags = {},
) -> (
	info: vk.CommandBufferBeginInfo,
) {
	info = vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = flags,
	}

	return
}

fence_create_info :: proc(flags: vk.FenceCreateFlags = {}) -> (info: vk.FenceCreateInfo) {
	info = vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = flags,
	}

	return
}

semaphore_create_info :: proc(
	flags: vk.SemaphoreCreateFlags = {},
) -> (
	info: vk.SemaphoreCreateInfo,
) {
	info = vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
		flags = flags,
	}

	return
}

semaphore_submit_info :: proc(
	stage_mask: vk.PipelineStageFlags2,
	semaphore: vk.Semaphore,
) -> (
	info: vk.SemaphoreSubmitInfo,
) {
	info = vk.SemaphoreSubmitInfo {
		sType       = .SEMAPHORE_SUBMIT_INFO,
		semaphore   = semaphore,
		stageMask   = stage_mask,
		deviceIndex = 0,
		value       = 1,
	}

	return
}

command_buffer_submit_info :: proc(cmd: vk.CommandBuffer) -> (info: vk.CommandBufferSubmitInfo) {
	info = vk.CommandBufferSubmitInfo {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = cmd,
		deviceMask    = 0,
	}

	return info
}

submit_info :: proc(
	cmd: ^vk.CommandBufferSubmitInfo,
	signal_semaphore_info: ^vk.SemaphoreSubmitInfo,
	wait_semaphore_info: ^vk.SemaphoreSubmitInfo,
) -> (
	info: vk.SubmitInfo2,
) {
	info = vk.SubmitInfo2 {
		sType                    = .SUBMIT_INFO_2,
		waitSemaphoreInfoCount   = wait_semaphore_info == nil ? 0 : 1,
		pWaitSemaphoreInfos      = wait_semaphore_info,
		signalSemaphoreInfoCount = signal_semaphore_info == nil ? 0 : 1,
		pSignalSemaphoreInfos    = signal_semaphore_info,
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = cmd,
	}

	return info
}

// VkPresentInfoKHR vkinit::present_info()
// {
//     VkPresentInfoKHR info = {};
//     info.sType =  VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
//     info.pNext = 0;

//     info.swapchainCount = 0;
//     info.pSwapchains = nullptr;
//     info.pWaitSemaphores = nullptr;
//     info.waitSemaphoreCount = 0;
//     info.pImageIndices = nullptr;

//     return info;
// }

// //> color_info
// VkRenderingAttachmentInfo vkinit::attachment_info(
//     VkImageView view, VkClearValue* clear ,VkImageLayout layout /*= VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL*/)
// {
//     VkRenderingAttachmentInfo colorAttachment {};
//     colorAttachment.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
//     colorAttachment.pNext = nullptr;

//     colorAttachment.imageView = view;
//     colorAttachment.imageLayout = layout;
//     colorAttachment.loadOp = clear ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_LOAD;
//     colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
//     if (clear) {
//         colorAttachment.clearValue = *clear;
//     }

//     return colorAttachment;
// }
// //< color_info
// //> depth_info
// VkRenderingAttachmentInfo vkinit::depth_attachment_info(
//     VkImageView view, VkImageLayout layout /*= VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL*/)
// {
//     VkRenderingAttachmentInfo depthAttachment {};
//     depthAttachment.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
//     depthAttachment.pNext = nullptr;

//     depthAttachment.imageView = view;
//     depthAttachment.imageLayout = layout;
//     depthAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
//     depthAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
//     depthAttachment.clearValue.depthStencil.depth = 0.f;

//     return depthAttachment;
// }
// //< depth_info
// //> render_info
// VkRenderingInfo vkinit::rendering_info(VkExtent2D renderExtent, VkRenderingAttachmentInfo* colorAttachment,
//     VkRenderingAttachmentInfo* depthAttachment)
// {
//     VkRenderingInfo renderInfo {};
//     renderInfo.sType = VK_STRUCTURE_TYPE_RENDERING_INFO;
//     renderInfo.pNext = nullptr;

//     renderInfo.renderArea = VkRect2D { VkOffset2D { 0, 0 }, renderExtent };
//     renderInfo.layerCount = 1;
//     renderInfo.colorAttachmentCount = 1;
//     renderInfo.pColorAttachments = colorAttachment;
//     renderInfo.pDepthAttachment = depthAttachment;
//     renderInfo.pStencilAttachment = nullptr;

//     return renderInfo;
// }
// //< render_info
// //> subresource

image_subresource_range :: proc(
	aspect_mask: vk.ImageAspectFlags,
) -> (
	info: vk.ImageSubresourceRange,
) {
	info = vk.ImageSubresourceRange {
		aspectMask     = aspect_mask,
		baseMipLevel   = 0,
		levelCount     = vk.REMAINING_MIP_LEVELS,
		baseArrayLayer = 0,
		layerCount     = vk.REMAINING_ARRAY_LAYERS,
	}

	return
}

// VkDescriptorSetLayoutBinding vkinit::descriptorset_layout_binding(VkDescriptorType type, VkShaderStageFlags stageFlags,
//     uint32_t binding)
// {
//     VkDescriptorSetLayoutBinding setbind = {};
//     setbind.binding = binding;
//     setbind.descriptorCount = 1;
//     setbind.descriptorType = type;
//     setbind.pImmutableSamplers = nullptr;
//     setbind.stageFlags = stageFlags;

//     return setbind;
// }

// VkDescriptorSetLayoutCreateInfo vkinit::descriptorset_layout_create_info(VkDescriptorSetLayoutBinding* bindings,
//     uint32_t bindingCount)
// {
//     VkDescriptorSetLayoutCreateInfo info = {};
//     info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
//     info.pNext = nullptr;

//     info.pBindings = bindings;
//     info.bindingCount = bindingCount;
//     info.flags = 0;

//     return info;
// }

// VkWriteDescriptorSet vkinit::write_descriptor_image(VkDescriptorType type, VkDescriptorSet dstSet,
//     VkDescriptorImageInfo* imageInfo, uint32_t binding)
// {
//     VkWriteDescriptorSet write = {};
//     write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
//     write.pNext = nullptr;

//     write.dstBinding = binding;
//     write.dstSet = dstSet;
//     write.descriptorCount = 1;
//     write.descriptorType = type;
//     write.pImageInfo = imageInfo;

//     return write;
// }

// VkWriteDescriptorSet vkinit::write_descriptor_buffer(VkDescriptorType type, VkDescriptorSet dstSet,
//     VkDescriptorBufferInfo* bufferInfo, uint32_t binding)
// {
//     VkWriteDescriptorSet write = {};
//     write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
//     write.pNext = nullptr;

//     write.dstBinding = binding;
//     write.dstSet = dstSet;
//     write.descriptorCount = 1;
//     write.descriptorType = type;
//     write.pBufferInfo = bufferInfo;

//     return write;
// }

// VkDescriptorBufferInfo vkinit::buffer_info(VkBuffer buffer, VkDeviceSize offset, VkDeviceSize range)
// {
//     VkDescriptorBufferInfo binfo {};
//     binfo.buffer = buffer;
//     binfo.offset = offset;
//     binfo.range = range;
//     return binfo;
// }

image_create_info :: proc(
	format: vk.Format,
	usage_flags: vk.ImageUsageFlags,
	extent: vk.Extent3D,
) -> (
	info: vk.ImageCreateInfo,
) {
	info = vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format = format,
		extent = extent,
		mipLevels = 1,
		arrayLayers = 1,
		// For MSAA. we will not be using it by default, so default it to 1 sample per pixel.
		samples = {._1},
		// Optimal tiling, which means the image is stored on the best gpu format
		tiling = .OPTIMAL,
		usage = usage_flags,
	}

	return
}

imageview_create_info :: proc(
	format: vk.Format,
	image: vk.Image,
	aspect_flags: vk.ImageAspectFlags,
) -> (
	info: vk.ImageViewCreateInfo,
) {
	// Build a image-view for the depth image to use for rendering
	info = vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		image = image,
		format = format,
		subresourceRange =  {
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
			aspectMask = aspect_flags,
		},
	}

	return
}

// VkPipelineLayoutCreateInfo vkinit::pipeline_layout_create_info()
// {
//     VkPipelineLayoutCreateInfo info {};
//     info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
//     info.pNext = nullptr;

//     // empty defaults
//     info.flags = 0;
//     info.setLayoutCount = 0;
//     info.pSetLayouts = nullptr;
//     info.pushConstantRangeCount = 0;
//     info.pPushConstantRanges = nullptr;
//     return info;
// }

// VkPipelineShaderStageCreateInfo vkinit::pipeline_shader_stage_create_info(VkShaderStageFlagBits stage,
//     VkShaderModule shaderModule,
//     const char * entry)
// {
//     VkPipelineShaderStageCreateInfo info {};
//     info.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
//     info.pNext = nullptr;

//     // shader stage
//     info.stage = stage;
//     // module containing the code for this shader stage
//     info.module = shaderModule;
//     // the entry point of the shader
//     info.pName = entry;
//     return info;
// }
