package vk_guide

// Vendor
import vk "vendor:vulkan"

command_pool_create_info :: proc(
	queueFamilyIndex: u32,
	flags: vk.CommandPoolCreateFlags = {},
) -> vk.CommandPoolCreateInfo {
	info := vk.CommandPoolCreateInfo{}
	info.sType = .COMMAND_POOL_CREATE_INFO
	info.pNext = nil
	info.queueFamilyIndex = queueFamilyIndex
	info.flags = flags
	return info
}

command_buffer_allocate_info :: proc(
	pool: vk.CommandPool,
	count: u32 = 1,
) -> vk.CommandBufferAllocateInfo {
	info := vk.CommandBufferAllocateInfo{}
	info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
	info.pNext = nil
	info.commandPool = pool
	info.commandBufferCount = count
	info.level = .PRIMARY
	return info
}

command_buffer_begin_info :: proc(
	flags: vk.CommandBufferUsageFlags = {},
) -> vk.CommandBufferBeginInfo {
	info := vk.CommandBufferBeginInfo{}
	info.sType = .COMMAND_BUFFER_BEGIN_INFO
	info.pNext = nil
	info.pInheritanceInfo = nil
	info.flags = flags
	return info
}

fence_create_info :: proc(flags: vk.FenceCreateFlags = {}) -> vk.FenceCreateInfo {
	info := vk.FenceCreateInfo{}
	info.sType = .FENCE_CREATE_INFO
	info.pNext = nil
	info.flags = flags
	return info
}

semaphore_create_info :: proc(flags: vk.SemaphoreCreateFlags = {}) -> vk.SemaphoreCreateInfo {
	info := vk.SemaphoreCreateInfo{}
	info.sType = .SEMAPHORE_CREATE_INFO
	info.pNext = nil
	info.flags = flags
	return info
}

semaphore_submit_info :: proc(
	stageMask: vk.PipelineStageFlags2,
	semaphore: vk.Semaphore,
) -> vk.SemaphoreSubmitInfo {
	submitInfo := vk.SemaphoreSubmitInfo{}
	submitInfo.sType = .SEMAPHORE_SUBMIT_INFO
	submitInfo.pNext = nil
	submitInfo.semaphore = semaphore
	submitInfo.stageMask = stageMask
	submitInfo.deviceIndex = 0
	submitInfo.value = 1
	return submitInfo
}

command_buffer_submit_info :: proc(cmd: vk.CommandBuffer) -> vk.CommandBufferSubmitInfo {
	info := vk.CommandBufferSubmitInfo{}
	info.sType = .COMMAND_BUFFER_SUBMIT_INFO
	info.pNext = nil
	info.commandBuffer = cmd
	info.deviceMask = 0
	return info
}

submit_info :: proc(
	cmd: ^vk.CommandBufferSubmitInfo,
	signalSemaphoreInfo: ^vk.SemaphoreSubmitInfo,
	waitSemaphoreInfo: ^vk.SemaphoreSubmitInfo,
) -> vk.SubmitInfo2 {
	info := vk.SubmitInfo2{}
	info.sType = .SUBMIT_INFO_2
	info.pNext = nil
	info.waitSemaphoreInfoCount = waitSemaphoreInfo == nil ? 0 : 1
	info.pWaitSemaphoreInfos = waitSemaphoreInfo
	info.signalSemaphoreInfoCount = signalSemaphoreInfo == nil ? 0 : 1
	info.pSignalSemaphoreInfos = signalSemaphoreInfo
	info.commandBufferInfoCount = 1
	info.pCommandBufferInfos = cmd
	return info
}

present_info :: proc() -> vk.PresentInfoKHR {
	info := vk.PresentInfoKHR{}
	info.sType = .PRESENT_INFO_KHR
	info.pNext = nil
	info.swapchainCount = 0
	info.pSwapchains = nil
	info.pWaitSemaphores = nil
	info.waitSemaphoreCount = 0
	info.pImageIndices = nil
	return info
}

attachment_info :: proc(
	view: vk.ImageView,
	clear: ^vk.ClearValue = nil,
	layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
) -> vk.RenderingAttachmentInfo {
	colorAttachment := vk.RenderingAttachmentInfo{}
	colorAttachment.sType = .RENDERING_ATTACHMENT_INFO
	colorAttachment.pNext = nil
	colorAttachment.imageView = view
	colorAttachment.imageLayout = layout
	colorAttachment.loadOp = clear != nil ? .CLEAR : .LOAD
	colorAttachment.storeOp = .STORE
	if clear != nil {
		colorAttachment.clearValue = clear^
	}
	return colorAttachment
}

depth_attachment_info :: proc(
	view: vk.ImageView,
	layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
) -> vk.RenderingAttachmentInfo {
	depthAttachment := vk.RenderingAttachmentInfo{}
	depthAttachment.sType = .RENDERING_ATTACHMENT_INFO
	depthAttachment.pNext = nil
	depthAttachment.imageView = view
	depthAttachment.imageLayout = layout
	depthAttachment.loadOp = .CLEAR
	depthAttachment.storeOp = .STORE
	depthAttachment.clearValue.depthStencil.depth = 0.0
	return depthAttachment
}

rendering_info :: proc(
	renderExtent: vk.Extent2D,
	colorAttachment: ^vk.RenderingAttachmentInfo,
	depthAttachment: ^vk.RenderingAttachmentInfo,
) -> vk.RenderingInfo {
	renderInfo := vk.RenderingInfo{}
	renderInfo.sType = .RENDERING_INFO
	renderInfo.pNext = nil
	renderInfo.renderArea = vk.Rect2D {
		offset = {0, 0},
		extent = renderExtent,
	}
	renderInfo.layerCount = 1
	renderInfo.colorAttachmentCount = 1
	renderInfo.pColorAttachments = colorAttachment
	renderInfo.pDepthAttachment = depthAttachment
	renderInfo.pStencilAttachment = nil
	return renderInfo
}

image_subresource_range :: proc(aspectMask: vk.ImageAspectFlags) -> vk.ImageSubresourceRange {
	subImage := vk.ImageSubresourceRange{}
	subImage.aspectMask = aspectMask
	subImage.baseMipLevel = 0
	subImage.levelCount = vk.REMAINING_MIP_LEVELS
	subImage.baseArrayLayer = 0
	subImage.layerCount = vk.REMAINING_ARRAY_LAYERS
	return subImage
}

descriptorset_layout_binding :: proc(
	type: vk.DescriptorType,
	stageFlags: vk.ShaderStageFlags,
	binding: u32,
) -> vk.DescriptorSetLayoutBinding {
	setbind := vk.DescriptorSetLayoutBinding{}
	setbind.binding = binding
	setbind.descriptorCount = 1
	setbind.descriptorType = type
	setbind.pImmutableSamplers = nil
	setbind.stageFlags = stageFlags
	return setbind
}

descriptorset_layout_create_info :: proc(
	bindings: ^vk.DescriptorSetLayoutBinding,
	bindingCount: u32,
) -> vk.DescriptorSetLayoutCreateInfo {
	info := vk.DescriptorSetLayoutCreateInfo{}
	info.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO
	info.pNext = nil
	info.pBindings = bindings
	info.bindingCount = bindingCount
	info.flags = {}
	return info
}

write_descriptor_image :: proc(
	type: vk.DescriptorType,
	dstSet: vk.DescriptorSet,
	imageInfo: ^vk.DescriptorImageInfo,
	binding: u32,
) -> vk.WriteDescriptorSet {
	write := vk.WriteDescriptorSet{}
	write.sType = .WRITE_DESCRIPTOR_SET
	write.pNext = nil
	write.dstBinding = binding
	write.dstSet = dstSet
	write.descriptorCount = 1
	write.descriptorType = type
	write.pImageInfo = imageInfo
	return write
}

write_descriptor_buffer :: proc(
	type: vk.DescriptorType,
	dstSet: vk.DescriptorSet,
	bufferInfo: ^vk.DescriptorBufferInfo,
	binding: u32,
) -> vk.WriteDescriptorSet {
	write := vk.WriteDescriptorSet{}
	write.sType = .WRITE_DESCRIPTOR_SET
	write.pNext = nil
	write.dstBinding = binding
	write.dstSet = dstSet
	write.descriptorCount = 1
	write.descriptorType = type
	write.pBufferInfo = bufferInfo
	return write
}

buffer_info :: proc(
	buffer: vk.Buffer,
	offset: vk.DeviceSize,
	range: vk.DeviceSize,
) -> vk.DescriptorBufferInfo {
	binfo := vk.DescriptorBufferInfo{}
	binfo.buffer = buffer
	binfo.offset = offset
	binfo.range = range
	return binfo
}

image_create_info :: proc(
	format: vk.Format,
	usageFlags: vk.ImageUsageFlags,
	extent: vk.Extent3D,
) -> vk.ImageCreateInfo {
	info := vk.ImageCreateInfo{}
	info.sType = .IMAGE_CREATE_INFO
	info.pNext = nil
	info.imageType = .D2
	info.format = format
	info.extent = extent
	info.mipLevels = 1
	info.arrayLayers = 1
	info.samples = {._1}
	info.tiling = .OPTIMAL
	info.usage = usageFlags
	return info
}

imageview_create_info :: proc(
	format: vk.Format,
	image: vk.Image,
	aspectFlags: vk.ImageAspectFlags,
) -> vk.ImageViewCreateInfo {
	info := vk.ImageViewCreateInfo{}
	info.sType = .IMAGE_VIEW_CREATE_INFO
	info.pNext = nil
	info.viewType = .D2
	info.image = image
	info.format = format
	info.subresourceRange.baseMipLevel = 0
	info.subresourceRange.levelCount = 1
	info.subresourceRange.baseArrayLayer = 0
	info.subresourceRange.layerCount = 1
	info.subresourceRange.aspectMask = aspectFlags
	return info
}

pipeline_layout_create_info :: proc() -> vk.PipelineLayoutCreateInfo {
	info := vk.PipelineLayoutCreateInfo{}
	info.sType = .PIPELINE_LAYOUT_CREATE_INFO
	info.pNext = nil
	info.flags = {}
	info.setLayoutCount = 0
	info.pSetLayouts = nil
	info.pushConstantRangeCount = 0
	info.pPushConstantRanges = nil
	return info
}

pipeline_shader_stage_create_info :: proc(
	stage: vk.ShaderStageFlags,
	shaderModule: vk.ShaderModule,
	entry: cstring,
) -> vk.PipelineShaderStageCreateInfo {
	info := vk.PipelineShaderStageCreateInfo{}
	info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
	info.pNext = nil
	info.stage = stage
	info.module = shaderModule
	info.pName = entry
	return info
}
