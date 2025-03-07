---
sidebar_position: 1
description: Instance, physical device, device, and swapchain setup.
---

# Vulkan initialization

Unlike OpenGL, which allowed you to execute graphics commands near-immediately, Vulkan has a
lengthy setup phase. To shorten this phase, we are going to use the library
`odin-vk-bootstrap`, which helps a lot with all of this boilerplate.

Vulkan is a very explicit API that gives very "direct" control, you need to initialize it to do
things such as load extensions, select which GPU (or multiple!) you are going to use, and
create the initial `vk.Instance` and `vk.Device` structures that you then use with Vulkan
commands.

Vulkan has no global state, unlike OpenGL, so you need to pass the `vk.Device` or `vk.Instance`
to every API function call. To simplify this process, we will use `odin-vk-bootstrap` to link
to Vulkan and the Odin Vulkan package to set all the function pointers, including extensions.

## vk.Instance

The root of everything is the `vk.Instance`. This represents a Vulkan API context. When creating
a `vk.Instance`, you can enable validation layers if you want, what instance extensions you
need, like `VK_KHR_surface`, and also hook a logger of your choosing for when the Vulkan driver
has errors or needs to log something. The main thing to do during instance creation is turning
on validation layers and instance extensions.

In general, applications only need to create a single `vk.Instance` for their entire run, as
it's just the global Vulkan context for your application.

## vk.PhysicalDevice

Once we have created a `vk.Instance`, we can query it for what GPUs are available in the system.

Vulkan allows us to get a list of what GPUs are in a system, and what their capabilities are.
All of this information is represented on the `vk.PhysicalDevice` handle, which is a reference
to the GPU. For example, in a dedicated gaming PC, there will likely only be 1
`vk.PhysicalDevice` available, which is the dedicated gaming GPU. In this case, there is no need
to choose between GPUs, as there is only one.

Where things get more interesting is in devices such as a laptop. Laptops often have 2 GPUs,
one being the CPU integrated one (low power), and other being the dedicated GPU (high power).
In such a case, an application will need to decide what GPU to use for the rendering, and
optimally, leave the choice for the user, in the case he might want to use the less powerful
dedicated GPU to preserve battery life.

Apart from choosing a GPU to use, `vk.PhysicalDevice` lets us query the features it has, the
memory size of the GPU, or what extensions are available. This is very important for advanced
applications where you want to know exactly how much VRAM you have available, and if the GPU
supports advanced features.

## vk.Device

Once we have the `vk.PhysicalDevice` of the GPU we are going to use, we can create a
`vk.Device` from it. This is the actual GPU driver on the GPU hardware, and the way we
communicate with said GPU. Most of Vulkan commands outside of debug utils or initialization
stuff need the `vk.Device`. A device is created with a list of extensions that you want to
enable. It is highly recommended you do not enable extensions you don't need, as they can cause
the driver to be slower due to checking extra things.

Your engine can handle multiple VkDevices at once, and this is the way to use multiple gpus
from the same program. This tutorial will not be doing that, but it can be useful to know if
you want do do things like running compute shaders across multiple GPUs.

## Swapchain

Initializing the GPU is nice, but we want to actually perform some rendering into the screen.
We use a swapchain for that. A swapchain is a OS/windowing provided structure with some images
we can draw to and then display on the screen. Swapchains are not in the core Vulkan spec as
they are optional, and often unique to the different platforms. If you are going to use Vulkan
for compute shader calculations, or for offline rendering, you do not need to setup a
swapchain.

A swapchain is created on a given size, and if the window resizes, you will have to recreate
the swapchain again.

The format that the swapchain exposes for its images can be different between platforms and
even GPUs, so it's necessary that you store the image format that the swapchain wants, as
rendering on a different format will cause artifacts or crashes.

Swapchains hold a list of images and image-views, accessible by the operating system for
display to the screen. You can create swapchains with more or less images, but generally you
will want only 2 or 3 images to perform double-buffer or triple-buffer rendering.

The most important thing when creating a swapchain is to select a Present Mode
(`vk.PresentModeKHR`), this controls how the swapchain sincronizes to the screen display.

You can see the full list of them with detailed explanation on the vulkan spec page here
[Vulkan Spec: VkPresentModeKHR][]

- `IMMEDIATE` Makes the swapchain not wait for anything, and accept instant pushing of images.
  This will likely result in tearing, generally not recommended.
- `FIFO` This will have a queue of images to present on refresh intervals. Once the queue is
  full the application will have to wait until the queue is popped by displaying the image.
  This is the "strong VSync" present mode, and it will lock your application to the FPS of your
  screen.
- `FIFO_RELAXED` . Mostly the same as Fifo VSync, but the VSync is adaptive. If the FPS of your
  application are lower than the optimal FPS of the screen, it will push the images
  immediately, likely resulting in tearing. For example, if your screen is a 60 HZ screen, and
  you are rendering at 55 HZ, this will not drop to the next vsync interval, making your
  general FPS drop to 30 like Fifo does, instead it will just display the images as still 55
  FPS, but with tearing.
- `MAILBOX` . This one has a list of images, and while one of them is being displayed by the
  screen, you will be continuously rendering to the others in the list. Whenever it's time to
  display an image, it will select the most recent one. This is the one you use if you want
  Triple-buffering without hard vsync.

`IMMEDIATE` is rarely used due to its tearing. Only in extreme low latency scenarios it might
be useful to allow the tearing.

Normal applications will use either `MAILBOX` or one of the 2 `FIFO` modes. Mostly depends if
you want a hard-vsync or you prefer triple-buffering.

In this guide, we will be using the `FIFO_RELAXED` mode, because it implements a upper cap on
our rendering speed, and as we aren't going to render many objects, it's best if the framerate
is capped and not reaching 5000 FPS which can cause issues like overheating. On real
applications that have some work to do, `MAILBOX` is likely going to be a better default.

[Vulkan Spec: VkPresentModeKHR]: https://registry.khronos.org/vulkan/specs/1.3-extensions/html/chap34.html#VkPresentModeKHR
