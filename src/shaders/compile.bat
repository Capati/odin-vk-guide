@echo off
for /r %%i in (*.frag, *.vert, *.comp) do (
    %VULKAN_SDK%\Bin\glslangValidator -V %%i -o %%~ni.spv
)
