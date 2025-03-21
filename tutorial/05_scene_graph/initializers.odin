package vk_guide

// Vendor
import vk "vendor:vulkan"

command_pool_create_info :: proc(
	queueFamilyIndex: u32,
	flags: vk.CommandPoolCreateFlags = {},
) -> vk.CommandPoolCreateInfo {
	info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = queueFamilyIndex,
		flags            = flags,
	}
	return info
}

command_buffer_allocate_info :: proc(
	pool: vk.CommandPool,
	count: u32 = 1,
) -> vk.CommandBufferAllocateInfo {
	info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool,
		commandBufferCount = count,
		level              = .PRIMARY,
	}
	return info
}

command_buffer_begin_info :: proc(
	flags: vk.CommandBufferUsageFlags = {},
) -> vk.CommandBufferBeginInfo {
	info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = flags,
	}
	return info
}

fence_create_info :: proc(flags: vk.FenceCreateFlags = {}) -> vk.FenceCreateInfo {
	info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = flags,
	}
	return info
}

semaphore_create_info :: proc(flags: vk.SemaphoreCreateFlags = {}) -> vk.SemaphoreCreateInfo {
	info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
		flags = flags,
	}
	return info
}

semaphore_submit_info :: proc(
	stageMask: vk.PipelineStageFlags2,
	semaphore: vk.Semaphore,
) -> vk.SemaphoreSubmitInfo {
	submitInfo := vk.SemaphoreSubmitInfo {
		sType     = .SEMAPHORE_SUBMIT_INFO,
		semaphore = semaphore,
		stageMask = stageMask,
		value     = 1,
	}
	return submitInfo
}

command_buffer_submit_info :: proc(cmd: vk.CommandBuffer) -> vk.CommandBufferSubmitInfo {
	info := vk.CommandBufferSubmitInfo {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = cmd,
	}
	return info
}

submit_info :: proc(
	cmd: ^vk.CommandBufferSubmitInfo,
	signalSemaphoreInfo: ^vk.SemaphoreSubmitInfo,
	waitSemaphoreInfo: ^vk.SemaphoreSubmitInfo,
) -> vk.SubmitInfo2 {
	info := vk.SubmitInfo2 {
		sType                    = .SUBMIT_INFO_2,
		waitSemaphoreInfoCount   = waitSemaphoreInfo == nil ? 0 : 1,
		pWaitSemaphoreInfos      = waitSemaphoreInfo,
		signalSemaphoreInfoCount = signalSemaphoreInfo == nil ? 0 : 1,
		pSignalSemaphoreInfos    = signalSemaphoreInfo,
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = cmd,
	}
	return info
}

present_info :: proc() -> vk.PresentInfoKHR {
	info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
	}
	return info
}

attachment_info :: proc(
	view: vk.ImageView,
	clear: ^vk.ClearValue,
	layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
) -> vk.RenderingAttachmentInfo {
	colorAttachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = view,
		imageLayout = layout,
		loadOp      = clear != nil ? .CLEAR : .LOAD,
		storeOp     = .STORE,
	}
	if clear != nil {
		colorAttachment.clearValue = clear^
	}
	return colorAttachment
}

depth_attachment_info :: proc(
	view: vk.ImageView,
	layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
) -> vk.RenderingAttachmentInfo {
	depth_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = view,
		imageLayout = layout,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
	}
	depth_attachment.clearValue.depthStencil.depth = 0.0
	return depth_attachment
}

rendering_info :: proc(
	renderExtent: vk.Extent2D,
	colorAttachment: ^vk.RenderingAttachmentInfo,
	depthAttachment: ^vk.RenderingAttachmentInfo,
) -> vk.RenderingInfo {
	renderInfo := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = vk.Rect2D{extent = renderExtent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = colorAttachment,
		pDepthAttachment = depthAttachment,
	}
	return renderInfo
}

image_subresource_range :: proc(aspectMask: vk.ImageAspectFlags) -> vk.ImageSubresourceRange {
	subImage := vk.ImageSubresourceRange {
		aspectMask = aspectMask,
		levelCount = vk.REMAINING_MIP_LEVELS,
		layerCount = vk.REMAINING_ARRAY_LAYERS,
	}
	return subImage
}

descriptorset_layout_binding :: proc(
	type: vk.DescriptorType,
	stageFlags: vk.ShaderStageFlags,
	binding: u32,
) -> vk.DescriptorSetLayoutBinding {
	setbind := vk.DescriptorSetLayoutBinding {
		binding            = binding,
		descriptorCount    = 1,
		descriptorType     = type,
		pImmutableSamplers = nil,
		stageFlags         = stageFlags,
	}
	return setbind
}

descriptorset_layout_create_info :: proc(
	bindings: ^vk.DescriptorSetLayoutBinding,
	bindingCount: u32,
) -> vk.DescriptorSetLayoutCreateInfo {
	info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pBindings    = bindings,
		bindingCount = bindingCount,
	}
	return info
}

write_descriptor_image :: proc(
	type: vk.DescriptorType,
	dstSet: vk.DescriptorSet,
	imageInfo: ^vk.DescriptorImageInfo,
	binding: u32,
) -> vk.WriteDescriptorSet {
	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = binding,
		dstSet          = dstSet,
		descriptorCount = 1,
		descriptorType  = type,
		pImageInfo      = imageInfo,
	}
	return write
}

write_descriptor_buffer :: proc(
	type: vk.DescriptorType,
	dstSet: vk.DescriptorSet,
	bufferInfo: ^vk.DescriptorBufferInfo,
	binding: u32,
) -> vk.WriteDescriptorSet {
	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = binding,
		dstSet          = dstSet,
		descriptorCount = 1,
		descriptorType  = type,
		pBufferInfo     = bufferInfo,
	}
	return write
}

buffer_info :: proc(
	buffer: vk.Buffer,
	offset: vk.DeviceSize,
	range: vk.DeviceSize,
) -> vk.DescriptorBufferInfo {
	binfo := vk.DescriptorBufferInfo {
		buffer = buffer,
		offset = offset,
		range  = range,
	}
	return binfo
}

image_create_info :: proc(
	format: vk.Format,
	usageFlags: vk.ImageUsageFlags,
	extent: vk.Extent3D,
) -> vk.ImageCreateInfo {
	info := vk.ImageCreateInfo {
		sType       = .IMAGE_CREATE_INFO,
		imageType   = .D2,
		format      = format,
		extent      = extent,
		mipLevels   = 1,
		arrayLayers = 1,
		samples     = {._1},
		tiling      = .OPTIMAL,
		usage       = usageFlags,
	}
	return info
}

imageview_create_info :: proc(
	format: vk.Format,
	image: vk.Image,
	aspectFlags: vk.ImageAspectFlags,
) -> vk.ImageViewCreateInfo {
	info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		image = image,
		format = format,
		subresourceRange = {levelCount = 1, layerCount = 1, aspectMask = aspectFlags},
	}
	return info
}

pipeline_layout_create_info :: proc() -> vk.PipelineLayoutCreateInfo {
	info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}
	return info
}

pipeline_shader_stage_create_info :: proc(
	stage: vk.ShaderStageFlags,
	shaderModule: vk.ShaderModule,
	entry: cstring,
) -> vk.PipelineShaderStageCreateInfo {
	info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = stage,
		module = shaderModule,
		pName  = entry,
	}
	return info
}
