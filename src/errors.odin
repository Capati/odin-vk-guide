package main

// Libs
import "libs:vk-bootstrap/vkb"

Window_Error :: enum {
	None,
	SDL_Init_Failed,
	Create_Window_Failed,
}

Error :: union #shared_nil {
	Window_Error,
	vkb.Error,
}
